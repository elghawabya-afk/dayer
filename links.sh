#!/bin/bash
# Puts the DAYER app link (https://dayer.rivqan.com) with a "قريبًا" label on rivqan.com and elghawaby.rivqan.com.
# rivqan.com is a Next.js export: the text lives in the HTML, in the inline page data (escaped) and in *.txt payloads;
# all three are patched so the page shows the link on direct load AND when navigating inside the site.
# Safe: only replaces the existing DAYER placeholders; backup before each change; idempotent; re-applied every 15 min.
set -u
export DAYER_URL=https://dayer.rivqan.com
LOG=/var/log/dayer-links.log
say(){ echo "== $*"; }
cp -f "$0" /usr/local/bin/dayer-links.sh 2>/dev/null; chmod +x /usr/local/bin/dayer-links.sh 2>/dev/null
echo "*/15 * * * * root /usr/local/bin/dayer-links.sh >> $LOG 2>&1" > /etc/cron.d/dayer-links

cat > /tmp/dayer_patch.py <<'PY'
import sys, io, os, shutil, time
U = os.environ.get("DAYER_URL", "https://dayer.rivqan.com")
def rsc(q):
    s = lambda x: q + x + q
    def badge(txt): return "[" + s("$") + "," + s("span") + ",null,{" + s("className") + ":" + s("badge") + "," + s("children") + ":" + s(txt) + "}]"
    def link(txt): return ("[" + s("$") + "," + s("a") + ",null,{" + s("className") + ":" + s("btn") + "," + s("href") + ":" + s(U) + ","
                           + s("target") + ":" + s("_blank") + "," + s("rel") + ":" + s("noopener") + "," + s("children") + ":" + s(txt) + "}]")
    def card(lang, label):
        head = s("href") + ":" + s("/" + lang + "/dayer") + "," + s("className") + ":" + s("kid") + "," + s("children") + ":[" + badge("GROUP COMPANY")
        return head, head.replace(s("GROUP COMPANY"), s("GROUP COMPANY · " + label))
    return [
        (badge("تطبيق DAYER — الرابط بانتظار الاعتماد"), link("افتح تطبيق DAYER") + "," + badge("قريبًا")),
        (badge("DAYER app — link awaiting approval"), link("Open the DAYER app") + "," + badge("Coming soon")),
        card("ar", "قريبًا"), card("en", "COMING SOON"),
    ]
R = [
    ('<span class="badge">تطبيق DAYER — الرابط بانتظار الاعتماد</span>',
     '<a class="btn" href="' + U + '" target="_blank" rel="noopener">افتح تطبيق DAYER</a><span class="badge">قريبًا</span>'),
    ('<span class="badge">DAYER app — link awaiting approval</span>',
     '<a class="btn" href="' + U + '" target="_blank" rel="noopener">Open the DAYER app</a><span class="badge">Coming soon</span>'),
    ('href="/ar/dayer/"><span class="badge">GROUP COMPANY</span>', 'href="/ar/dayer/"><span class="badge">GROUP COMPANY · قريبًا</span>'),
    ('href="/en/dayer/"><span class="badge">GROUP COMPANY</span>', 'href="/en/dayer/"><span class="badge">GROUP COMPANY · COMING SOON</span>'),
    ('dayer:    \\"#app\\"', 'dayer:    \\"' + U + '\\"'),
    ('dayer:    "#app"', 'dayer:    "' + U + '"'),
] + rsc('"') + rsc('\\"')
n = 0
for p in sys.argv[1:]:
    try: s = io.open(p, encoding="utf-8").read()
    except Exception: continue
    t = s
    for a, b in R: t = t.replace(a, b)
    if t != s:
        shutil.copy2(p, p + ".bak-dayer-" + str(int(time.time())))
        io.open(p, "w", encoding="utf-8").write(t); n += 1; print("patched", p)
print("files changed:", n)
PY

# 1) RIVQAN website files (host side; the Caddy container mounts them read-only)
F=$(grep -rlI -e 'الرابط بانتظار الاعتماد' -e 'link awaiting approval' -e 'GROUP COMPANY' /opt/rivqan /srv /var/www /var/lib/docker/volumes 2>/dev/null | grep -v -e '\.bak-dayer-' -e '\.bak-' )
if [ -n "$F" ]; then say "rivqan site"; python3 /tmp/dayer_patch.py $F; else say "rivqan site: nothing to change"; fi

# 2) Elghawaby site (CONFIG.dayer in worker.mjs), restart only if changed
W=/opt/elghawaby/worker.mjs
if [ -f "$W" ] && grep -q 'dayer: *\\\?"#app' "$W"; then
  say "elghawaby site"; python3 /tmp/dayer_patch.py "$W"; chown elghawaby:elghawaby "$W" 2>/dev/null
  systemctl restart elghawaby && sleep 2 && say "elghawaby restarted"
else
  say "elghawaby: already linked"
fi

# 3) checks (0 = good for "old text left")
sleep 1
say "old text left on rivqan (ar/en, html+data): $(for u in /ar/dayer/ /ar/dayer/index.txt /en/dayer/ /en/dayer/index.txt; do curl -s https://rivqan.com$u; done | grep -c -e 'بانتظار الاعتماد' -e 'awaiting approval')"
say "rivqan dayer pages with link: $(for u in /ar/dayer/ /ar/dayer/index.txt /en/dayer/ /en/dayer/index.txt; do curl -s https://rivqan.com$u | grep -q 'dayer.rivqan.com' && echo x; done | wc -l) of 4"
say "elghawaby has link: $(curl -s https://elghawaby.rivqan.com/ | grep -c 'dayer.rivqan.com')"
say "sites: rivqan $(curl -s -o /dev/null -w '%{http_code}' https://rivqan.com/ar/)  elghawaby $(curl -s -o /dev/null -w '%{http_code}' https://elghawaby.rivqan.com/)  dayer $(curl -s -o /dev/null -w '%{http_code}' $DAYER_URL/)"
