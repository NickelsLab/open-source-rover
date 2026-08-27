#!/usr/bin/env python3
"""Split the combined OSR Control_Boards.kicad_pcb into per-board files.

The two board outlines are separated by a wide empty band in Y:
  motor board  outline spans y = -78.0 .. 100.0   (T shape)
  brain board  outline spans y = -229.2 .. -129.2 (100x100 rect)
so a horizontal cut anywhere in the gap partitions the design cleanly.
"""
import re, sys, os, argparse, collections

SPLIT_Y = -100.0          # anywhere in the -129.2 .. -78.0 gap
KEEP = ('version','generator','generator_version','general','paper',
        'layers','setup','embedded_fonts','property')

def parse_children(text):
    n=len(text); i=text.index('('); i+=1
    depth=0; instr=False; esc=False; child=None; out=[]
    while i<n:
        c=text[i]
        if instr:
            if esc: esc=False
            elif c=='\\': esc=True
            elif c=='"': instr=False
            i+=1; continue
        if c=='"': instr=True; i+=1; continue
        if c=='(':
            if depth==0: child=i
            depth+=1
        elif c==')':
            depth-=1
            if depth==0: out.append((child,i+1))
            elif depth<0: break
        i+=1
    return out

def node_name(seg):
    m=re.match(r'\(\s*([A-Za-z0-9_]+)',seg)
    return m.group(1) if m else '?'

COORD = re.compile(r'\((?:at|start|end|center|mid|xy)\s+(-?[\d.]+)\s+(-?[\d.]+)')
MODEL = re.compile(r'(\(model\s+")([^"]+)(")')

_CASE_CACHE = {}

def true_case(path, report):
    """Return the path as it is really spelled on disk.

    macOS is case-insensitive, so a reference like '3d_models/DC-10.STEP' resolves
    against the real file 'DC-10.step' here but would fail on a case-sensitive
    filesystem. Emit the on-disk spelling so the split files are portable.
    """
    d, base = os.path.split(path)
    if d not in _CASE_CACHE:
        try: _CASE_CACHE[d] = {f.lower(): f for f in os.listdir(d)}
        except OSError: _CASE_CACHE[d] = {}
    realname = _CASE_CACHE[d].get(base.lower())
    if realname and realname != base:
        report['recased'].add(f"{base} -> {realname}")
        return os.path.join(d, realname)
    return path


def fix_models(seg, srcdir, outdir, report):
    """Rewrite project-local 3D model paths so they still resolve from outdir.

    Model paths are relative to ${KIPRJMOD}, i.e. the directory holding the board
    file. Moving a board into gerbers/<version>/ silently breaks every './3d_models/..'
    reference -- which is why the committed v2.0.1 renders show bare footprints
    where the Roboclaws, regulators and PCA9685 should be.
    """
    def sub(m):
        pre, path, post = m.group(1), m.group(2), m.group(3)
        if path.startswith('${') or path.startswith('$(') or os.path.isabs(path):
            return m.group(0)                      # stock KiCad library, leave alone
        target = os.path.normpath(os.path.join(srcdir, path))
        if not os.path.exists(target):             # e.g. J16-J18's stray '../'
            cand = os.path.join(srcdir, '3d_models', os.path.basename(path))
            if os.path.exists(cand):
                report['repaired'].add(f"{path} -> 3d_models/{os.path.basename(path)}")
                target = os.path.normpath(cand)
            else:
                report['unresolved'].add(path)
                return m.group(0)
        target = true_case(target, report)
        new = os.path.relpath(target, outdir).replace(os.sep, '/')
        return pre + '${KIPRJMOD}/' + new + post
    return MODEL.sub(sub, seg)


def ys_of(seg, name):
    if name=='footprint':
        m=re.search(r'\(at\s+(-?[\d.]+)\s+(-?[\d.]+)',seg)
        return [float(m.group(2))] if m else []
    return [float(m.group(2)) for m in COORD.finditer(seg)]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('source'); ap.add_argument('--outdir',default='.')
    ap.add_argument('--write',action='store_true')
    a=ap.parse_args()

    t=open(a.source,encoding='utf-8').read()
    kids=parse_children(t)
    srcdir=os.path.dirname(os.path.abspath(a.source))
    outdir=os.path.abspath(a.outdir)
    report={'repaired':set(),'unresolved':set(),'recased':set()}

    header=[]; motor=[]; brain=[]; straddle=[]
    counts=collections.Counter()
    refs={'motor':[], 'brain':[]}

    for s,e in kids:
        seg=t[s:e]; nm=node_name(seg)
        if nm in KEEP:
            header.append(seg); continue
        ys=ys_of(seg,nm)
        if not ys:
            header.append(seg); counts['no-coords:'+nm]+=1; continue
        above=[y for y in ys if y>SPLIT_Y]; below=[y for y in ys if y<=SPLIT_Y]
        if nm!='footprint' and above and below:
            straddle.append((nm,min(ys),max(ys))); counts['STRADDLE:'+nm]+=1
            continue
        side='motor' if (ys[0]>SPLIT_Y) else 'brain'
        if nm=='footprint':
            seg=fix_models(seg, srcdir, outdir, report)
        (motor if side=='motor' else brain).append(seg)
        counts[f'{side}:{nm}']+=1
        if nm=='footprint':
            r=re.search(r'\(property\s+"Reference"\s+"([^"]+)"',seg)
            if r: refs[side].append(r.group(1))

    for k in sorted(counts): print(f"  {k:28s} {counts[k]}")
    print(f"\nmotor items {len(motor)}   brain items {len(brain)}   header {len(header)}")
    print(f"motor refdes ({len(refs['motor'])}): {' '.join(sorted(refs['motor']))}")
    print(f"\nbrain refdes ({len(refs['brain'])}): {' '.join(sorted(refs['brain']))}")
    if report['repaired']:
        print("\nrepaired broken model paths:")
        for r in sorted(report['repaired']): print("   "+r)
    if report['recased']:
        print("\ncorrected filename case (for case-sensitive filesystems):")
        for r in sorted(report['recased']): print("   "+r)
    if report['unresolved']:
        print("\n!! model paths that could not be resolved:")
        for r in sorted(report['unresolved']): print("   "+r)
    if straddle:
        print("\n!! items crossing the split line:")
        for nm,lo,hi in straddle: print(f"   {nm}  y {lo} .. {hi}")

    if a.write:
        os.makedirs(a.outdir,exist_ok=True)
        for name,items in (('motor_board',motor),('brain_board',brain)):
            p=os.path.join(a.outdir,name+'.kicad_pcb')
            with open(p,'w',encoding='utf-8') as f:
                f.write('(kicad_pcb\n')
                for h in header: f.write('\t'+h+'\n')
                for it in items:  f.write('\t'+it+'\n')
                f.write(')\n')
            print(f"wrote {p}  ({os.path.getsize(p)} bytes)")

main()
