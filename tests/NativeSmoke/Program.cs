using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using LibVLCSharp;

// Windows native ABI smoke test. Uses the actual Unity binding for instance,
// media creation and async parsing. A raw native player avoids calling Unity's
// graphics bridge without an initialized IUnityGraphics host.
var root = Path.GetFullPath(args[0]);
var dir = Path.Combine(root, "Plugins");
Environment.SetEnvironmentVariable("PATH", dir + ";" + Environment.GetEnvironmentVariable("PATH"));
Environment.SetEnvironmentVariable("VLC_PLUGIN_PATH", Path.Combine(dir, "plugins"));
NativeLibrary.Load(Path.Combine(dir, "libvlccore.dll"));
var vlcHandle = NativeLibrary.Load(Path.Combine(dir, "libvlc.dll"));
var bridge = NativeLibrary.Load(Path.Combine(dir, "VLCUnityPlugin.dll"));
IntPtr Resolve(string name, Assembly asm, DllImportSearchPath? path) =>
    name.Contains("VLCUnityPlugin") ? bridge : name.Contains("libvlc") ? vlcHandle : IntPtr.Zero;
NativeLibrary.SetDllImportResolver(typeof(LibVLC).Assembly, Resolve);
NativeLibrary.SetDllImportResolver(Assembly.GetExecutingAssembly(), Resolve);
Core.Initialize(root); // exercise the binding's Unity initialization in a player-style layout
Native.SetPluginPath(Path.Combine(dir, "plugins"));
foreach (var entry in new[] { "libvlc_unity_media_player_new", "libvlc_unity_media_player_release", "libvlc_unity_get_texture" })
    if (!NativeLibrary.TryGetExport(bridge, entry, out _)) throw new Exception("Missing bridge export " + entry);
// libvlc_add_intf is a removed VLC UI API, not used by the Unity integration.
Console.WriteLine("AddInterface native availability: " + NativeLibrary.TryGetExport(vlcHandle, "libvlc_add_intf", out _));

var wav = Path.Combine(Path.GetTempPath(), "vlc-smoke-" + Guid.NewGuid() + ".wav");
try
{
    using (var w = new BinaryWriter(File.Create(wav)))
    {
        int bytes = 48000 * 2 * 3;
        w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + bytes);
        w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); w.Write(16);
        w.Write((short)1); w.Write((short)1); w.Write(48000); w.Write(96000);
        w.Write((short)2); w.Write((short)16);
        w.Write(System.Text.Encoding.ASCII.GetBytes("data")); w.Write(bytes); w.Write(new byte[bytes]);
    }
    using var vlc = new LibVLC("--no-video", "--aout=dummy");
    Console.WriteLine("Native version: " + vlc.Version);
    using var media = new Media(new Uri(wav));
    var parsed = await media.ParseAsync(vlc, MediaParseOptions.ParseLocal, 10000).WaitAsync(TimeSpan.FromSeconds(20));
    if (parsed != MediaParsedStatus.Done) throw new Exception("ParseAsync: " + parsed);
    if (media.Duration < 2900 || media.Duration > 3100) throw new Exception("Duration/time-base mismatch: " + media.Duration);
    Console.WriteLine("PASS: actual Unity binding Media.ParseAsync; duration=" + media.Duration + " ms");
    var player = Native.libvlc_media_player_new(vlc.NativeReference);
    if (player == IntPtr.Zero) throw new Exception("native player creation failed");
    try
    {
        Native.libvlc_media_player_set_media(player, media.NativeReference);
        if (Native.libvlc_media_player_play(player) != 0) throw new Exception("native play failed");
        bool advanced = false;
        for (int i = 0; i < 100; i++)
        {
            await Task.Delay(50);
            var state = Native.libvlc_media_player_get_state(player);
            var time = Native.libvlc_media_player_get_time(player);
            if (state == (int)VLCState.Error) throw new Exception("native playback error");
            if (state == (int)VLCState.Playing && time > 100 && time < 3000) { advanced = true; break; }
        }
        if (!advanced) throw new Exception("playback did not reach Playing with advancing millisecond time");
        if (Native.libvlc_media_player_stop_async(player) != 0) throw new Exception("stop failed");
        for (int i = 0; i < 100 && Native.libvlc_media_player_get_state(player) != (int)VLCState.Stopped; i++) await Task.Delay(50);
        if (Native.libvlc_media_player_get_state(player) != (int)VLCState.Stopped) throw new Exception("stop did not complete");
        Console.WriteLine("PASS: native WAV play, Playing=3, advancing ms time, async Stop and Stopped=5");
    }
    finally { Native.libvlc_media_player_release(player); }
}
finally { File.Delete(wav); }
Console.WriteLine("NOT TESTED: Unity graphics initialization, textures, audio-device output, IL2CPP, Quest");

static class Native
{
    [DllImport("VLCUnityPlugin", CallingConvention=CallingConvention.Cdecl)] public static extern void SetPluginPath(string path);
    [DllImport("libvlc", CallingConvention=CallingConvention.Cdecl)] public static extern IntPtr libvlc_media_player_new(IntPtr vlc);
    [DllImport("libvlc", CallingConvention=CallingConvention.Cdecl)] public static extern void libvlc_media_player_set_media(IntPtr player, IntPtr media);
    [DllImport("libvlc", CallingConvention=CallingConvention.Cdecl)] public static extern int libvlc_media_player_play(IntPtr player);
    [DllImport("libvlc", CallingConvention=CallingConvention.Cdecl)] public static extern int libvlc_media_player_get_state(IntPtr player);
    [DllImport("libvlc", CallingConvention=CallingConvention.Cdecl)] public static extern long libvlc_media_player_get_time(IntPtr player);
    [DllImport("libvlc", CallingConvention=CallingConvention.Cdecl)] public static extern int libvlc_media_player_stop_async(IntPtr player);
    [DllImport("libvlc", CallingConvention=CallingConvention.Cdecl)] public static extern void libvlc_media_player_release(IntPtr player);
}
