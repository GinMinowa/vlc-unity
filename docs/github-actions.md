# GitHub Actions builds for VLC-Unity

These workflows port the **non-watermark** (free / self-build) path from the
upstream VideoLAN `vlc-unity` GitLab CI (`.gitlab-ci.yml`) onto public GitHub
Actions runners for [GinMinowa/vlc-unity](https://github.com/GinMinowa/vlc-unity).

| Workflow | File | Runner(s) | GitLab jobs mirrored |
|----------|------|-----------|----------------------|
| Windows x86_64 | `.github/workflows/build-windows.yml` | `ubuntu-latest` + VideoLAN LLVM/msvcrt container | `libvlc-win-x86_64`, `unity-plugin-windows` |
| macOS | `.github/workflows/build-macos.yml` | `macos-14` (aarch64), `macos-13` (x86_64) | `libvlc-macos-*`, `unity-plugin-macos-*` |
| iOS arm64 | `.github/workflows/build-ios.yml` | `macos-14` | `libvlc-ios-arm64`, `unity-plugin-ios-aarch64` |

## Non-watermark (critical)

All workflows build **without** the Videolabs trial watermark:

- They **never** pass `-Dwatermark=true`.
- They **never** set `ARGS_TRIAL`.
- Meson option default in `meson_options.txt` is `watermark=false`.

Trial / watermark packaging from GitLab (`*-trial` jobs,
`package-unity-plugins-trial`) is intentionally **not** ported.

## How to run

### Manual

1. Open the repo on GitHub → **Actions**.
2. Select **Build Windows (x86_64)**, **Build macOS**, or **Build iOS (aarch64)**.
3. Click **Run workflow** (`workflow_dispatch`).

### Automatic

Each workflow also runs on `push` and `pull_request` when relevant paths change:

- `PluginSource/**`
- `build-libvlc.sh` (and `copy_ios.sh` for iOS)
- Platform cross files / `meson.build` / `meson_options.txt`
- The workflow YAML itself

This matches the GitLab `changes:` rules for plugin / CI updates.

## Artifacts

Jobs use `actions/upload-artifact` (pinned). Retention is **14 days**.

| Workflow | Artifact name(s) | Contents |
|----------|------------------|----------|
| Windows | `libvlc-win-x86_64` | LibVLC `vlc-4.0.0-dev` + `_win32` SDK tree |
| Windows | `VLCUnityPlugin-windows-x86_64` | `VLCUnityPlugin.dll` |
| macOS | `libvlc-macos-aarch64` / `libvlc-macos-x86_64` | macOS LibVLC install bits |
| macOS | `VLCUnityPlugin-macos-aarch64` / `…-x86_64` | `libVLCUnityPlugin.dylib` |
| iOS | `libvlc-ios-arm64` | `lib/` + `include/` for iphoneos/arm64 |
| iOS | `VLCUnityPlugin-ios-arm64` | `Assets/VLCUnity/Plugins/iOS` (via `copy_ios.sh`) |

Download from the completed workflow run page under **Artifacts**.

Typical flow:

1. `build-libvlc` compiles / packages LibVLC and uploads the SDK.
2. `build-unity-plugin` downloads that artifact, patches `libvlc.pc` `prefix=`,
   runs `meson` + `ninja`, and uploads the Unity plugin binary / tree.

## Supply chain notes

Trusted sources only:

| Component | Source |
|-----------|--------|
| VLC tree | Primary: `https://code.videolan.org/videolan/vlc` — fallback: `https://github.com/videolan/vlc` |
| iOS live555 patches | VideoLAN VLCKit raw URLs (same as GitLab CI) |
| Windows toolchain image | `registry.videolan.org/vlc-debian-llvm-msvcrt:20260331112916` (GitLab `VLC_WIN_LLVM_IMAGE`) |
| macOS / iOS tools | Homebrew (`meson`, `ninja`, `pkg-config`, `nasm`, autotools) |
| GitHub Actions | Pinned to commit SHAs: `actions/checkout@11d5960a…` (v4.4.0), `actions/upload-artifact@ea165f8d…` (v4.6.2), `actions/download-artifact@d3f86a10…` (v4.3.0) |

Do **not** introduce third-party binary caches, unofficial LibVLC zips, or
unpinned marketplace actions without review.

## Windows container approach

GitLab builds Windows LibVLC inside
`registry.videolan.org/vlc-debian-llvm-msvcrt` using
`extras/package/win32/build.sh` and cross-compiles the plugin with
`cross/windows-x86_64.txt`. The GHA Windows workflow uses the **same** image
via `container:` on `ubuntu-latest` for parity.

Assumptions:

- The VideoLAN registry image is **publicly pullable** from GitHub-hosted
  runners (many VideoLAN images are; if pull fails, the job fails early).
- Full win64 LibVLC compile is heavy (hours + large disk). Public GHA disk /
  time limits may be tighter than VideoLAN’s private runners.
- Native `windows-latest` + MSVC is **not** used here; that would diverge from
  GitLab’s LLVM/msvcrt cross path.

## Known gaps vs private VideoLAN runners

| Area | Gap |
|------|-----|
| Runner hardware | Public GHA macOS/Linux vs VideoLAN tagged runners (`monterey`, `macos-m1`, `macos-xcode26`, Docker amd64). Xcode major version may differ from VideoLAN’s `macos-xcode26` tag. |
| Android / UWP / Linux / packaging | Not ported in this first PR set (only Windows classic, macOS, iOS). |
| LibVLCSharp .NET jobs | Not ported (`libvlcsharp-all` / `libvlcsharp-ios`). |
| `package-unity-plugin.sh` | No combined Unity package job yet; download per-platform artifacts and assemble locally. |
| Sandbox PATH | GitLab uses `$HOME/sandbox/bin` for meson; GHA installs meson via brew (Apple) or the container (Windows). |
| Time / disk | Full LibVLC contrib builds may hit GHA timeouts or disk limits; re-run or self-hosted runners may be needed. |
| Registry auth | If `registry.videolan.org` ever requires auth from GHA IPs, Windows jobs need a mirror or self-hosted runner with the image cached. |
| Watermark / commercial | Trial watermark builds and Videolabs packaging are out of scope. |

## Local verification tips

After downloading artifacts:

- **Windows:** place `VLCUnityPlugin.dll` next to the LibVLC runtime DLLs from
  the `libvlc-win-x86_64` artifact (under `vlc-4.0.0-dev` / plugin layout used
  by the Unity package).
- **macOS:** ensure `@loader_path` rpath is present
  (`otool -l libVLCUnityPlugin.dylib | grep -A2 RPATH`).
- **iOS:** drop the uploaded `Assets/VLCUnity/Plugins/iOS` tree into your Unity
  project as produced by `copy_ios.sh`.

## Updating action pins

Pins were taken from release tags around 2026-07 / 2026-08:

```yaml
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2
uses: actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093 # v4.3.0
```

When bumping, prefer full commit SHAs with a trailing version comment.
