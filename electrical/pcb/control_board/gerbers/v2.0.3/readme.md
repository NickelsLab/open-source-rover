# v2.0.3 board files

`Control_Boards.kicad_pcb` in the project root holds **both** boards in a single
design. The per-revision files here are single-board copies of it, matching the
convention used for v2.0.1 and v2.0.2:

- `brain_board.kicad_pcb` — 52 footprints
- `motor_board.kicad_pcb` — 96 footprints

They are generated, not hand-edited. To regenerate after a change to the
combined board:

```sh
python3 ../../split_boards.py ../../Control_Boards.kicad_pcb --outdir . --write
```

The splitter partitions the design along Y: the two board outlines are separated
by a 51 mm empty band (motor board spans y = -78..100, brain board y = -229..-129),
so a horizontal cut at y = -100 divides it cleanly. Run without `--write` first to
see the item counts and the reference designators that land on each side.

### 3D model paths

KiCad resolves relative `(model ...)` paths against `${KIPRJMOD}`, which is the
directory holding the board file. Moving a board down into `gerbers/<version>/`
therefore breaks every `./3d_models/...` reference in it -- silently, with no error.
That is why the committed v2.0.1 and v2.0.2 split boards render with bare footprints
where the Roboclaws, regulators, PCA9685 and XT30 connectors should be: all 28 of
the motor board's project-local models and all 11 of the brain board's fail to load.

`split_boards.py` rewrites those paths to `${KIPRJMOD}/../../3d_models/...` as it
writes, corrects filename case so they also resolve on case-sensitive filesystems,
and repairs the stray `../3d_models/277-14404-ND.step` on J16/J17/J18 that is broken
in the combined board itself. All 39 project-local models resolve in these files.

These files are what the 3D documentation images are rendered from — see
`../../render_3d.sh`. Fabrication gerbers for v2.0.3 have **not** been generated
yet; the newest orderable board is still v2.0.2, which is what `parts_list/README.md`
points builders at.
