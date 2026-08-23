#!/usr/bin/env bash
# filter-vlc-plugins.sh — keep only LibVLC plugins needed for soft+HW decode of
# MPEG-1/2, VP8/VP9, H.264, H.265/HEVC (plus demux/access/chroma/audio-out so
# Unity can open and play files). Delete everything else before artifact upload.
#
# Usage: ./scripts/filter-vlc-plugins.sh <plugins-dir>
#
# <plugins-dir> is the VLC plugins root (nested codec/, demux/, … or flat *.dll/
# *.so/*.dylib). Does NOT touch parent libvlc / libvlccore.
#
# After filtering, plugins.dat (if present) is removed so VLC regenerates the
# cache at runtime (or via vlc-cache-gen on Windows).
#
# Compatible with bash 3.2+ (macOS /bin/bash) and bash 4+/5 (Linux GHA).

set -euo pipefail

usage() {
  echo "Usage: $0 <plugins-dir>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage

PLUGINS_DIR="$1"

if [[ ! -d "${PLUGINS_DIR}" ]]; then
  echo "ERROR: plugins directory not found: ${PLUGINS_DIR}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Whitelist: matched case-insensitively against a normalized basename.
# Normalization: strip leading "lib", strip trailing "_plugin", strip extension.
# Patterns are bash ERE (=~). Be conservative on KEEP for the decode path;
# aggressive DELETE on UI/skins/DVD/Bluray/etc. bloat.
# ---------------------------------------------------------------------------
WHITELIST_PATTERNS=(
  # Software decode (FFmpeg) — covers MPEG-1/2, VP8/9, H.264, HEVC, etc.
  '^avcodec$'
  '^avformat$'

  # Packetizers for target codecs (+ common audio companions in same files)
  '^packetizer_h264$'
  '^packetizer_hevc$'
  '^packetizer_mpeg4video$'
  '^packetizer_mpegvideo$'
  '^packetizer_vc1$'
  '^packetizer_mpeg4audio$'
  '^packetizer_aac$'
  '^packetizer_copy$'

  # Hardware decode
  '^videotoolbox$'          # Apple
  '^d3d11va$'               # Windows
  '^dxva2$'
  '^d3d9va$'
  '^d3d11$'
  '^nvdec'                  # NVIDIA (nvdec, nvdec_*)
  '^mediacodec$'            # Android; harmless if absent on desktop
  '^vdpau$'                 # Linux
  '^vaapi'                  # Linux (vaapi, vaapi_*)

  # Demux / containers (needed to open media)
  '^mp4$'
  '^mkv$'
  '^avi$'
  '^ts$'
  '^ps$'
  '^es$'
  '^asf$'
  '^ogg$'
  '^rawvid$'
  '^mpeg$'
  '^mjpeg$'
  '^h26x$'
  '^hevc$'
  '^vc1$'
  '^demux_cdg$'
  '^playlist$'
  '^adaptive$'

  # Access
  '^filesystem$'
  '^file$'
  '^http$'
  '^https$'
  '^imem$'
  '^ftp$'
  '^tcp$'
  '^udp$'
  '^rtp$'

  # Chroma / convert (frames → Unity textures)
  '^swscale$'
  '^yuv$'
  '^i420$'
  '^cvpx$'
  '^d3d11_fmt$'
  'chroma'                  # any *chroma*

  # Minimal audio output (LibVLC often needs one)
  '^adummy$'
  '^afile$'
  '^directsound$'
  '^wasapi$'
  '^waveout$'
  '^auhal$'
  '^coreaudio$'
  '^audiounit$'
  '^amem$'

  # Misc often required with avcodec (inflate/zip for some containers)
  '^inflat'
  '^zip$'
)

# Normalize plugin basename for matching:
#   libavcodec_plugin.dylib  -> avcodec
#   avcodec_plugin.dll       -> avcodec
#   libqt_plugin.so          -> qt
normalize_name() {
  local base="$1"
  base="${base##*/}"
  base="$(printf '%s' "${base}" | tr '[:upper:]' '[:lower:]')"
  case "${base}" in
    *.dll)   base="${base%.dll}" ;;
    *.dylib) base="${base%.dylib}" ;;
    *.so)    base="${base%.so}" ;;
  esac
  case "${base}" in
    lib*) base="${base#lib}" ;;
  esac
  case "${base}" in
    *_plugin) base="${base%_plugin}" ;;
  esac
  printf '%s' "${base}"
}

