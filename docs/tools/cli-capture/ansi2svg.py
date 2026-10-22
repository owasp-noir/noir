#!/usr/bin/env python3
"""Render a PTY transcript (truecolor ANSI) into a self-contained SVG.

The SVG is a faithful, grid-aligned screenshot of a real terminal run: every
cell is placed on an exact monospace grid using textLength + lengthAdjust so
the output aligns regardless of the viewer's font. No external assets.

Adapted from gori's docs/tools/tui-capture renderer; this variant replays a
scrolling CLI transcript, where the original parsed a fixed tmux pane.

What it replays: SGR colour/bold/reverse, carriage return, backspace, tab.
What it does NOT replay: cursor motion and erase-in-line (\x1b[K, \x1b[2A, …)
are recognised only so they never print as literal text; their effect on the
cell grid is dropped. A scene whose output redraws itself in place (a spinner,
a re-rendered progress line) therefore renders with the pre-erase text still
showing. Capture such scenes with the redraw disabled, the way capture.sh
passes --no-spinner.
"""
import sys, re, html, argparse, unicodedata

# A cell painted with no explicit colour is the terminal's own default, which
# a transcript never spells out: terminals emit no SGR for "default fg on
# default bg". Resolve those to the reset pair at parse time. (The upstream
# tmux renderer inferred them from a histogram of the frame instead, which
# only works because `capture-pane -e` writes an explicit colour into every
# cell. On a plain transcript that heuristic elects whatever colour covers the
# most cells, and noir's 11-row cyan banner wins it over the log prose.)
RESET_FG = (200, 200, 204)
RESET_BG = (10, 10, 11)
DEF_FG = None
DEF_BG = None

# xterm 256-color -> rgb
def xterm256(n):
    if n < 16:
        base = [(0,0,0),(205,49,49),(13,188,121),(229,229,16),(36,114,200),
                (188,63,188),(17,168,205),(229,229,229),(102,102,102),(241,76,76),
                (35,209,139),(245,245,67),(59,142,234),(214,112,214),(41,184,219),(255,255,255)]
        return base[n]
    if n >= 232:
        v = 8 + (n-232)*10
        return (v,v,v)
    n -= 16
    r = n // 36; g = (n % 36) // 6; b = n % 6
    conv = lambda c: 0 if c == 0 else 55 + c*40
    return (conv(r), conv(g), conv(b))

class Cell:
    __slots__ = ("ch","fg","bg","bold","w")
    def __init__(s, ch=" ", fg=RESET_FG, bg=RESET_BG, bold=False, w=1):
        s.ch=ch; s.fg=fg; s.bg=bg; s.bold=bold; s.w=w

# Wide glyphs (CJK, most emoji) take two terminal columns. Track that or every
# cell after one on the same row lands a column left of where the terminal put
# it, and the wide glyph itself gets squeezed into one cell by textLength.
def cell_width(ch):
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1

# SGR is the only escape that paints; everything else a PTY transcript can
# carry (cursor hide/show, OSC titles, keypad modes) is skipped, not drawn.
SGR   = re.compile(r"\x1b\[([0-9;]*)m")
OTHER = re.compile(r"\x1b(\[[0-9;?]*[A-Za-z]|\][^\x07\x1b]*(\x07|\x1b\\)|[()][B0]|[=>])")

