#!/usr/bin/env python3
"""Compose the README/overview hero image page from a noir PTY transcript.

Usage: hero.py <scan.ansi> <out.html>

The page is a fixed 1680x1340 canvas: the demo app's source on the left, a
JSON excerpt below it, and the real `noir scan -P -T` transcript on the right.
build.sh screenshots it with headless Chrome at 2x and writes the JPG.

Only the transcript is captured; the source and JSON panels are typed here so
they stay short enough to read at README width. Keep them in sync with
docs/tools/cli-capture/demo-app/src/app.cr (the routes and parameter names
must match what the terminal panel shows).
"""
import html, re, sys

ansi_path, out_path = sys.argv[1], sys.argv[2]
here = __file__.rsplit("/", 1)[0] if "/" in __file__ else "."
IMAGES = here + "/../../static/images"

# 16-colour palette the transcript is rendered with (noir only emits the
# basic 3x/9x codes plus 38;5;81 for the banner).
PAL = {30: "#3b3b40", 31: "#ff5f57", 32: "#4ade80", 33: "#f5c542", 34: "#6ea8ff",
       35: "#ff6ac1", 36: "#5fd7ff", 37: "#e6e6e8", 90: "#7a7a82", 91: "#ff6b64",
       92: "#7dffa4", 93: "#ffd75f", 94: "#82b4ff", 95: "#ff8ad0", 96: "#8ae7ff",
       97: "#ffffff"}
X256 = {81: "#5fd7ff"}


def ansi_to_html(text):
    text = text.replace("^D\x08\x08", "").replace("\x04", "")
    text = text.replace("\r\n", "\n").replace("\r", "")
    text = re.sub(r"\x1b\[[0-9;?]*[A-LN-Zln]", "", text)
    out, fg, bold, pos = [], None, False, 0
    for m in re.finditer(r"\x1b\[([0-9;]*)m", text):
        seg = text[pos:m.start()]
        pos = m.end()
        if seg:
            st = []
            if fg:
                st.append(f"color:{fg}")
            if bold:
                st.append("font-weight:600")
            out.append(f'<span style="{";".join(st)}">{html.escape(seg)}</span>' if st else html.escape(seg))
        nums = [int(x) for x in m.group(1).split(";") if x] or [0]
        i = 0
        while i < len(nums):
            c = nums[i]
            if c == 0:
                fg, bold = None, False
            elif c == 1:
                bold = True
            elif c == 22:
                bold = False
            elif c == 39:
                fg = None
            elif c in PAL:
                fg = PAL[c]
            elif c == 38 and i + 2 < len(nums) and nums[i + 1] == 5:
                fg = X256.get(nums[i + 2], "#5fd7ff")
                i += 2
            i += 1
    out.append(html.escape(text[pos:]))
    return "".join(out).strip("\n")


term = ansi_to_html(open(ansi_path, encoding="utf-8", errors="replace").read())

CODE = '''<span class=k>require</span> <span class=s>"kemal"</span>

<span class=r><span class=k>get</span> <span class=s>"/"</span> <span class=k>do</span> |env|</span>
  env.request.headers[<span class=s>"x-api-key"</span>]
  <span class=s>"Welcome!"</span>
<span class=k>end</span>

<span class=r><span class=k>post</span> <span class=s>"/search"</span> <span class=k>do</span> |env|</span>
  env.request.cookies[<span class=s>"my_auth"</span>]
  env.params.body[<span class=s>"search"</span>]
<span class=k>end</span>

<span class=r><span class=k>get</span> <span class=s>"/token"</span> <span class=k>do</span> |env|</span>
  env.params.body[<span class=s>"client_id"</span>]
  env.params.body[<span class=s>"redirect_url"</span>]
  env.params.body[<span class=s>"grant_type"</span>]
<span class=k>end</span>

<span class=r><span class=k>ws</span> <span class=s>"/socket"</span> <span class=k>do</span> |socket|</span>
  socket.send <span class=s>"Hello from the demo app!"</span>
<span class=k>end</span>

Kemal.run'''
GUTTER = "\n".join(str(i + 1) for i in range(CODE.count("\n") + 1))

JSON = '''{
  <span class=j>"url"</span>: <span class=s>"/search"</span>,
  <span class=j>"method"</span>: <span class=s>"POST"</span>,
  <span class=j>"params"</span>: [
    { <span class=j>"name"</span>: <span class=s>"my_auth"</span>, <span class=j>"param_type"</span>: <span class=s>"cookie"</span> },
    { <span class=j>"name"</span>: <span class=s>"search"</span>,  <span class=j>"param_type"</span>: <span class=s>"form"</span>,
      <span class=j>"tags"</span>: [{ <span class=j>"name"</span>: <span class=t>"sqli"</span>, <span class=j>"tagger"</span>: <span class=s>"Hunt"</span> }] }
  ],
  <span class=j>"details"</span>: {
    <span class=j>"code_paths"</span>: [{ <span class=j>"path"</span>: <span class=s>"src/app.cr"</span>, <span class=j>"line"</span>: <span class=n>19</span> }]
  }
}'''

