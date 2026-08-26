# 3D models

STEP and WRL models used by the control board footprints.

See [SOURCES.txt](SOURCES.txt) for where individual models came from, and
[../README_3d_render.md](../README_3d_render.md) for how the documentation
images are rendered.

Places to find models:

- [3dcontentcentral.com](https://www.3dcontentcentral.com) (free after you create an account)
- [ultralibrarian.com](https://www.ultralibrarian.com)
- [snapeda.com](https://www.snapeda.com)

## Adding a model

Reference it from `Control_Boards.kicad_pcb` as `./3d_models/<file>`. KiCad
resolves that against `${KIPRJMOD}`, the directory holding the board file, so the
path only works while the board sits in the project root — the per-board copies
under `gerbers/<version>/` need rewritten paths, which `split_boards.py` handles
automatically. See [Model paths](../README_3d_render.md#model-paths).

Match the filename case exactly. macOS is case-insensitive and will silently
load `DC-10.STEP` from a file actually named `DC-10.step`; Linux will not.

## Local modifications to downloaded models

### roboclaw_2x7a_headers_standoffs.step

The `MC5A-PCB` solid — the RoboClaw board itself, solid `#51342` — shipped
coloured light grey (192/192/192) with a single `ADVANCED_FACE` overridden to
red by `OVER_RIDING_STYLED_ITEM #782`. It rendered red from below and near-white
from above. Real 2x7A boards are red on both sides.

Fix: a new `COLOUR_RGB #88566` (168/32/42, a deep soldermask red) was added, and
the two `FILL_AREA_STYLE_COLOUR`s that paint this solid — `#51275` for the whole
body and `#51276` for the pre-existing single-face override — were both
repointed to it. Both style chains are private to this solid, so nothing else in
the file changed colour. The vendor's `DRAUGHTING_PRE_DEFINED_COLOUR #804`
('red', a hot 255/0/0) is now unreferenced and left in place.

To change the shade again, edit the three fractions in `#88566`. **Do not**
repoint `#51334` (192/192/192) — 22 other styled solids share it.
