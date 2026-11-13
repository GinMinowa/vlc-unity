#!/usr/bin/env bash
# Create one complete, importable VLC Unity plugin ZIP for one target.
# Usage: scripts/package-platform.sh windows|macos|ios|android
set -euo pipefail
platform="${1:?Usage: $0 windows|macos|ios|android}"
root="${GITHUB_WORKSPACE:-$(pwd)}"
cd "$root"
case "$platform" in
  windows) artifact="VLCUnity-Windows-x86_64"; dest='Windows/x86_64'; sharp='_libvlcsharp-unity';;
  macos) artifact="VLCUnity-macOS-ARM64"; dest='MacOS/ARM64'; sharp='_libvlcsharp-unity';;
  ios) artifact="VLCUnity-iOS-ARM64"; dest='iOS'; sharp='_libvlcsharp-ios';;
  android) artifact="VLCUnity-Android-arm64-v8a"; dest='Android'; sharp='_libvlcsharp-unity';;
  *) echo "Invalid platform: $platform" >&2; exit 2;;
esac
require_file() { [[ -s "$1" ]] || { echo "Missing/empty required file: $1" >&2; exit 1; }; }
require_dir() { [[ -d "$1" ]] || { echo "Missing required directory: $1" >&2; exit 1; }; }
require_file "${sharp}/LibVLCSharp.dll"
stage="${root}/_stage/${artifact}"
plugin_dest="${stage}/Assets/VLCUnity/Plugins/${dest}"
rm -rf "$stage"
mkdir -p "$plugin_dest" "${root}/dist"
# Include the managed integration and importer/build postprocessors, not only
# native binaries. Exclude the source Plugins tree so stale binaries for another
# architecture cannot leak into a platform package. Keep stable Unity meta GUIDs.
require_dir Assets/VLCUnity
(
  cd Assets
  tar --exclude='VLCUnity/Plugins' -cf - VLCUnity VLCUnity.meta
) | (cd "${stage}/Assets" && tar -xf -)
require_file LICENSE
cp LICENSE "${stage}/LICENSE"
case "$platform" in
  windows)
    # Artifact upload strips the shared parent, so the downloaded runtime can be at ./*
    # or at vlc-win64/win64/ when packaging locally.
    runtime=""
    for candidate in './vlc-4.0.0-dev' './vlc-win64/win64/vlc-4.0.0-dev'; do
      [[ -d "$candidate" ]] && runtime="$candidate" && break
    done
    require_dir "$runtime"
    require_file 'vlc-win64/VLCUnityPlugin.dll'
    for dll in libvlc.dll libvlccore.dll vlc-cache-gen.exe; do
      require_file "${runtime}/${dll}"
      cp "${runtime}/${dll}" "$plugin_dest/"
    done
    require_dir "${runtime}/plugins"
    require_dir "${runtime}/lua"
    cp -R "${runtime}/plugins" "${runtime}/lua" "$plugin_dest/"
    cp vlc-win64/VLCUnityPlugin.dll "$plugin_dest/"
    cp "${sharp}/LibVLCSharp.dll" "${stage}/Assets/VLCUnity/Plugins/LibVLCSharp.dll"
    ;;
  macos)
    runtime='macos-aarch64/macos-install/lib'
    require_dir "$runtime/vlc"
    for dylib in libvlc.dylib libvlccore.dylib; do
      require_file "${runtime}/${dylib}"
      cp -L "${runtime}/${dylib}" "$plugin_dest/"
    done
    require_file build_aarch64/PluginSource/libVLCUnityPlugin.dylib
    cp build_aarch64/PluginSource/libVLCUnityPlugin.dylib "$plugin_dest/"
    cp -R "${runtime}/vlc" "$plugin_dest/"
    cp "${sharp}/LibVLCSharp.dll" "${stage}/Assets/VLCUnity/Plugins/LibVLCSharp.dll"
    ;;
  ios)
    source_dir='Assets/VLCUnity/Plugins/iOS'
    require_dir "${source_dir}/arm64/VLCUnityPlugin.framework"
    require_dir "${source_dir}/arm64/vlc.framework"
    require_dir "${source_dir}/arm64/vlccore.framework"
    cp -R "${source_dir}/." "$plugin_dest/"
    cp "${sharp}/LibVLCSharp.dll" "$plugin_dest/"
    ;;
  android)
    plugin='build_android_arm64-v8a/PluginSource/libVLCUnityPlugin.so'
    engine='vlc-android/libvlcjni/libvlc/jni/libs/arm64-v8a/libvlc.so'
    classes='vlc-android/libvlcjni/libvlc/build/intermediates/aar_main_jar/release/syncReleaseLibJars/classes.jar'
    require_file "$plugin"
    require_file "$engine"
    require_file "$classes"
    mkdir -p "$plugin_dest/libs/arm64-v8a"
    cp "$plugin" "$engine" "$plugin_dest/libs/arm64-v8a/"
    # Java JAR must not be tied to a native ABI; Unity imports JARs under Plugins/Android.
    cp "$classes" "$plugin_dest/classes.jar"
    cp "${sharp}/LibVLCSharp.dll" "${stage}/Assets/VLCUnity/Plugins/LibVLCSharp.dll"
    ;;
esac
cat > "${stage}/BUILD-INFO.txt" <<INFO
VLC Unity CI package: ${artifact}
VLC source ref: ${VLC_GIT_REF:-not provided}
LibVLCSharp source commit: $(cat "${sharp}/LIBVLCSHARP-COMMIT.txt" 2>/dev/null || echo unknown)
VLC Unity source: ${GITHUB_SHA:-local snapshot}
Watermark: disabled (-Dwatermark=false)
Bundle: native Unity rendering plugin, LibVLC engine and LibVLCSharp C# bindings
NOTE: confirm LGPL-2.1 redistribution obligations before distributing to others.
INFO
rm -f "${root}/dist/${artifact}.zip"
(
  cd "$stage"
  zip -q -r "${root}/dist/${artifact}.zip" .
)
require_file "dist/${artifact}.zip"
unzip -t "dist/${artifact}.zip" | tail -n1
printf 'Created dist/%s.zip\n' "$artifact"