def parse(text):
    rows = []
    fg, bg, bold, rev = DEF_FG, DEF_BG, False, False
    for line in text.replace("\r\n", "\n").split("\n"):
        cells = []
        col = 0
        def put(ch):
            nonlocal col
            # Resolve the default-colour sentinels BEFORE the reverse swap:
            # swapping two Nones is a no-op, which silently drops the
            # highlight from any inverted span drawn in the default pair.
            cf = RESET_FG if fg is None else fg
            cb = RESET_BG if bg is None else bg
            f, b = (cb, cf) if rev else (cf, cb)
            cell = Cell(ch, f, b, bold, cell_width(ch))
            if col < len(cells):
                cells[col] = cell
            else:
                cells.append(cell)
            col += 1
        i = 0
        while i < len(line):
            m = SGR.match(line, i)
            if m:
                params = m.group(1)
                nums = [int(x) if x else 0 for x in params.split(";")] if params else [0]
                j = 0
                while j < len(nums):
                    c = nums[j]
                    if c == 0: fg,bg,bold,rev = DEF_FG,DEF_BG,False,False
                    elif c == 1: bold = True
                    elif c == 22: bold = False
                    elif c == 7: rev = True
                    elif c == 27: rev = False
                    elif c == 39: fg = DEF_FG
                    elif c == 49: bg = DEF_BG
                    elif 30 <= c <= 37: fg = xterm256(c-30)
                    elif 90 <= c <= 97: fg = xterm256(c-90+8)
                    elif 40 <= c <= 47: bg = xterm256(c-40)
                    elif 100 <= c <= 107: bg = xterm256(c-100+8)
                    elif c == 38 or c == 48:
                        # Bounds-checked: a truncated sequence (an interrupted
                        # capture, a mangled multi-byte escape) would otherwise
                        # take down the whole render with an IndexError.
                        if j+4 < len(nums) and nums[j+1] == 2:
                            col_ = (nums[j+2], nums[j+3], nums[j+4]); j += 4
                            if c == 38: fg = col_
                            else: bg = col_
                        elif j+2 < len(nums) and nums[j+1] == 5:
                            col_ = xterm256(nums[j+2]); j += 2
                            if c == 38: fg = col_
                            else: bg = col_
                        else:
                            break
                    j += 1
                i = m.end()
                continue
            m = OTHER.match(line, i)
            if m:
                i = m.end()
                continue
            ch = line[i]
            if ch == "\r":
                col = 0
            elif ch == "\b":
                col = max(0, col - 1)
            elif ch == "\t":
                put(" ")
                while col % 8:
                    put(" ")
            elif ch >= " " or ch == " ":
                put(ch)
            # other control bytes (^D noise from script(1), BEL, ...) are dropped
            i += 1
        rows.append(cells)
    return rows

def hexc(c): return "#%02x%02x%02x" % c
def lum(c): return (0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]) / 255.0
def mix(a, b, t): return tuple(round(a[i]+(b[i]-a[i])*t) for i in range(3))

