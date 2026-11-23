#!/bin/bash
# DAYER on the RIVQAN server: dayer.rivqan.com
# Safe for RIVQAN: own folder (/opt/dayer), own container (dayer-web), one Caddy block appended
# with backup + validate + automatic rollback. Re-run any time to update to the latest version.
set -u
DOMAIN=dayer.rivqan.com
DIR=/opt/dayer
CF=/opt/rivqan/Caddyfile
C=rivqan-caddy-1
SRC=https://raw.githubusercontent.com/elghawabya-afk/dayer/main/index.html
say(){ echo "== $*"; }

# 0) preconditions
[ -f "$CF" ] || { echo "ERROR: $CF not found"; exit 1; }
docker inspect "$C" >/dev/null 2>&1 || { echo "ERROR: container $C not found"; exit 1; }

# 1) app file (download to temp, check it is the DAYER page, then swap in)
mkdir -p "$DIR"
TMP=$(mktemp)
curl -fsSL "$SRC?t=$(date +%s)" -o "$TMP" || { echo "ERROR: download failed"; exit 1; }
grep -q "DAYER" "$TMP" && [ "$(stat -c%s "$TMP")" -gt 500000 ] || { echo "ERROR: downloaded file is not the DAYER app"; rm -f "$TMP"; exit 1; }
[ -f "$DIR/index.html" ] && cp "$DIR/index.html" "$DIR/index.html.prev"
mv "$TMP" "$DIR/index.html"; chmod 644 "$DIR/index.html"
say "app file: $(sha256sum "$DIR/index.html" | cut -c1-16)  ($(stat -c%s "$DIR/index.html") bytes)"

# 2) small web container on the same Docker network as Caddy
NET=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$C" | awk '{print $1}')
if ! docker inspect dayer-web >/dev/null 2>&1; then
  docker run -d --name dayer-web --restart unless-stopped --network "$NET" \
    -v "$DIR":/usr/share/nginx/html:ro nginx:1.27-alpine >/dev/null && say "dayer-web started on network $NET"
else
  docker start dayer-web >/dev/null 2>&1; say "dayer-web already exists (file updated in place)"
fi

# 3) Caddy route (append once, validate, roll back on failure)
if grep -q "^$DOMAIN" "$CF"; then
  say "Caddy block already present"
else
  cp "$CF" "$CF.bak-dayer-$(date +%s)"
  cat >> "$CF" <<BLOCK

$DOMAIN {
	encode gzip
	header Strict-Transport-Security "max-age=31536000"
	header X-Content-Type-Options "nosniff"
	header Referrer-Policy "strict-origin-when-cross-origin"
	header Cache-Control "no-cache"
	reverse_proxy dayer-web:80
}
BLOCK
  if docker exec "$C" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    docker exec "$C" caddy reload --config /etc/caddy/Caddyfile >/dev/null && say "Caddy reloaded"
  else
    echo "VALIDATION FAILED - rolling back, RIVQAN untouched"
    cp "$(ls -t $CF.bak-dayer-* | head -1)" "$CF"; exit 1
  fi
fi

# 4) checks
sleep 3
say "inside: $(docker exec "$C" wget -qO- http://dayer-web/ 2>/dev/null | grep -c DAYER) (should be 1 or more)"
MYIP=$(curl -fsS -4 https://ifconfig.me 2>/dev/null)
DNSIP=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')
say "server IP: ${MYIP:-?}   $DOMAIN -> ${DNSIP:-NOT FOUND}"
if [ -z "$DNSIP" ]; then
  echo ">> DNS missing: add an A record  dayer  ->  $MYIP  (where rivqan.com DNS is managed), then wait a few minutes."
else
  say "public: $(curl -s -o /dev/null -w '%{http_code}' https://$DOMAIN/) (200 = live)"
fi
say "rivqan.com still: $(curl -s -o /dev/null -w '%{http_code}' https://rivqan.com/)"
