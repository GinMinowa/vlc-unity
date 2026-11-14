# Experimental iOS VP9 hardware decoding

This is an opt-in backport, not a device-verified production claim. Run the
Build iOS workflow with `experimental_vp9_videotoolbox=true`. Normal releases
and all other platforms are unchanged. The experimental ZIP/artifacts are
explicitly named `experimental-vp9`.

## Provenance and limits

The hardware-decoding patch is unchanged upstream VLC commit
[b53d8f021745ddf5eef14530710078edf20ce914](https://github.com/videolan/vlc/commit/b53d8f021745ddf5eef14530710078edf20ce914),
backported to native VLC e7a30c9d47e8328de37cf1760a815e0af673fe12 without
upgrading LibVLC's ABI or LibVLCSharp. It supplies the VP9 parser, vpcC decoder
configuration, superframe repacker and VideoToolbox decoder integration.

Upstream describes support on **some iOS devices running iOS 26.2 or newer**,
not every iPhone/iPad. Compilation requires iOS SDK 26.2+ for supplemental
decoder registration. CI deliberately fails if that SDK is unavailable.
The code registers the decoder at runtime only on the supported OS, checks
`VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9)`, and accepts VP9 profiles
0 and 2. Unsupported devices/content fall back to VLC's software decoders;
no hardware-only global option is forced. This does not add VP9 alpha support.

## Validation

The standalone parser regression covers 8/10-bit profiles, frame sizes, vpcC,
configuration changes, unsupported chroma, corrupt sync and truncated input.
CI compiling/linking the native player is **not** proof of device hardware decode.

Before treating this as supported, test a physical iOS 26.2+ device:

1. Record device model, OS version, source codec/profile/bit depth/resolution.
2. Test ordinary profile 0 and profile 2 samples, seeking, pause/resume,
   app background/foreground, and several minutes of playback.
3. Capture verbose VLC logs to confirm the selected decoder is VideoToolbox,
   not `avcodec`/`vpx`. Confirm actual session hardware usage with
   the included session log below; successful playback or a GPU texture is insufficient.
4. Compare power/CPU and dropped frames with software decoding, and verify
   Unity texture output on the actual app. Check unsupported-device software
   fallback and ordinary H.264/HEVC regression playback too.

No physical-device result is bundled with this experimental package.

## Installation and session-level logging

Use the complete experimental ZIP, not the intermediate LibVLC artifact.
Back up the Unity project first. Remove the old Assets/VLCUnity package before
importing the complete replacement Assets/VLCUnity tree to avoid duplicate
native plugins or LibVLCSharp DLLs. Keep your own scripts outside that directory.
Build for physical iOS ARM64 and install via Xcode; Editor/simulator results do
not establish iPhone hardware support.

In this 2026-3 player enable `logToConsole` (Log To Console) before playback.
Capture Unity Player logs via Xcode's device debug console. The experimental
build additionally queries the active VideoToolbox session after each successful
VP9 session creation, using `VTSessionCopyProperty` and
`kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder`:

- `VP9 VT session hardware=yes status=0`: that session reports hardware decoding.
- `VP9 VT session hardware=no status=0`: that session reports software decoding.
- `VP9 VT session hardware=unknown`: API unavailable, query failed, missing value
  or unexpected type. A zero status with unknown is still NOT proof of hardware.
- No matching line: inconclusive; verify logging and selected decoder. Unsupported
  VP9 devices/content may fall back to `avcodec` or `vpx` without creating a VT session.

Record the latest line after seeking/reconfiguration because sessions can be
recreated. This is a creation-time property snapshot, not continuous per-frame
monitoring. Diagnostic failure does not alter playback or force hardware-only
mode. The mock diagnostic test covers yes/no/unknown, API unavailability,
wrong types, non-VP9 isolation and CF ownership; it does not emulate a real device.
