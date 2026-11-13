# GitHub Actions builds for VLC-Unity

These workflows port the **non-watermark** (free / self-build) path from the
upstream VideoLAN `vlc-unity` GitLab CI (`.gitlab-ci.yml`) onto public GitHub
Actions runners for [GinMinowa/vlc-unity](https://github.com/GinMinowa/vlc-unity).

| Workflow | File | Runner(s) | GitLab jobs mirrored |
|----------|------|-----------|----------------------|
| Windows x86_64 | `.github/workflows/build-windows.yml` | `ubuntu-latest` + `docker run` VideoLAN LLVM/msvcrt image | `libvlc-win-x86_64`, `unity-plugin-windows` |
| macOS | `.github/workflows/build-macos.yml` | `macos-15` (aarch64 only) | `libvlc-macos-aarch64`, `unity-plugin-macos-aarch64` |
| iOS arm64 | `.github/workflows/build-ios.yml` | `macos-15` | `libvlc-ios-arm64`, `unity-plugin-ios-aarch64` |

## Non-watermark (critical)

All workflows build **without** the Videolabs trial watermark:

- They **never** pass `-Dwatermark=true`.
- They **never** set `ARGS_TRIAL`.
- Meson option default in `meson_options.txt` is `watermark=false`.

Trial / watermark packaging from GitLab (`*-trial` jobs,
`package-unity-plugins-trial`) is intentionally **not** ported.

## LibVLC git ref (production pin for release 2026-3)

Branch `build/release-2026-3` is based on **vlc-unity tag `2026-3`**
(commit `bcffbde1a513…`) and clones VideoLAN VLC at a **fixed commit SHA**.
This is a **production** pin: **not** floating `master`, and **not** the
ancient git tag `4.0.0-dev`.

| Env | Default | Meaning |
|-----|---------|---------|
| `VLC_GIT_REF` | `e7a30c9d47e8328de37cf1760a815e0af673fe12` | Trial v9 / **2026-3 engine** LibVLC (`e7a30c9d47`, 2026-06-17). Matches PluginSource on tag `2026-3` (single-arg `libvlc_media_player_new(inst)`, `output->opengl_format` without named union `.u`). |

Why this pin:

- Production builds for **vlc-unity 2026-3** must use the LibVLC engine that
  the tagged PluginSource was written against (`e7a30c9d47`), not a later
  master tip that introduced `media_player_cbs` / named union `u` (those need
  PluginSource commit `cee01f0`, which is **intentionally excluded** from this
  branch).
- VLC Unity expects **LibVLC 4**. There is no 4.0 stable release yet.
- The git **tag** `4.0.0-dev` is from **2017-11-30** (commit `1f2e534`). It
  lacks `extras/package/apple/build.sh`, and old `macosx`/`win32` `build.sh`
  scripts reject modern flags — so pinning that tag is wrong for CI.
- Consumer **3.0.x** is the wrong major for this plugin.
- Floating `master` drifts (extras/tools, GNU mirrors, LibVLC APIs); a SHA
  keeps builds reproducible and API-compatible with tag `2026-3`.

Clone pattern (every workflow, including the Windows docker `bash -c` script).
**Do not** use `git clone --branch` — a SHA is not a branch/tag name for
`--branch`. Use shallow fetch-by-SHA instead:

```bash
REF="${VLC_GIT_REF}"
clone_ref() {
  local url="$1"
  rm -rf vlc
  git init vlc
  git -C vlc remote add origin "$url"
  git -C vlc fetch --depth=1 origin "$REF"
  git -C vlc checkout --force FETCH_HEAD
}
if clone_ref https://code.videolan.org/videolan/vlc.git; then
  echo "Cloned VLC from code.videolan.org"
else
  echo "Primary failed; GitHub mirror"
  clone_ref https://github.com/videolan/vlc.git
fi
echo "Building LibVLC from ${REF}"
git -C vlc rev-parse HEAD
git -C vlc describe --tags --always || true
```

Windows passes `-e VLC_GIT_REF` into `docker run` so the in-container clone
sees the same pin.

### GNU extras/tools mirror (`packages.mak`)

Pinned LibVLC (`e7a30c9d47` / trial v9) sets `GNU=https://ftpmirror.gnu.org/gnu`
in `vlc/extras/tools/packages.mak`. That mirror has returned **HTTP 502** for
`m4-1.4.21.tar.gz` (and likely gettext), which aborts the tools bootstrap within
~1–2 minutes after a successful clone. The VideoLAN contrib mirror also lacks
`m4-1.4.21` (404). Official `https://ftp.gnu.org/gnu` returns 200.

After every VLC clone (and before patches / `build.sh`), all three workflows
rewrite that line to `GNU=https://ftp.gnu.org/gnu`:

- **macOS / iOS:** dedicated host step right after “Clone VLC”.
- **Windows:** same `sed` inside the Docker `bash -c` script (clone is
  in-container only; the host never has a pre-clone `vlc/` tree to patch).

### Bumping `VLC_GIT_REF`

1. Edit `VLC_GIT_REF` in:
   - `.github/workflows/build-windows.yml`
   - `.github/workflows/build-macos.yml`
   - `.github/workflows/build-ios.yml`
2. Prefer a **full commit SHA** on the LibVLC 4 line that stays API-compatible
   with this branch’s PluginSource (tag `2026-3` APIs). Do **not** jump to a
   post-`media_player_cbs` master tip without also porting PluginSource
   (`cee01f0` and later). Do not use the 2017 tag `4.0.0-dev` or 3.0.x.
3. Re-run all three workflows and confirm artifact layouts still match
   (`vlc-4.0.0-dev` on Windows, etc.).
4. iOS live555 patches from VLCKit are applied **best-effort** on this pin
   (they targeted master tip); a patch miss logs `WARN` and does not fail the
   job by itself.

## How to run

### Manual

1. Open the repo on GitHub → **Actions**.
2. Select **Build Windows (x86_64)**, **Build macOS**, or **Build iOS (aarch64)**.
3. Click **Run workflow** (`workflow_dispatch`).

### Automatic

Each workflow also runs on `push` and `pull_request` when relevant paths change:

- `PluginSource/**`
- `build-libvlc.sh` (and `copy_ios.sh` for iOS)
- `scripts/filter-vlc-plugins.sh`
- Platform cross files / `meson.build` / `meson_options.txt`
- The workflow YAML itself

This matches the GitLab `changes:` rules for plugin / CI updates.

## Artifacts

Jobs use `actions/upload-artifact` (pinned). Retention is **14 days**.

| Workflow | Artifact name(s) | Contents |
|----------|------------------|----------|
| Windows | `libvlc-win-x86_64` | LibVLC `vlc-4.0.0-dev` + `_win32` SDK tree |
| Windows | `VLCUnityPlugin-windows-x86_64` | `VLCUnityPlugin.dll` |
| macOS | `libvlc-macos-aarch64` | macOS LibVLC install bits |
| macOS | `VLCUnityPlugin-macos-aarch64` | `libVLCUnityPlugin.dylib` |
| iOS | `libvlc-ios-arm64` | Whole `vlc-iphoneos-arm64` install tree |
| iOS | `VLCUnityPlugin-ios-arm64` | `Assets/VLCUnity/Plugins/iOS` (via `copy_ios.sh`) |

Download from the completed workflow run page under **Artifacts**.

### Job layout

- **Windows:** two jobs still (LibVLC artifact → plugin). Checkout and
  `upload`/`download-artifact` run on the **host**; compile steps use
  `docker run` (see below).
- **iOS / macOS:** **single job** each — LibVLC then meson/plugin in the same
  runner, then upload both artifacts. This avoids `download-artifact` path
  layout mismatches (e.g. flattened `lib/` vs `vlc/build/vlc-iphoneos-arm64`).

## Codec-filtered LibVLC packaging

After each platform’s LibVLC build (and **before** artifact upload / `copy_ios.sh`),
workflows run `scripts/filter-vlc-plugins.sh` on the VLC `plugins/` tree. The
script keeps only modules needed for soft + hardware decode of **MPEG-1, MPEG-2,
VP8, VP9, H.264, H.265/HEVC**, plus essential demux/access/chroma/packetizer/
audio-out so Unity can open and play files. Everything else (Qt/skins, DVD,
Blu-ray, visualizations, Chromecast, VNC, …) is deleted to shrink artifacts.

| Workflow | Plugins path filtered |
|----------|------------------------|
| Windows | `vlc-win64/win64/vlc-4.0.0-dev/plugins` (host, after docker build) |
| macOS | `macos-aarch64/macos-install/lib/vlc/plugins` |
| iOS | `vlc/build/vlc-iphoneos-arm64/lib/vlc/plugins` (before `copy_ios.sh`) |

Whitelist intent (see comments in the script):

- **Soft decode:** `avcodec`, `avformat`
- **HW decode:** VideoToolbox, D3D11VA/DXVA2, NVDEC, MediaCodec, VAAPI/VDPAU
- **Packetizers:** h264/hevc/mpeg*/aac/copy (+ optional vc1)
- **Demux:** mp4, mkv, avi, ts, ps, es, asf, ogg, rawvid, mpeg, playlist, adaptive, …
- **Access:** filesystem/file, http(s), imem, ftp, tcp/udp/rtp
- **Chroma:** swscale, yuv, i420, cvpx, d3d11_fmt, `*chroma*`
- **Audio out (minimal):** adummy, afile, wasapi/directsound/waveout, auhal/coreaudio/audiounit, amem

`plugins.dat` is removed after filtering. On Windows the workflow tries
`wine` + `vlc-cache-gen.exe` when available; otherwise VLC regenerates the
cache at first runtime.

### Widening the keep-list

Edit `WHITELIST_PATTERNS` in `scripts/filter-vlc-plugins.sh` (bash ERE matched
against a normalized basename: strip `lib` prefix, `_plugin` suffix, and
extension). Re-run any affected workflow; path filters include the script so
pushes to it trigger rebuilds.

## Supply chain notes

Trusted sources only:

| Component | Source |
|-----------|--------|
| VLC tree | Primary: `https://code.videolan.org/videolan/vlc` @ SHA `VLC_GIT_REF` (`e7a30c9d47…`, trial v9 / 2026-3 engine) — fallback: `https://github.com/videolan/vlc` (same SHA). Production pin for tag `2026-3`. Not tag `4.0.0-dev`, not floating `master`. |
| iOS live555 patches | VideoLAN VLCKit raw URLs (same as GitLab CI); best-effort soft apply on pinned SHA (WARN + continue if miss) |
| Windows toolchain image | `registry.videolan.org/vlc-debian-llvm-msvcrt:20260331112916` (GitLab `VLC_WIN_LLVM_IMAGE`) |
| macOS / iOS tools | Homebrew (`meson`, `ninja`, `pkg-config`, `nasm`, autotools) |
| GitHub Actions | Pinned to commit SHAs: `actions/checkout@11d5960a…` (v4.4.0), `actions/upload-artifact@ea165f8d…` (v4.6.2), `actions/download-artifact@d3f86a10…` (v4.3.0) |

Do **not** introduce third-party binary caches, unofficial LibVLC zips, or
unpinned marketplace actions without review.

## Windows: docker run (not job `container:`)

GitLab builds Windows LibVLC inside
`registry.videolan.org/vlc-debian-llvm-msvcrt` using
`extras/package/win32/build.sh` and cross-compiles the plugin with
`cross/windows-x86_64.txt`.

GHA does **not** use job-level `container:` for that image: `actions/checkout`
often fails inside it (missing Node / git / UID mapping). Instead:

1. Checkout on `ubuntu-latest` (host).
2. `docker pull` the same VideoLAN tag.
3. `docker run --rm -u 0 -v "$GITHUB_WORKSPACE:/workspace" -w /workspace …`
   for clone + `build.sh` / meson+ninja.

Assumptions:

- The VideoLAN registry image is **publicly pullable** from GitHub-hosted
  runners (confirmed reachable when the old job-container path got past pull).
- Full win64 LibVLC compile is heavy (hours + large disk). Public GHA disk /
  time limits may be tighter than VideoLAN’s private runners.
- Native `windows-latest` + MSVC is **not** used here; that would diverge from
  GitLab’s LLVM/msvcrt cross path.

## macOS: macos-14 only

The macOS workflow keeps **macos-14 + aarch64** only. The previous
`macos-13` / x86_64 matrix entry was dropped (deprecated runner, long queue).

## Known gaps vs private VideoLAN runners

| Area | Gap |
|------|-----|
| Runner hardware | Public GHA macOS/Linux vs VideoLAN tagged runners (`monterey`, `macos-m1`, `macos-xcode26`, Docker amd64). Xcode major version may differ from VideoLAN’s `macos-xcode26` tag. |
| Android / UWP / Linux / packaging | Not ported in this first PR set (only Windows classic, macOS aarch64, iOS). |
| LibVLCSharp .NET jobs | Not ported (`libvlcsharp-all` / `libvlcsharp-ios`). |
| `package-unity-plugin.sh` | No combined Unity package job yet; download per-platform artifacts and assemble locally. |
| Sandbox PATH | GitLab uses `$HOME/sandbox/bin` for meson; GHA installs meson via brew (Apple) or the container (Windows). |
| Time / disk | Full LibVLC contrib builds may hit GHA timeouts or disk limits; re-run or self-hosted runners may be needed. |
| Registry auth | If `registry.videolan.org` ever requires auth from GHA IPs, Windows jobs need a mirror or self-hosted runner with the image cached. |
| Watermark / commercial | Trial watermark builds and Videolabs packaging are out of scope. |
| macOS Intel | x86_64 / macos-13 path not built on GHA anymore. |

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
