# Experimental iOS VP9 hardware decoding

This is an opt-in backport, not a device-verified production claim. Run the
Build iOS workflow with `experimental_vp9_videotoolbox=true`. Normal releases
and all other platforms are unchanged. The experimental ZIP/artifacts are
explicitly named `experimental-vp9`.

## Provenance and limits

The patch is unchanged upstream VLC commit
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
   `VTSessionCopyProperty` and
   `kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder` in an
   instrumented native build; successful playback or a GPU texture is insufficient.
4. Compare power/CPU and dropped frames with software decoding, and verify
   Unity texture output on the actual app. Check unsupported-device software
   fallback and ordinary H.264/HEVC regression playback too.

No physical-device result is bundled with this experimental package.
