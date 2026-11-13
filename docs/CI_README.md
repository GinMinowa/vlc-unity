# GitHub Actions: full VLC Unity packages

This fork builds **Windows x86_64, macOS ARM64, iOS ARM64, Android ARM64**.
No macOS Intel x86_64 or Android ARMv7 binary is produced.

All native Unity plugins use `-Dwatermark=false`. This is the **open-source build**,
not a purchased Videolabs binary; remember to meet VLC and LibVLCSharp LGPL
redistribution requirements when shipping binaries.

## Manual builds

In **Actions**, open an individual `Build ...` workflow and select **Run workflow**.
Windows, macOS and iOS also offer an optional `filter_plugins` checkbox. The default
(`false`) keeps every VLC plugin for maximum format/protocol support; enabling the
whitelist may drop some codecs, subtitle renderers or network protocols.

After the workflow succeeds, open its **Summary > Artifacts** and download:

| Platform | Complete artifact |
| --- | --- |
| Windows x64 | `VLCUnity-Windows-x86_64` |
| macOS Apple Silicon | `VLCUnity-macOS-ARM64` |
| iOS ARM64 | `VLCUnity-iOS-ARM64` |
| Android ARM64 / Quest | `VLCUnity-Android-arm64-v8a` |

Artifacts contain a ZIP file with `Assets/VLCUnity/`, including runtime C# code,
editor import/build processors, native plugins, metadata, and the project license. **Extract the ZIP
into the Unity project root**, *not* directly into `Assets/VLCUnity/Plugins/`.
Windows, macOS and Android packages put the same managed assembly at
`Assets/VLCUnity/Plugins/LibVLCSharp.dll` so their ZIPs can be combined without
creating three copies. The iOS build has a separate `UNITY_IOS=true` assembly at
`Assets/VLCUnity/Plugins/iOS/LibVLCSharp.dll`; **configure that iOS-only DLL in
the Unity Plugin Importer** if combining iOS with desktop/Android packages.
Artifacts are retained for 90 days, or less if repository settings impose a shorter limit.

## Release builds

Once the four CI workflows are green, create a new tag on the intended release commit:

```bash
git switch build/release-2026-3
git pull --ff-only origin build/release-2026-3
git tag unity-v2026.3.1
git push origin unity-v2026.3.1
```

The **Release VLC Unity** workflow invokes all four platform builds on **the exact tag**;
if any fail, `publish` is skipped. After all succeed, it publishes four checked ZIPs
on the repository's GitHub **Releases** page. `workflow_dispatch` can test all four
platforms without publishing a release.

## Build inputs and caveats

- VLC is pinned to `e7a30c9d47e8328de37cf1760a815e0af673fe12`.
- Android uses VideoLAN's `vlc-debian-android` image and the official `vlc-android`
  → `libvlcjni` → `vlc` structure; `vlc-android` and `libvlcjni` presently track
  their `master` branches. For perfectly reproducible releases, pin those two refs
  after the first proven green build.
- LibVLCSharp is pinned to `52cb7c5b871752c6beeb3f32984a294a72cc52c8`,
  built with `UNITY=true` or `UNITY_IOS=true` and restricted to `netstandard2.0`.
  Unrelated mobile .NET workloads are not required. The package records this ref
  in `BUILD-INFO.txt`.
- iOS patch files come from a pinned VLCKit commit, **not** floating `master`;
  an incompatible patch now fails the workflow instead of being silently skipped.
- Android `classes.jar` is copied to `Assets/VLCUnity/Plugins/Android/classes.jar`,
  outside the native `arm64-v8a` subdirectory, for normal Unity Java-plugin import.
- Android Vulkan requires an appropriate Android device/API; Unity project settings,
  codec compatibility, hardware acceleration and iOS signing still need device tests.
- Building all of LibVLC from source can use significant CI minutes and storage.

**Validation status:** syntax checks and synthetic packaging tests do **not** prove
that the native VideoLAN toolchains succeed. Always check actual Actions logs and
run playback smoke tests (H.264, H.265, audio, subtitles, network streams) before a
production release.
