#!/usr/bin/env bash
# Render the per-board 3D documentation images, the way documentation/v2.0.1/3d_images
# was produced by hand -- but reproducibly.
#
#   ./render_3d.sh                 # render the version set in VERSION below
#   VERSION=v2.0.4 ./render_3d.sh  # render a different revision
#
# Inputs : gerbers/$VERSION/{brain,motor}_board.kicad_pcb  (single-board files,
#          produced by split_boards.py from the combined Control_Boards.kicad_pcb)
# Outputs: documentation/$VERSION/3d_images/{brain,motor}_{top,bottom}[_iso].png
#
# Requires KiCad 8 or newer for `kicad-cli pcb render`. Verified against KiCad 10.

set -euo pipefail

VERSION="${VERSION:-v2.0.3}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/gerbers/$VERSION"
OUT="$HERE/documentation/$VERSION/3d_images"

# Render settings. `basic` quality matches the flat OpenGL look of the v2.0.1
# images; bump to `high` or `ultra` for raytraced shadows and reflections.
QUALITY="${QUALITY:-basic}"
BACKGROUND="${BACKGROUND:-opaque}"   # opaque | transparent | checkered
PRESET="${PRESET:-FOLLOW_PLOT_SETTINGS}"

# Isometric camera angles, as 'X,Y,Z' degrees applied after --side.
# Tweak these two lines if you want a different three-quarter view.
ISO_TOP="-45,0,45"
ISO_BOTTOM="45,0,45"

# Per-board canvas. The motor board is a wide T; the brain board is square.
# (kept as a case, not an associative array, so this runs on the bash 3.2 that
#  ships with macOS as well as on bash 4+)
canvas() {
  case "$1" in
    motor) echo "2400 1800" ;;
    brain) echo "1800 1800" ;;
    *)     echo "1600 900"  ;;
  esac
}

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
# Note: `pcb render` uses -h as the short form of --height, so ask for --help.
if ! "$KICAD_CLI" pcb render --help >/dev/null 2>&1; then
  echo "error: '$KICAD_CLI' has no 'pcb render' command (needs KiCad 8+)." >&2
  exit 1
fi
echo "kicad-cli: $KICAD_CLI ($("$KICAD_CLI" version 2>/dev/null || echo 'version unknown'))"

# --- check inputs -----------------------------------------------------------
for b in brain motor; do
  [[ -f "$SRC/${b}_board.kicad_pcb" ]] || {
    echo "error: missing $SRC/${b}_board.kicad_pcb" >&2
    echo "       run: python3 split_boards.py Control_Boards.kicad_pcb --outdir gerbers/$VERSION --write" >&2
    exit 1; }
done
mkdir -p "$OUT"

# --- render -----------------------------------------------------------------
render() {  # render <board> <name> <side> [rotate]
  local board="$1" name="$2" side="$3" rot="${4:-}"
  local cw ch; read -r cw ch <<<"$(canvas "$board")"
  local cmd
  cmd=( "$KICAD_CLI" pcb render
                 --side "$side"
                 --width "$cw" --height "$ch"
                 --quality "$QUALITY"
                 --background "$BACKGROUND"
                 --preset "$PRESET"
                 --zoom 1.0 )
  [[ -n "$rot" ]] && cmd+=( --rotate "$rot" )
  cmd+=( -o "$OUT/${board}_${name}.png" "$SRC/${board}_board.kicad_pcb" )
  printf '  %s\n' "${cmd[*]}"
  "${cmd[@]}"
}

echo "rendering $VERSION -> ${OUT/#$HERE\//}"
for board in brain motor; do
  render "$board" top        top
  render "$board" top_iso    top    "$ISO_TOP"
  render "$board" bottom     bottom
  render "$board" bottom_iso bottom "$ISO_BOTTOM"
done

echo "done:"
ls -la "$OUT"
