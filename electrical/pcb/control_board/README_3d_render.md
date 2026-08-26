# Regenerating the 3D board images

The images in `documentation/<version>/3d_images/` are rendered from the KiCad
board, not captured by hand out of the 3D viewer. Two steps, both run from this
directory (`electrical/pcb/control_board/`).

Requires KiCad 8 or newer for `kicad-cli pcb render`. Verified against KiCad 10.

## 1. Split the combined board

`Control_Boards.kicad_pcb` holds **both** boards in a single design, so it
cannot be rendered per board. Produce single-board copies first:

```sh
python3 split_boards.py Control_Boards.kicad_pcb --outdir gerbers/v2.0.3 --write
```

Run it without `--write` first to preview. It reports how many items land on
each board and lists the reference designators, so you can check the result
before anything is written — for v2.0.3 that is 52 footprints on the brain board
and 96 on the motor board.

The split is geometric: the two board outlines are separated by a 51 mm empty
band in Y (the motor board spans y = -78..100, the brain board y = -229..-129),
so a horizontal cut at y = -100 divides the design cleanly. The splitter also
rewrites 3D model paths on the way out — see [Model paths](#model-paths).

## 2. Render

```sh
./render_3d.sh
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

All optional, all environment variables:

| Variable | Default | Notes |
|---|---|---|
| `VERSION` | `v2.0.3` | which `gerbers/<version>/` to read and `documentation/<version>/` to write |
| `QUALITY` | `basic` | `basic` matches the flat look of the v2.0.1 images; `high` and `ultra` raytrace |
| `BACKGROUND` | `opaque` | or `transparent`, `checkered` |
| `PRESET` | `FOLLOW_PLOT_SETTINGS` | or `FOLLOW_PCB`, or a preset you defined in the 3D viewer |
| `KICAD_CLI` | auto-detected | set this if `kicad-cli` is not on `PATH` or in the macOS app bundle |

```sh
VERSION=v2.0.4 QUALITY=ultra ./render_3d.sh
```

The isometric camera angles are the `ISO_TOP` and `ISO_BOTTOM` variables near
the top of the script. `kicad-cli pcb render --side` accepts only `top` and
`bottom`, so the three-quarter views come from `--rotate 'X,Y,Z'` instead;
negative values need quoting in zsh. `-h` is the short form of `--height`, so
use `kicad-cli pcb render --help` for the full option list.

Per-board canvas sizes are set in the `canvas()` function — the motor board is a
wide T, the brain board is square.

## Model paths

This is the non-obvious part. KiCad resolves relative `(model ...)` paths
against `${KIPRJMOD}`, which is **the directory holding the board file**. Moving
a board into `gerbers/<version>/` therefore breaks every `./3d_models/...`
reference in it — silently, with no error and no warning in the render.

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
