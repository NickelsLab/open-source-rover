#!/usr/bin/env python3
"""Shrink-wrap a KiCad-exported SVG's viewBox around what it actually draws.

`kicad-cli pcb export svg --page-size-mode 2` sizes the canvas to the Edge.Cuts
bounding box, so anything plotted outside the board outline -- notably Dwgs.User
annotations -- is written into the file but falls outside the viewBox and never
appears in a viewer. There is no clipPath, so widening the viewBox brings it back
with no loss of fidelity.

KiCad emits each text object twice: an invisible <text> (opacity="0") inside a
<g transform="rotate(...)"> for searchability, and a sibling <g class="stroked-text">
holding the visible stroked paths in final absolute coordinates. Only the paths
and circles are measured here; the invisible <text> and its rotate are skipped.
Any non-identity transform that actually wraps drawn geometry is treated as
unsafe and the file is left alone.

    fit_svg_viewbox.py FILE... [--margin MM] [--quiet]
"""
import re, sys, argparse

NUM = r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?'
PAIR = re.compile(rf'({NUM})\s*[,\s]\s*({NUM})')
TOKEN = re.compile(r'<g\b[^>]*>|</g>|<path\b[^>]*>|<circle\b[^>]*>')
DATTR = re.compile(r'\sd="([^"]*)"')
CXCYR = re.compile(rf'cx="({NUM})"[^>]*?cy="({NUM})"[^>]*?r="({NUM})"')
XFORM = re.compile(r'transform="([^"]*)"')
IDENTITY = re.compile(r'^\s*translate\(\s*0\s+0\s*\)\s*scale\(\s*1\s+1\s*\)\s*$')


def content_bbox(svg):
    """Bounding box of drawn geometry, or ('unsafe', transform) if a non-identity
    transform wraps any of it."""
    xs, ys = [], []
    stack = []                                    # one entry per open <g>: transformed?
    for tok in TOKEN.finditer(svg):
        s = tok.group(0)
        if s.startswith('<g'):
            tr = XFORM.search(s)
            stack.append((tr.group(1), True) if tr and not IDENTITY.match(tr.group(1))
                         else (None, False))
        elif s == '</g>':
            if stack:
                stack.pop()
        else:
            bad = next((t for t, flag in stack if flag), None)
            if bad:
                return ('unsafe', bad)
            if s.startswith('<path'):
                d = DATTR.search(s)
                if d:
                    for mx, my in PAIR.findall(re.sub(r'[A-Za-z]', ' ', d.group(1))):
                        xs.append(float(mx)); ys.append(float(my))
            else:
                c = CXCYR.search(s)
                if c:
                    cx, cy, r = (float(v) for v in c.groups())
                    xs += [cx - r, cx + r]; ys += [cy - r, cy + r]
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def fit(path, margin, quiet):
    svg = open(path, encoding='utf-8').read()
    bb = content_bbox(svg)
    name = path.split('/')[-1]
    if bb is None:
        if not quiet:
            print(f"  {name:34s} nothing drawn, left alone")
        return True
    if bb[0] == 'unsafe':
        print(f"  {name}: refusing, geometry under transform {bb[1]!r}", file=sys.stderr)
        return False

    x0, y0, x1, y1 = bb
    x0 -= margin; y0 -= margin; x1 += margin; y1 += margin
    w, h = x1 - x0, y1 - y0

    old = re.search(rf'viewBox="({NUM})\s+({NUM})\s+({NUM})\s+({NUM})"', svg)
    ow, oh = (float(old.group(3)), float(old.group(4))) if old else (0.0, 0.0)

    svg = re.sub(rf'width="{NUM}mm"', f'width="{w:.4f}mm"', svg, count=1)
    svg = re.sub(rf'height="{NUM}mm"', f'height="{h:.4f}mm"', svg, count=1)
    svg = re.sub(rf'viewBox="{NUM}\s+{NUM}\s+{NUM}\s+{NUM}"',
                 f'viewBox="{x0:.4f} {y0:.4f} {w:.4f} {h:.4f}"', svg, count=1)
    open(path, 'w', encoding='utf-8').write(svg)
    if not quiet:
        note = "unchanged" if (abs(w - ow) < .01 and abs(h - oh) < .01) else f"was {ow:.1f} x {oh:.1f}"
        print(f"  {name:34s} {w:7.2f} x {h:7.2f} mm   ({note})")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('--margin', type=float, default=2.0, help='mm of padding (default 2)')
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args()
    sys.exit(0 if all([fit(f, a.margin, a.quiet) for f in a.files]) else 1)


main()
