#!/usr/bin/env bash
# Export the schematic PDF for documentation/<version>/, the counterpart to the
# hand-made documentation/v2.0.1/schematics.pdf.
#
# Input : Control_Boards.kicad_sch; kicad-cli follows the hierarchy to the
#         Brain_Board and Motor_Board sub-sheets itself
# Output: documentation/$VERSION/schematics.pdf
#
# Requires KiCad 8 or newer for `kicad-cli sch export pdf`. Verified against KiCad 10.
#
# Usage
# -----
#   documentation/utilities/export_schematic.sh
#   BLACK_AND_WHITE=1 documentation/utilities/export_schematic.sh
#   DEFINE_VAR=VERSION VERSION=v2.0.4 documentation/utilities/export_schematic.sh
#
# Paths are resolved relative to the script, so it can be run from anywhere.
# This script does NOT modify the schematic.
#
# Environment flags (all optional, defaults in brackets)
# -----------------------------------------------------
#   VERSION          [v2.0.3]  which documentation/<version>/ to write. Note this
#                              only picks the output directory -- the version
#                              printed in the title block comes from the project
#                              text variable, unless DEFINE_VAR is set.
#
#   DEFINE_VAR       [ ]       set to VERSION to pass --define-var VERSION=$VERSION
#                              to kicad-cli, overriding the project text variable
#                              for this one export.
#
#   BLACK_AND_WHITE  [0]       1 plots monochrome (kicad-cli --black-and-white).
#
#   THEME            [sch]     colour theme name; empty uses the schematic's own.
#
#   KICAD_CLI        [auto]    path to kicad-cli. Searched on PATH, then the macOS
#                              app bundle, then /usr/bin.
#
# The version comes from the ${VERSION} text variable in each sheet's Rev field,
# resolved against the project variable table (Schematic Editor -> File ->
# Schematic Setup -> Project -> Text Variables), stored in Control_Boards.kicad_pro
# and shared with the board. Bumping a revision is one edit there; this script
# does not touch the schematic at all. DEFINE_VAR overrides the project value for
# a single export, e.g. to plot a v2.0.4 preview without editing the project.

set -euo pipefail

VERSION="${VERSION:-v2.0.3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # documentation/utilities
PROJ="$(cd "$HERE/../.." && pwd)"                      # the KiCad project directory
OUT="$PROJ/documentation/$VERSION"

BLACK_AND_WHITE="${BLACK_AND_WHITE:-0}"
THEME="${THEME:-}"
DEFINE_VAR="${DEFINE_VAR:-}"

# --- locate the schematic ---------------------------------------------------
if [[ -f "$PROJ/Control_Boards.kicad_sch" ]]; then
  ROOT="$PROJ/Control_Boards.kicad_sch"
elif [[ -f "$PROJ/Control_Boards.sch" ]]; then
  ROOT="$PROJ/Control_Boards.sch"
  echo "note: using the legacy $(basename "$ROOT"); see the header if kicad-cli refuses it." >&2
else
  echo "error: no Control_Boards.kicad_sch or Control_Boards.sch in $PROJ" >&2
  exit 1
fi

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
if ! "$KICAD_CLI" sch export pdf --help >/dev/null 2>&1; then
  echo "error: '$KICAD_CLI' has no 'sch export pdf' command (needs KiCad 8+)." >&2
  exit 1
fi
echo "kicad-cli: $KICAD_CLI ($("$KICAD_CLI" version 2>/dev/null || echo 'version unknown'))"

# --- export -----------------------------------------------------------------
mkdir -p "$OUT"
args=( sch export pdf -o "$OUT/schematics.pdf" )
[[ "$BLACK_AND_WHITE" == "1" ]] && args+=( --black-and-white )
[[ -n "$THEME"      ]] && args+=( --theme "$THEME" )
[[ -n "$DEFINE_VAR" ]] && args+=( --define-var "$DEFINE_VAR=$VERSION" )
args+=( "$ROOT" )

echo "exporting $VERSION -> ${OUT/#$PROJ\//}/schematics.pdf"
printf '  %s %s\n' "$(basename "$KICAD_CLI")" "${args[*]}"
"$KICAD_CLI" "${args[@]}"

echo "done:"
ls -la "$OUT/schematics.pdf"
