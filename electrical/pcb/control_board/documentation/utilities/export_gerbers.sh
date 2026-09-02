#!/usr/bin/env bash
# Export fabrication gerbers and drill files for gerbers/<version>/, reproducing
# the set that was plotted by hand for v2.0.1 and v2.0.2 -- but reproducibly.
#
# Inputs : gerbers/$VERSION/{brain,motor}_board.kicad_pcb  (single-board files,
#          produced by split_boards.py from the combined Control_Boards.kicad_pcb)
# Outputs: gerbers/$VERSION/gerber_files/{brain,motor}_board/*.gbl .gtl .gts ...
#          gerbers/$VERSION/gerber_files/{brain,motor}_board_$VERSION.zip
#
# Requires KiCad 8 or newer for `kicad-cli pcb export gerbers|drill`.
# Verified against KiCad 10.
#
# This script does NOT run the splitter. If the per-board files are missing it
# stops and prints the split_boards.py command. Nothing checks whether they are
# stale, so re-split whenever Control_Boards.kicad_pcb changes -- the split also
# bakes the ${VERSION} silkscreen text into the derived boards, so a stale split
# means a stale version on the copper you order.
#
# Usage
# -----
#   documentation/utilities/export_gerbers.sh
#   VERSION=v2.0.4 documentation/utilities/export_gerbers.sh
#   ZIP=0 documentation/utilities/export_gerbers.sh
#
# Paths are resolved relative to the script, so it can be run from anywhere.
#
# Environment flags (all optional, defaults in brackets)
# -----------------------------------------------------
#   VERSION      [v2.0.3]  which gerbers/<version>/ to read and write.
#
#   LAYERS       [see below]  comma separated KiCad layer names. The default is
#                             the seven layers v2.0.2 shipped: both coppers, both
#                             masks, both silkscreens and the board outline. Paste
#                             layers are deliberately absent -- those are stencil
#                             data, not fab data.
#
#   DRILL_UNITS  [in]      in | mm. Inches matches the committed v2.0.1 and v2.0.2
#                          drill files; JLCPCB accepts either.
#
#   ZIP          [1]       build the per-board zip a fab wants uploaded. 0 leaves
#                          the loose files only.
#
#   EXTRA_GERBER_ARGS [ ]  extra flags passed through to `pcb export gerbers`,
#                          e.g. "--subtract-soldermask". Run
#                          `kicad-cli pcb export gerbers --help` for the full list.
#
#   KICAD_CLI    [auto]    path to kicad-cli. Searched on PATH, then the macOS
#                          app bundle, then /usr/bin.
#
# Protel file extensions (.gbl/.gtl/.gts/.gm1) are kicad-cli's default for this
# command and are what v2.0.2 used, so no flag is passed for them. Pass
# --no-protel-extension via EXTRA_GERBER_ARGS if you want plain .gbr instead.

set -euo pipefail

VERSION="${VERSION:-v2.0.3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # documentation/utilities
PROJ="$(cd "$HERE/../.." && pwd)"                      # the KiCad project directory
SRC="$PROJ/gerbers/$VERSION"
OUT="$SRC/gerber_files"

LAYERS="${LAYERS:-F.Cu,B.Cu,F.Mask,B.Mask,F.Silkscreen,B.Silkscreen,Edge.Cuts}"
DRILL_UNITS="${DRILL_UNITS:-in}"
ZIP="${ZIP:-1}"
EXTRA_GERBER_ARGS="${EXTRA_GERBER_ARGS:-}"

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
[[ -x "$KICAD_CLI" ]] || { echo "error: KICAD_CLI='$KICAD_CLI' is not executable." >&2; exit 1; }
for sub in gerbers drill; do
  "$KICAD_CLI" pcb export "$sub" --help >/dev/null 2>&1 || {
    echo "error: '$KICAD_CLI' has no 'pcb export $sub' command (needs KiCad 8+)." >&2; exit 1; }
done
echo "kicad-cli: $KICAD_CLI ($("$KICAD_CLI" version 2>/dev/null || echo 'version unknown'))"

# --- check inputs -----------------------------------------------------------
for b in brain motor; do
  [[ -f "$SRC/${b}_board.kicad_pcb" ]] || {
    echo "error: missing $SRC/${b}_board.kicad_pcb" >&2
    echo "       run: python3 \"$HERE/split_boards.py\" \"$PROJ/Control_Boards.kicad_pcb\" --outdir \"$SRC\" --write" >&2
    exit 1; }
done

echo "exporting $VERSION -> ${OUT/#$PROJ\//}"
echo "  layers: $LAYERS"

# --- plot -------------------------------------------------------------------
for board in brain motor; do
  src="$SRC/${board}_board.kicad_pcb"
  dir="$OUT/${board}_board"
  mkdir -p "$dir"

  g=( pcb export gerbers --layers "$LAYERS" -o "$dir/" )
  # shellcheck disable=SC2206
  [[ -n "$EXTRA_GERBER_ARGS" ]] && g+=( $EXTRA_GERBER_ARGS )
  g+=( "$src" )
  printf '  %s %s\n' "$(basename "$KICAD_CLI")" "${g[*]}"
  "$KICAD_CLI" "${g[@]}"

  d=( pcb export drill --format excellon --drill-origin absolute
      --excellon-units "$DRILL_UNITS" --excellon-zeros-format decimal
      -o "$dir/" "$src" )
  printf '  %s %s\n' "$(basename "$KICAD_CLI")" "${d[*]}"
  "$KICAD_CLI" "${d[@]}"
done

# --- zip --------------------------------------------------------------------
if [[ "$ZIP" == "1" ]]; then
  if ! command -v zip >/dev/null 2>&1; then
    echo "warning: 'zip' not found, skipping archives (loose files are written)." >&2
  else
    for board in brain motor; do
      z="$OUT/${board}_board_${VERSION}.zip"
      rm -f "$z"
      ( cd "$OUT" && zip -q -r "$z" "${board}_board" )
      echo "  zipped $(basename "$z") ($(unzip -l "$z" | tail -1 | awk '{print $2}') files)"
    done
  fi
fi

echo "done:"
find "$OUT" -type f | sort | sed "s|^$PROJ/||;s|^|  |"
