#!/bin/bash
# Puts the DAYER app link (https://dayer.rivqan.com) with a "قريبًا" label on rivqan.com and elghawaby.rivqan.com.
# Safe: only replaces the existing DAYER placeholders; keeps a backup of every file it changes; idempotent.
# Installs itself to /usr/local/bin and a cron (every 15 min) so a site re-install doesn't remove the link.
set -u
URL=https://dayer.rivqan.com
LOG=/var/log/dayer-links.log
say(){ echo "== $*"; }
cp -f "$0" /usr/local/bin/dayer-links.sh 2>/dev/null; chmod +x /usr/local/bin/dayer-links.sh 2>/dev/null
echo "*/15 * * * * root /usr/local/bin/dayer-links.sh >> $LOG 2>&1" > /etc/cron.d/dayer-links

cat > /tmp/dayer_patch.py <<PY
import sys,io,os,shutil,time
URL="$URL"
R=[
 ('<span class="badge">تطبيق DAYER — الرابط بانتظار الاعتماد</span>',
  '<a class="btn" href="'+URL+'" target="_blank" rel="noopener">افتح تطبيق DAYER</a><span class="badge">قريبًا</span>'),
 ('<span class="badge">DAYER app — link awaiting approval</span>',
  '<a class="btn" href="'+URL+'" target="_blank" rel="noopener">Open the DAYER app</a><span class="badge">Coming soon</span>'),
 ('href="/ar/dayer/"><span class="badge">GROUP COMPANY</span>','href="/ar/dayer/"><span class="badge">GROUP COMPANY · قريبًا</span>'),
 ('href="/en/dayer/"><span class="badge">GROUP COMPANY</span>','href="/en/dayer/"><span class="badge">GROUP COMPANY · COMING SOON</span>'),
 ('dayer:    \\\\"#app\\\\"','dayer:    \\\\"'+URL+'\\\\"'),
 ('dayer:    "#app"','dayer:    "'+URL+'"'),
]
n=0
for p in sys.argv[1:]:
    try: s=io.open(p,encoding='utf-8').read()
    except Exception: continue
    t=s
    for a,b in R: t=t.replace(a,b)
    if t!=s:
        shutil.copy2(p,p+'.bak-dayer-'+str(int(time.time())))
        io.open(p,'w',encoding='utf-8').write(t); n+=1; print('patched',p)
print('files changed:',n)
PY

# 1) RIVQAN website files on the host (/opt, docker volumes)
F=$(grep -rlI -e 'الرابط بانتظار الاعتماد' -e 'link awaiting approval' -e 'href="/ar/dayer/"><span class="badge">GROUP COMPANY</span>' /opt /srv /var/www /var/lib/docker/volumes 2>/dev/null | grep -v '\.bak-dayer-' | grep -v '/elghawaby/' )
if [ -n "$F" ]; then say "rivqan site (host files)"; python3 /tmp/dayer_patch.py $F; else say "rivqan site: no host files with the placeholder (already linked, or files are inside a container)"; fi
# files baked inside running containers
for c in $(docker ps --format '{{.Names}}' | grep -v -e '^dayer-web$'); do
  L=$(docker exec "$c" sh -c "grep -rlI -e 'الرابط بانتظار الاعتماد' -e 'link awaiting approval' -e 'GROUP COMPANY</span><b>DAYER' /usr/share/nginx /srv /app /var/www /site /public /usr/src 2>/dev/null" 2>/dev/null)
  [ -z "$L" ] && continue
  say "inside container $c"
  for f in $L; do docker cp "$c:$f" /tmp/dl.html && python3 /tmp/dayer_patch.py /tmp/dl.html >/dev/null && docker cp /tmp/dl.html "$c:$f" && echo "patched $c:$f"; done
done

# 2) Elghawaby site (CONFIG.dayer in worker.mjs), restart only if changed
W=/opt/elghawaby/worker.mjs
if [ -f "$W" ] && grep -q 'dayer: *\\\?"#app' "$W"; then
  say "elghawaby site"; python3 /tmp/dayer_patch.py "$W"; chown elghawaby:elghawaby "$W" 2>/dev/null
  systemctl restart elghawaby && sleep 2 && say "elghawaby restarted"
else
  say "elghawaby: already linked (or worker.mjs not found)"
fi

# 3) checks
sleep 1
say "rivqan.com/ar/dayer/ has link: $(curl -s https://rivqan.com/ar/dayer/ | grep -c 'dayer.rivqan.com')"
say "rivqan.com/en/dayer/ has link: $(curl -s https://rivqan.com/en/dayer/ | grep -c 'dayer.rivqan.com')"
say "elghawaby has link: $(curl -s https://elghawaby.rivqan.com/ | grep -c 'dayer.rivqan.com')"
say "sites: rivqan $(curl -s -o /dev/null -w '%{http_code}' https://rivqan.com/ar/)  elghawaby $(curl -s -o /dev/null -w '%{http_code}' https://elghawaby.rivqan.com/)  dayer $(curl -s -o /dev/null -w '%{http_code}' $URL/)"
