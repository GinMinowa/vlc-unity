#!/usr/bin/env bash
# Build the Unity-specific LibVLCSharp assembly. Usage: build-libvlcsharp.sh [unity|ios]
set -euo pipefail
flavor="${1:?Usage: $0 unity|ios}"
case "$flavor" in
  unity) define=UNITY ;;
  ios) define=UNITY_IOS ;;
  *) echo "Unsupported LibVLCSharp flavor: $flavor" >&2; exit 2 ;;
esac
# Pin the Unity-capable LibVLCSharp 4.x source; the default GitHub branch is 3.x.
ref="${LIBVLCSHARP_GIT_REF:-52cb7c5b871752c6beeb3f32984a294a72cc52c8}"
repo="${LIBVLCSHARP_GIT_URL:-https://code.videolan.org/videolan/LibVLCSharp.git}"
workspace="${GITHUB_WORKSPACE:-$(pwd)}"
build_dir="${workspace}/_libvlcsharp-src"
output_dir="${workspace}/_libvlcsharp-${flavor}"
rm -rf "$build_dir" "$output_dir"
clone_at_ref() {
  local url="$1"
  rm -rf "$build_dir"
  git init -q "$build_dir"
  git -C "$build_dir" remote add origin "$url"
  git -C "$build_dir" fetch --depth 1 origin "$ref"
  git -C "$build_dir" checkout -q --detach FETCH_HEAD
}
if ! clone_at_ref "$repo"; then
  echo "VideoLAN host unavailable; trying GitHub mirror." >&2
  clone_at_ref https://github.com/videolan/libvlcsharp.git
fi
printf 'LibVLCSharp source: %s\n' "$(git -C "$build_dir" rev-parse HEAD)"
# UNITY selects compilation symbols but upstream still declares mobile TFMs.
# Restrict BOTH restore's TargetFrameworks and build's TargetFramework so macOS
# does not try to install unrelated Android/iOS workloads (NETSDK1147).
mkdir -p "$output_dir"
(
  cd "$build_dir"
  dotnet build src/LibVLCSharp/LibVLCSharp.csproj \
    "/p:${define}=true" /p:TargetFrameworks=netstandard2.0 \
    /p:GeneratePackageOnBuild=false -f netstandard2.0 -c Release \
    --output "$output_dir"
)
assembly="${output_dir}/LibVLCSharp.dll"
[[ -s "$assembly" ]] || { echo "Missing ${assembly}" >&2; exit 1; }
git -C "$build_dir" rev-parse HEAD > "$output_dir/LIBVLCSHARP-COMMIT.txt"