is_whitelisted() {
  local norm="$1"
  local pat
  for pat in "${WHITELIST_PATTERNS[@]}"; do
    if [[ "${norm}" =~ ${pat} ]]; then
      return 0
    fi
  done
  return 1
}

dir_size_bytes() {
  local d="$1"
  if ! command -v du >/dev/null 2>&1; then
    echo 0
    return
  fi
  if du -sb "${d}" >/dev/null 2>&1; then
    du -sb "${d}" | awk '{print $1}'
  else
    # BSD du (macOS): -sk → KiB
    local kb
    kb="$(du -sk "${d}" | awk '{print $1}')"
    echo $((kb * 1024))
  fi
}

human_size() {
  local b="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "${b}" 2>/dev/null || echo "${b} B"
  elif (( b >= 1073741824 )); then
    awk -v b="$b" 'BEGIN { printf "%.1f GB\n", b/1073741824 }'
  elif (( b >= 1048576 )); then
    awk -v b="$b" 'BEGIN { printf "%.1f MB\n", b/1048576 }'
  elif (( b >= 1024 )); then
    awk -v b="$b" 'BEGIN { printf "%.1f KB\n", b/1024 }'
  else
    echo "${b} B"
  fi
}

echo "==> Filtering VLC plugins in: ${PLUGINS_DIR}"

SIZE_BEFORE="$(dir_size_bytes "${PLUGINS_DIR}")"

# Collect plugin binaries into a temp list (bash 3.2–safe; no mapfile)
LIST_FILE="$(mktemp)"
trap 'rm -f "${LIST_FILE}"' EXIT
find "${PLUGINS_DIR}" -type f \( -name '*.dll' -o -name '*.so' -o -name '*.dylib' \) 2>/dev/null | sort > "${LIST_FILE}" || true

KEPT=0
DELETED=0
KEPT_LIST="$(mktemp)"
DELETED_LIST="$(mktemp)"
trap 'rm -f "${LIST_FILE}" "${KEPT_LIST}" "${DELETED_LIST}"' EXIT

while IFS= read -r f || [[ -n "${f}" ]]; do
  [[ -n "${f}" ]] || continue
  [[ -f "${f}" ]] || continue
  base="$(basename "${f}")"
  norm="$(normalize_name "${base}")"
  if is_whitelisted "${norm}"; then
    KEPT=$((KEPT + 1))
    echo "${base}" >> "${KEPT_LIST}"
  else
    chmod u+w "${f}" 2>/dev/null || true
    rm -f "${f}" || { echo "ERROR: could not delete ${f} (permission?)" >&2; exit 1; }
    DELETED=$((DELETED + 1))
    echo "${base}" >> "${DELETED_LIST}"
  fi
done < "${LIST_FILE}"

# Remove stale plugin cache so VLC regenerates
if [[ -f "${PLUGINS_DIR}/plugins.dat" ]]; then
  rm -f "${PLUGINS_DIR}/plugins.dat"
  echo "NOTE: removed plugins.dat — regenerate with vlc-cache-gen on Windows, or let VLC rebuild at runtime."
fi
find "${PLUGINS_DIR}" -type f -name 'plugins.dat' 2>/dev/null | while IFS= read -r dat; do
  [[ -n "${dat}" ]] || continue
  rm -f "${dat}"
  echo "NOTE: removed ${dat}"
done

# Prune empty directories (deepest first)
find "${PLUGINS_DIR}" -depth -type d -empty -delete 2>/dev/null || true

SIZE_AFTER="$(dir_size_bytes "${PLUGINS_DIR}")"

echo ""
echo "==> Summary"
echo "    kept:    ${KEPT}"
echo "    deleted: ${DELETED}"
echo "    size:    $(human_size "${SIZE_BEFORE}" | tr -d '\n') -> $(human_size "${SIZE_AFTER}" | tr -d '\n')"
if [[ ${KEPT} -gt 0 ]]; then
  echo "    kept plugins:"
  sort -u "${KEPT_LIST}" | sed 's/^/      - /'
fi
if [[ ${DELETED} -gt 0 && ${DELETED} -le 80 ]]; then
  echo "    deleted plugins:"
  sort -u "${DELETED_LIST}" | sed 's/^/      - /'
elif [[ ${DELETED} -gt 80 ]]; then
  echo "    deleted plugins: (${DELETED} files; listing omitted)"
fi

if [[ ${KEPT} -eq 0 ]]; then
  echo "WARNING: no plugins kept — whitelist may be too strict or plugins dir layout unexpected" >&2
fi

exit 0
