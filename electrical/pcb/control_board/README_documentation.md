# Regenerating the board documentation

Everything under `documentation/<version>/` is generated from the KiCad board,
not captured by hand. The scripts live in `documentation/utilities/` and resolve
their paths relative to themselves, so they can be run from anywhere; the
examples below assume you are in this directory
(`electrical/pcb/control_board/`).

Requires KiCad 8 or newer for the `kicad-cli` subcommands used here. Verified
against KiCad 10.

| Script | Produces | Reads |
|---|---|---|
| `utilities/split_boards.py` | `gerbers/<version>/{brain,motor}_board.kicad_pcb` | `Control_Boards.kicad_pcb` |
| `utilities/fit_svg_viewbox.py` | re-fits an SVG canvas (called by `export_layout.sh`) | the exported SVGs |
| `utilities/render_3d.sh` | `documentation/<version>/3d_images/*.png` | the split per-board files |
| `utilities/export_layout.sh` | `documentation/<version>/layout/*.svg` | `Control_Boards.kicad_pcb` |

The two output scripts are independent — the layout export does **not** need the
split, only the 3D render does.

## 3D board images

### 1. Split the combined board

`Control_Boards.kicad_pcb` holds **both** boards in a single design, so it
cannot be rendered per board. Produce single-board copies first:

```sh
python3 documentation/utilities/split_boards.py \
    Control_Boards.kicad_pcb --outdir gerbers/v2.0.3 --write
```

Run it without `--write` first to preview. It reports how many items land on
each board and lists the reference designators, so you can check the result
before anything is written — for v2.0.3 that is 52 footprints on the brain board
and 96 on the motor board.