def render(rows, title, fs=15.0, pad=18.0, aria=None, min_cols=0):
    cw = fs*0.60
    ch = fs*1.20
    # trim leading/trailing fully-blank rows
    while rows and all(c.ch == " " for c in rows[0]):
        rows.pop(0)
    while rows and all(c.ch == " " for c in rows[-1]):
        rows.pop()
    # Column offset of every cell, so wide glyphs push what follows along.
    # Each row's list carries a final entry holding the row's total width,
    # which makes the offset of any run simply starts[end] - starts[begin].
    starts = []
    for row in rows:
        acc, xs = 0, []
        for c in row:
            xs.append(acc); acc += c.w
        xs.append(acc)
        starts.append(xs)
    cols = max(max((xs[-1] for xs in starts), default=0), min_cols)
    nrows = len(rows)

    dom_bg = RESET_BG
    dark = lum(dom_bg) < 0.5
    ink = (255, 255, 255) if dark else (0, 0, 0)
    chrome_bg = mix(dom_bg, ink, 0.06)          # titlebar
    border_col = mix(dom_bg, ink, 0.16)         # outer hairline
    label_col = mix(dom_bg, ink, 0.55)          # window title text

    titleh = 34.0 if title is not None else 0.0
    W = cols*cw + pad*2
    H = nrows*ch + pad*2 + titleh
    aria = html.escape(aria or title or "noir terminal screenshot")
    out = []
    out.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W:.0f}" height="{H:.0f}" '
               f'viewBox="0 0 {W:.1f} {H:.1f}" font-family="ui-monospace,\'SF Mono\',\'JetBrains Mono\',Menlo,Consolas,monospace" '
               f'font-size="{fs:.1f}px" role="img" aria-label="{aria}">')
    out.append(f'<rect x="0.5" y="0.5" width="{W-1:.1f}" height="{H-1:.1f}" rx="10" ry="10" '
               f'fill="{hexc(dom_bg)}" stroke="{hexc(border_col)}" stroke-width="1"/>')
    if title is not None:
        # slim window chrome
        out.append(f'<rect x="1" y="1" width="{W-2:.1f}" height="{titleh:.1f}" rx="10" ry="10" fill="{hexc(chrome_bg)}"/>')
        out.append(f'<rect x="1" y="{titleh-10:.1f}" width="{W-2:.1f}" height="10" fill="{hexc(chrome_bg)}"/>')
        for k,(cx,col) in enumerate([(0,"#e0645f"),(1,"#e0b24f"),(2,"#4fb06a")]):
            out.append(f'<circle cx="{pad+cx*16:.1f}" cy="{titleh/2:.1f}" r="5.5" fill="{col}"/>')
        out.append(f'<text x="{W/2:.1f}" y="{titleh/2+5:.1f}" text-anchor="middle" '
                   f'fill="{hexc(label_col)}" font-size="{fs*0.82:.1f}px">{html.escape(title)}</text>')
    y0 = pad + titleh
    body = []
    txt = []
    for ri, row in enumerate(rows):
        yb = y0 + ri*ch
        xs = starts[ri]
        # background runs
        ci = 0
        while ci < len(row):
            cell = row[ci]
            if cell.bg != dom_bg:
                cj = ci
                while cj < len(row) and row[cj].bg == cell.bg:
                    cj += 1
                x = pad + xs[ci]*cw
                body.append(f'<rect x="{x:.2f}" y="{yb:.2f}" width="{(xs[cj]-xs[ci])*cw:.2f}" height="{ch:.2f}" fill="{hexc(cell.bg)}"/>')
                ci = cj
            else:
                ci += 1
        # foreground runs (skip spaces)
        ci = 0
        ytext = yb + ch*0.76
        while ci < len(row):
            cell = row[ci]
            if cell.ch == " ":
                ci += 1; continue
            cj = ci
            while cj < len(row) and row[cj].ch != " " and row[cj].fg == cell.fg and row[cj].bold == cell.bold:
                cj += 1
            run = "".join(row[k].ch for k in range(ci, cj))
            x = pad + xs[ci]*cw
            tl = (xs[cj]-xs[ci])*cw
            wt = ' font-weight="700"' if cell.bold else ''
            txt.append(f'<text x="{x:.2f}" y="{ytext:.2f}" textLength="{tl:.2f}" lengthAdjust="spacingAndGlyphs" '
                       f'fill="{hexc(cell.fg)}"{wt} xml:space="preserve">{html.escape(run)}</text>')
            ci = cj
    out.extend(body)
    out.extend(txt)
    out.append('</svg>')
    return "\n".join(out)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("infile")
    ap.add_argument("outfile")
    ap.add_argument("--title", default=None)
    ap.add_argument("--aria", default=None, help="spoken label; defaults to --title")
    ap.add_argument("--fs", type=float, default=15.0)
    ap.add_argument("--min-cols", type=int, default=0,
                    help="pad the frame to at least this many columns wide")
    a = ap.parse_args()
    with open(a.infile, "r", encoding="utf-8", errors="replace") as f:
        data = f.read()
    rows = parse(data)
    svg = render(rows, a.title, fs=a.fs, aria=a.aria, min_cols=a.min_cols)
    with open(a.outfile, "w", encoding="utf-8") as f:
        f.write(svg)
    print(f"wrote {a.outfile} ({len(svg)} bytes)")
