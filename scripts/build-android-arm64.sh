#!/usr/bin/env bash
# Runs inside registry.videolan.org/vlc-debian-android (see official .gitlab-ci.yml).
set -euo pipefail
ABI=arm64-v8a
VLC_GIT_REF="${VLC_GIT_REF:?Missing fixed VLC_GIT_REF}"
export PATH="${HOME}/sandbox/bin:${PATH}"
export ANDROID_HOME="${ANDROID_HOME:-/sdk/android-sdk-linux}"

clone_repository() {
  local dirname="$1" origin="$2" fallback="$3" ref="$4"
  local dir="${PWD}/${dirname}"
  rm -rf "$dir"
  clone_from() {
    local url="$1"
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch --depth 1 origin "$ref"
    git -C "$dir" checkout -q --detach FETCH_HEAD
  }
  if ! clone_from "$origin"; then
    echo "Falling back to GitHub mirror for ${dirname}" >&2
    clone_from "$fallback"
  fi
  git -C "$dir" rev-parse HEAD
}

clone_repository vlc-android \
  https://code.videolan.org/videolan/vlc-android.git \
  https://github.com/videolan/vlc-android.git \
  "${VLC_ANDROID_REF:-master}"
cd vlc-android
clone_repository libvlcjni \
  https://code.videolan.org/videolan/libvlcjni.git \
  https://github.com/videolan/libvlcjni.git \
  "${LIBVLCJNI_REF:-master}"
cd libvlcjni
clone_repository vlc \
  https://code.videolan.org/videolan/vlc.git \
  https://github.com/videolan/vlc.git \
  "$VLC_GIT_REF"
cd ../..

command -v meson
command -v ninja
[[ -d "$ANDROID_HOME" ]] || { echo "Missing Android SDK: ${ANDROID_HOME}" >&2; exit 1; }
cd vlc-android
./buildsystem/compile.sh -l -b -r -a "$ABI" --static-cpp --license l
cd ..

pc="${PWD}/vlc-android/libvlcjni/libvlc/jni/pkgconfig/${ABI}"
[[ -f "$pc/libvlc.pc" ]] || { echo "Missing LibVLC pkg-config ${pc}/libvlc.pc" >&2; exit 1; }
export PKG_CONFIG_PATH="$pc"
meson setup --cross-file="cross/android-${ABI}-ndk25.txt" \
  "build_android_${ABI}" -Dstatic_android=true -Dwatermark=false --buildtype release
ninja -C "build_android_${ABI}"
test -s "build_android_${ABI}/PluginSource/libVLCUnityPlugin.so"
test -s "vlc-android/libvlcjni/libvlc/jni/libs/${ABI}/libvlc.so"
test -s 'vlc-android/libvlcjni/libvlc/build/intermediates/aar_main_jar/release/syncReleaseLibJars/classes.jar'