The split is geometric: the two board outlines are separated by a 51 mm empty
band in Y (the motor board spans y = -78..100, the brain board y = -229..-129),
so a horizontal cut at y = -100 divides the design cleanly. The splitter also
rewrites 3D model paths on the way out — see [Model paths](#model-paths).

### 2. Render

```sh
documentation/utilities/render_3d.sh
```

This writes eight PNGs into `documentation/v2.0.3/3d_images/`: `brain_top`,
`brain_top_iso`, `brain_bottom`, `brain_bottom_iso`, and the same four for
`motor`.

**`render_3d.sh` does not run the splitter.** If the per-board files are missing
it stops and prints the `split_boards.py` command from step 1. Nothing checks
whether they are *stale*, so re-run step 1 yourself whenever
`Control_Boards.kicad_pcb` changes — otherwise you will silently render the
previous revision's geometry.

### Options

| Variable | Default | Notes |
|---|---|---|
| `VERSION` | `v2.0.3` | which `gerbers/<version>/` to read and `documentation/<version>/` to write |
| `QUALITY` | `basic` | `basic` matches the flat look of the v2.0.1 images; `high` and `ultra` raytrace |
| `BACKGROUND` | `opaque` | or `transparent`, `checkered` |
| `PRESET` | `FOLLOW_PLOT_SETTINGS` | or `FOLLOW_PCB`, or a preset you defined in the 3D viewer |
| `KICAD_CLI` | auto-detected | set this if `kicad-cli` is not on `PATH` or in the macOS app bundle |

```sh
VERSION=v2.0.4 QUALITY=ultra documentation/utilities/render_3d.sh
```

The isometric camera angles are the `ISO_TOP` and `ISO_BOTTOM` variables near
the top of the script. `kicad-cli pcb render --side` accepts only `top` and
`bottom`, so the three-quarter views come from `--rotate 'X,Y,Z'` instead;
negative values need quoting in zsh. `-h` is the short form of `--height`, so
use `kicad-cli pcb render --help` for the full option list.

Per-board canvas sizes are set in the `canvas()` function — the motor board is a
wide T, the brain board is square.

## Layout SVGs

```sh
documentation/utilities/export_layout.sh
```

This writes `documentation/v2.0.3/layout/all_layers.svg` plus one file per layer
under `separate_layers/`. It plots the **combined** board, which is what v2.0.1
was plotted from, so no split is needed and the output filenames keep the v2.0.1
spelling (`Control_Boards-F_Cu.svg` and so on) and stay directly comparable.

Six layers are plotted: `F.Cu`, `B.Cu`, `F.Silkscreen`, `B.Silkscreen`,
`Edge.Cuts` and `Dwgs.User`. v2.0.1 also plotted `F/B.Adhes` and `F/B.Paste`;
all four came out empty on this design — 4.7 KB of boilerplate each — so they
are omitted. To change the set, edit the `LAYERS` list at the top of the script;
each entry is `<kicad layer name>:<output basename>`.

### Options

| Variable | Default | Notes |
|---|---|---|
| `VERSION` | `v2.0.3` | which `documentation/<version>/layout/` to write |
| `PAGE_SIZE_MODE` | `2` | `0` drawing-sheet page size, `1` current page size, `2` board bounding box only |
| `DRAWING_SHEET` | `exclude` | the board's paper is A4 while the board is 220 x 329 mm, so the sheet lands off the board area entirely |
| `FIT_VIEWBOX` | `1` | re-fit each canvas to its content; `0` leaves KiCad's canvas alone |
| `MARGIN` | `2` | mm of padding around the fitted content |
| `THEME` | (board default) | try `"KiCad Classic"` to match the v2.0.1 colours |
| `KICAD_CLI` | auto-detected | as above |

```sh
THEME="KiCad Classic" MARGIN=5 documentation/utilities/export_layout.sh
PAGE_SIZE_MODE=0 DRAWING_SHEET=include documentation/utilities/export_layout.sh
```

The same list is in the comment block at the top of `utilities/export_layout.sh`.

`fit_svg_viewbox.py` can also be run by hand on any KiCad-exported SVG —
`documentation/utilities/fit_svg_viewbox.py FILE... [--margin MM] [--quiet]`. It
rewrites files in place and is idempotent, so re-running it is harmless.

If a layer name is rejected, the script reports which one and keeps going with
the rest, then exits non-zero. Layer names changed between KiCad 5 and 6 —
`F.SilkS` became `F.Silkscreen` — so if you retarget this at an old board file,
that is the first thing to check.

### Why the canvas is re-fitted

`--page-size-mode 2` crops to the **Edge.Cuts** bounding box, 220 x 329 mm. Two
Dwgs.User annotations live outside that box and were being cut off:

| Note | Position | Relative to the board |
|---|---|---|
| `BRAIN BOARD` caption | y = -230.39 | 1.2 mm above the brain board's top edge |
| `Note: T7 - T12 (large pad test points)...` | x = -42.47 | 42 mm left of the motor board's left edge |

KiCad still *writes* that geometry into the SVG — it just falls outside the
viewBox, and there is no `clipPath`, so nothing is lost. `fit_svg_viewbox.py`
recomputes the canvas from the drawn content and rewrites `width`, `height` and
`viewBox`.

Measuring raw path coordinates is only safe because KiCad writes drawn geometry
untransformed. It writes each text object twice: an invisible `<text>`
(`opacity="0"`) inside a `<g transform="rotate(...)">` for searchability, and a
sibling `<g class="stroked-text">` holding the visible strokes in final absolute
coordinates. The fitter measures only `<path>` and `<circle>`, ignores the
invisible text, and refuses the file outright if a non-identity transform ever
wraps drawn geometry.

Fitted, the content measures **291.4 x 331.5 mm**. The hand-plotted v2.0.1 files
are **292.1 x 332.0 mm** — the same framing to within 0.6 mm, which is a good
sign that KiCad 5's "board area only" fitted all plotted items while KiCad 8+
fits the board outline alone. That behaviour change is inferred from the two
canvas sizes, not from release notes.

Colours still differ from v2.0.1 unless you set `THEME="KiCad Classic"`; the old
files use the classic layer palette (F.Cu dark red, B.Cu green, F.SilkS teal,
B.SilkS magenta).

## Model paths

This is the non-obvious part, and it affects the 3D renders only. KiCad resolves
relative `(model ...)` paths against `${KIPRJMOD}`, which is **the directory
holding the board file**. Moving a board into `gerbers/<version>/` therefore
breaks every `./3d_models/...` reference in it — silently, with no error and no
warning in the render.

That is why the committed v2.0.1 and v2.0.2 split boards render with bare
footprints where the Roboclaws, regulators, PCA9685 and XT30 connectors should
be: all 28 project-local models on the motor board and all 11 on the brain board
fail to load. Only KiCad's own stock library models (the axial resistors, TO-92
transistors and electrolytics) survive, which is what those images actually show.

`split_boards.py` fixes this as it writes. It

- rewrites project-local paths to `${KIPRJMOD}/../../3d_models/...`,
- corrects filename case so they also resolve on case-sensitive filesystems
  (macOS is case-insensitive and will happily load `DC-10.STEP` from
  `DC-10.step`; Linux will not), and
- repairs the stray `../3d_models/` prefix on J16/J17/J18, which is broken in
  `Control_Boards.kicad_pcb` itself — those three motor supply headers have
  never rendered in any revision.

Stock KiCad paths (`${KICAD10_3DMODEL_DIR}/...`) are left untouched. It prints
what it repaired, so watch that output.

When you add a model, reference it as `./3d_models/<file>` from
`Control_Boards.kicad_pcb` and the splitter will fix it up for the per-board
copies. Fixing the J16-J18 typo at the source would be worth doing.

See [3d_models/README.md](3d_models/README.md) for where the models came from
and what has been edited locally.

## What renders and what does not

Every footprint representing a physical component has a 3D model. The 36 that
do not are 17 mounting holes, 15 test points and 4 silkscreen logos — none of
which have geometry to show. Coverage is 43/52 on the brain board and 69/96 on
the motor board, unchanged since v2.0.1.

## Not covered

`documentation/v2.0.1/schematics.pdf` has no equivalent script. The command is
`kicad-cli sch export pdf` against `Control_Boards.kicad_sch`, but it has not
been set up or tested here, and there is no v2.0.3 schematic PDF in the repo.