FORMATS = ["json", "yaml", "openapi", "sarif", "curl", "postman", "html", "markdown-table"]

page = f'''<!doctype html><html><head><meta charset=utf-8><style>
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:1680px;height:1340px;overflow:hidden;background:#09090b}}
body{{font-family:"SF Mono",Menlo,"DejaVu Sans Mono",monospace;color:#c8c8cc;position:relative}}
.bg{{position:absolute;inset:0;background:
 radial-gradient(900px 620px at 78% 8%, rgba(238,42,34,.30), transparent 70%),
 radial-gradient(700px 500px at 8% 100%, rgba(238,42,34,.10), transparent 70%),
 radial-gradient(1200px 900px at 50% 50%, #131316, #09090b 80%)}}
.grid{{position:absolute;inset:0;z-index:0;background-image:radial-gradient(rgba(255,255,255,.055) 1px, transparent 1px);background-size:28px 28px;mask-image:linear-gradient(#000 60%, transparent)}}
.win{{position:absolute;z-index:1;background:#0e0e11;border:1px solid rgba(255,255,255,.09);border-radius:14px;box-shadow:0 30px 80px rgba(0,0,0,.65),0 0 0 1px rgba(0,0,0,.6);overflow:hidden}}
.bar{{height:44px;display:flex;align-items:center;gap:8px;padding:0 16px;border-bottom:1px solid rgba(255,255,255,.07);background:rgba(255,255,255,.025);font-size:13px;color:#8b8b93}}
.dot{{width:12px;height:12px;border-radius:50%;background:#3a3a40}}
.dot.r{{background:#ff5f57}}.dot.y{{background:#febc2e}}.dot.g{{background:#28c840}}
.bar .t{{margin-left:10px;color:#a8a8b0}}
.bar .t b{{color:#f2f2f4;font-weight:600}}
.term{{left:660px;top:84px;width:956px;height:1216px}}
.term pre{{padding:22px 28px;font-size:15px;line-height:18px;white-space:pre;color:#c8c8cc}}
.code{{left:64px;top:96px;width:560px}}
.code pre{{display:flex;font-size:14px;line-height:22px;padding:18px 0 22px}}
.code .gut{{width:56px;text-align:right;padding-right:16px;color:#4a4a52;user-select:none}}
.code .c{{color:#d4d4d8}}
.k{{color:#ff8ad0}} .s{{color:#7dffa4}} .r{{position:relative}}
.r::before{{content:"";position:absolute;left:-56px;top:2px;bottom:2px;width:3px;background:#ee2a22;border-radius:2px;box-shadow:0 0 10px rgba(238,42,34,.8)}}
.json{{left:64px;top:732px;width:560px}}
.json pre{{padding:18px 22px;font-size:13px;line-height:20px;color:#c8c8cc}}
.j{{color:#8ae7ff}} .t{{color:#ffd75f}} .n{{color:#ff8ad0}}
.tag{{margin-left:auto;font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:#ee2a22;border:1px solid rgba(238,42,34,.5);padding:3px 8px;border-radius:999px}}
.brand{{position:absolute;left:64px;top:36px;display:flex;align-items:center;gap:12px;font-size:14px;color:#8b8b93;letter-spacing:.02em}}
.brand img{{width:30px;height:30px}}
.brand b{{color:#f2f2f4;font-weight:600;font-size:15px}}
.brand span.d{{color:#3a3a40}}
.foot{{position:absolute;right:64px;top:40px;display:flex;gap:10px;font-size:12px;color:#7a7a82}}
.foot i{{font-style:normal;padding:4px 10px;border:1px solid rgba(255,255,255,.1);border-radius:6px;background:rgba(255,255,255,.02)}}
.hak{{position:absolute;z-index:2;left:1310px;top:1010px;width:280px;filter:drop-shadow(0 12px 24px rgba(0,0,0,.7))}}
</style></head><body>
<div class=bg></div><div class=grid></div>
<div class=brand><img src="{IMAGES}/logo-s.png"><b>OWASP Noir</b><span class=d>/</span>Hunt every Endpoint in your code</div>
<div class=foot>{"".join(f"<i>{f}</i>" for f in FORMATS)}</div>
<div class="win code"><div class=bar><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span><span class=t>demo-app/src/<b>app.cr</b></span><span class=tag>source</span></div>
<pre><span class=gut>{GUTTER}</span><span class=c>{CODE}</span></pre></div>
<div class="win json"><div class=bar><span class="dot"></span><span class="dot"></span><span class="dot"></span><span class=t>noir scan ./demo-app <b>-f json</b></span><span class=tag>output</span></div>
<pre>{JSON}</pre></div>
<div class="win term"><div class=bar><span class="dot r"></span><span class="dot y"></span><span class="dot g"></span><span class=t>$ noir scan ./demo-app <b>-P -T</b></span><span class=tag>endpoints</span></div>
<pre>{term}</pre></div>
<img class=hak src="{IMAGES}/mascot/hak-binoculars.webp" alt="">
</body></html>'''
open(out_path, "w", encoding="utf-8").write(page)
