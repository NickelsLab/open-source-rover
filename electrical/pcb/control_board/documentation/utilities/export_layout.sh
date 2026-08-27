#!/usr/bin/env bash
# Export the layout SVGs for documentation/<version>/layout/, reproducing the set
# that was plotted by hand for v2.0.1 -- but reproducibly.
#
# Input : Control_Boards.kicad_pcb  (the COMBINED board, both boards on one sheet,
#         which is what v2.0.1 was plotted from -- no split needed)
# Output: documentation/$VERSION/layout/all_layers.svg
#         documentation/$VERSION/layout/separate_layers/Control_Boards-<Layer>.svg
#
# Requires KiCad 8 or newer for `kicad-cli pcb export svg`. Verified against KiCad 10.
#
# Usage
# -----
#   documentation/utilities/export_layout.sh
#   VERSION=v2.0.4 documentation/utilities/export_layout.sh
#   THEME="KiCad Classic" MARGIN=5 documentation/utilities/export_layout.sh
#
# Paths are resolved relative to the script, so it can be run from anywhere.
#
# Environment flags (all optional, defaults in brackets)
# -----------------------------------------------------
#   VERSION         [v2.0.3]   which documentation/<version>/layout/ to write.
#
#   PAGE_SIZE_MODE  [2]        canvas KiCad plots onto:
#                                0 = drawing-sheet page size
#                                1 = current page size
#                                2 = board bounding box (Edge.Cuts) only
#                              Mode 2 crops to the board outline, which cuts off
#                              the two Dwgs.User notes that sit outside it -- the
#                              "BRAIN BOARD" caption 1.2 mm above the brain board
#                              and the T7-T12 test-point note 42 mm left of the
#                              motor board. KiCad still writes that geometry into
#                              the SVG, so FIT_VIEWBOX below brings it back
#                              instead of plotting onto an oversized page.
#
#   DRAWING_SHEET   [exclude]  "include" keeps the frame and title block. The
#                              board's paper is A4 while the board is 220 x 329 mm,
#                              so the sheet lands entirely off the board area; with
#                              it included the fitted canvas stretches to ~550 mm of
#                              mostly nothing. Pair "include" with PAGE_SIZE_MODE=0.
#
#   FIT_VIEWBOX     [1]        after exporting, re-fit each SVG canvas to what it
#                              actually draws (see fit_svg_viewbox.py). Set to 0 to
#                              keep KiCad's canvas. Skipped automatically when
#                              DRAWING_SHEET=include, where it is meaningless.
#
#   MARGIN          [2]        mm of padding left around the fitted content.
#
#   THEME           [board]    colour theme name, e.g. "KiCad Classic" to match the
#                              v2.0.1 palette (F.Cu dark red, B.Cu green, F.SilkS
#                              teal, B.SilkS magenta). Empty uses the board's own.
#
#   KICAD_CLI       [auto]     path to kicad-cli. Searched on PATH, then the macOS
#                              app bundle, then /usr/bin.
#
# The layers plotted are the LAYERS list below, not a flag -- edit it in place.

set -euo pipefail

VERSION="${VERSION:-v2.0.3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # documentation/utilities
PROJ="$(cd "$HERE/../.." && pwd)"                      # the KiCad project directory
SRC="$PROJ/Control_Boards.kicad_pcb"
OUT="$PROJ/documentation/$VERSION/layout"

# Layers to plot, as "<kicad layer name>:<output basename>".
# v2.0.1 also plotted F/B.Adhes and F/B.Paste; all four came out empty on this
# design, so they are omitted. Output names keep the v2.0.1 spelling so the two
# revisions can be compared file for file.
LAYERS="
F.Cu:Control_Boards-F_Cu
B.Cu:Control_Boards-B_Cu
F.Silkscreen:Control_Boards-F_SilkS
B.Silkscreen:Control_Boards-B_SilkS
Edge.Cuts:Control_Boards-Edge_Cuts
Dwgs.User:Control_Boards-Dwgs_User
"

# 0 = drawing-sheet page size, 1 = current page size, 2 = board bounding box only.
# Mode 2 crops to the Edge.Cuts outline, which cuts off the Dwgs.User notes that
# sit outside the board (the "BRAIN BOARD" caption above the brain board, and the
# test-point note 42 mm to the left of the motor board). The geometry is still
# written into the SVG, just outside the viewBox, so FIT_VIEWBOX below puts it
# back rather than us plotting onto an oversized page.
PAGE_SIZE_MODE="${PAGE_SIZE_MODE:-2}"

