#!/usr/bin/env bash
# Build the Unity-specific LibVLCSharp assembly. Usage: build-libvlcsharp.sh [unity|ios]
set -euo pipefail
flavor="${1:?Usage: $0 unity|ios}"
case "$flavor" in
  unity) define=UNITY ;;
  ios) define=UNITY_IOS ;;
  *) echo "Unsupported LibVLCSharp flavor: $flavor" >&2; exit 2 ;;
esac
ref="${LIBVLCSHARP_GIT_REF:-master}"
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
dotnet build "${build_dir}/src/LibVLCSharp/LibVLCSharp.csproj" \
  "/p:${define}=true" -c Release
assembly="${build_dir}/src/LibVLCSharp/bin/Release/netstandard2.0/LibVLCSharp.dll"
[[ -s "$assembly" ]] || { echo "Missing ${assembly}" >&2; exit 1; }
mkdir -p "$output_dir"
cp "$assembly" "$output_dir/LibVLCSharp.dll"
git -C "$build_dir" rev-parse HEAD > "$output_dir/LIBVLCSHARP-COMMIT.txt"
