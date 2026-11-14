using System;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using LibVLCSharp;

// Exact libvlc_state_t values in the pinned native e7a30c9 headers.
var states = new[] { VLCState.NothingSpecial, VLCState.Opening, VLCState.Buffering,
    VLCState.Playing, VLCState.Paused, VLCState.Stopped, VLCState.Stopping, VLCState.Error };
for (int i = 0; i < states.Length; i++)
    if ((int)states[i] != i) throw new Exception($"Native state ABI mismatch: {states[i]} != {i}");

// Catch the post-June parser migration even if someone restores only the enum.
var imports = typeof(Media).Assembly.GetTypes().SelectMany(t =>
    t.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
    .Select(m => m.GetCustomAttribute<DllImportAttribute>()?.EntryPoint)
    .Where(n => n != null).ToHashSet();
if (!imports.Contains("libvlc_media_parse_request"))
    throw new Exception("Expected the parser API of the pinned June 2026 native engine");
if (imports.Contains("libvlc_parser_new"))
    throw new Exception("New parser API cannot be used with the pinned June 2026 engine");
Console.WriteLine("PASS: VLCState numeric ABI and pinned native parser API contract");