# The board's paper is A4 while the board itself is 220 x 329 mm, so the drawing
# sheet lands entirely off the board area and would stretch the fitted canvas to
# ~550 mm of mostly nothing. Set DRAWING_SHEET=include (with PAGE_SIZE_MODE=0) if
# you actually want the frame and title block.
DRAWING_SHEET="${DRAWING_SHEET:-exclude}"

# Re-fit each SVG's viewBox around what it actually draws. Only meaningful when
# the drawing sheet is excluded; set FIT_VIEWBOX=0 to leave KiCad's canvas alone.
FIT_VIEWBOX="${FIT_VIEWBOX:-1}"
MARGIN="${MARGIN:-2}"
# Empty uses the board's own theme; try "KiCad Classic" to match the v2.0.1 colours.
THEME="${THEME:-}"

# --- locate kicad-cli -------------------------------------------------------
KICAD_CLI="${KICAD_CLI:-}"
if [[ -z "$KICAD_CLI" ]]; then
  for c in \
    "$(command -v kicad-cli 2>/dev/null || true)" \
    "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli" \
    "/usr/bin/kicad-cli"
  do
    [[ -n "$c" && -x "$c" ]] && { KICAD_CLI="$c"; break; }
  done
fi
if [[ -z "$KICAD_CLI" ]]; then
  echo "error: kicad-cli not found. Set KICAD_CLI=/path/to/kicad-cli and re-run." >&2
  echo "       on macOS it is usually /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli" >&2
  exit 1
fi
if [[ ! -x "$KICAD_CLI" ]]; then
  echo "error: KICAD_CLI='$KICAD_CLI' is not an executable file." >&2
  exit 1
fi
if ! "$KICAD_CLI" pcb export svg --help >/dev/null 2>&1; then
  echo "error: '$KICAD_CLI' has no 'pcb export svg' command (needs KiCad 8+)." >&2
  exit 1
fi
[[ -f "$SRC" ]] || { echo "error: missing $SRC" >&2; exit 1; }

echo "kicad-cli: $KICAD_CLI ($("$KICAD_CLI" version 2>/dev/null || echo 'version unknown'))"
mkdir -p "$OUT/separate_layers"

common_args() {
  printf '%s\n' --mode-single --page-size-mode "$PAGE_SIZE_MODE"
  [[ "$DRAWING_SHEET" == "exclude" ]] && printf '%s\n' --exclude-drawing-sheet
  [[ -n "$THEME" ]] && printf '%s\n' --theme "$THEME"
  return 0
}

plot() {  # plot <comma-separated layers> <output file>
  local layers="$1" out="$2"
  local args=()
  while IFS= read -r a; do [[ -n "$a" ]] && args+=("$a"); done < <(common_args)
  args+=( --layers "$layers" -o "$out" "$SRC" )
  printf '  %s pcb export svg %s\n' "$(basename "$KICAD_CLI")" "${args[*]}"
  if ! "$KICAD_CLI" pcb export svg "${args[@]}"; then
    echo "  !! failed for layers '$layers'" >&2
    echo "     check the layer names with: $KICAD_CLI pcb export svg --help" >&2
    return 1
  fi
}

# --- all layers in one file -------------------------------------------------
all=""
for pair in $LAYERS; do
  [[ -z "$pair" ]] && continue
  all="${all:+$all,}${pair%%:*}"
done
echo "exporting $VERSION -> ${OUT/#$PROJ\//}"
failed=0
plot "$all" "$OUT/all_layers.svg" || failed=$((failed+1))

# --- one file per layer -----------------------------------------------------
for pair in $LAYERS; do
  [[ -z "$pair" ]] && continue
  plot "${pair%%:*}" "$OUT/separate_layers/${pair##*:}.svg" || failed=$((failed+1))
done

if (( failed )); then
  echo "done with $failed failure(s)." >&2
  exit 1
fi

# --- shrink-wrap the canvas around the real content -------------------------
if [[ "$FIT_VIEWBOX" != "0" && "$DRAWING_SHEET" == "exclude" ]]; then
  echo "fitting viewBox (margin ${MARGIN}mm):"
  python3 "$HERE/fit_svg_viewbox.py" --margin "$MARGIN" \
    "$OUT/all_layers.svg" "$OUT"/separate_layers/*.svg
elif [[ "$FIT_VIEWBOX" != "0" ]]; then
  echo "note: DRAWING_SHEET=include, skipping viewBox fit (the A4 sheet sits off" >&2
  echo "      the board area; use PAGE_SIZE_MODE=0 for a sheet-framed plot)." >&2
fi

echo "done:"
ls -la "$OUT" "$OUT/separate_layers"
