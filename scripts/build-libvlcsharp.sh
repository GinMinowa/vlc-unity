#!/usr/bin/env bash
# Build the Unity-specific LibVLCSharp assembly. Usage: build-libvlcsharp.sh [unity|ios]
set -euo pipefail
flavor="${1:?Usage: $0 unity|ios}"
case "$flavor" in
  unity) define=UNITY ;;
  ios) define=UNITY_IOS ;;
  *) echo "Unsupported LibVLCSharp flavor: $flavor" >&2; exit 2 ;;
esac
# Keep the managed ABI paired with LibVLC e7a30c9 (2026-06-17).
# Newer master removed Buffering, renumbered VLCState, and migrated parser APIs.
# A generic 4.x pin is NOT sufficient while LibVLC 4 is still evolving.
ref="${LIBVLCSHARP_GIT_REF:-039cd5aa7be77a003f917d8dc4ce1c43db2db6ae}"
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
# Compile the actual Unity runtime and demo sources against the DLL we ship.
# Also test enum numeric values: a successful native build cannot detect C# ABI drift.
dotnet build "$workspace/tests/ManagedCompile/ManagedCompile.csproj" \
  -c Release "/p:SharpAssembly=$assembly"
dotnet run --project "$workspace/tests/BindingContract/BindingContract.csproj" \
  -c Release "/p:SharpAssembly=$assembly"
