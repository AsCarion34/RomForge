using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;

namespace RomForge.Mac.Engine;

/// <summary>
/// upstream의 Windows DLL 이름을 macOS dylib로 연결한다. upstream 코드의 DllImport는 그대로 둔다.
/// </summary>
internal static class NativeLibraries
{
    private static readonly Dictionary<string, string> Map = new(StringComparer.OrdinalIgnoreCase)
    {
        ["chdman.dll"] = "libchdman.dylib",
        ["chdr.dll"] = "libchdr.dylib",
        ["xdelta3"] = "libxdelta3.dylib",
        ["xdelta3.dll"] = "libxdelta3.dylib",
        // macOS에서도 의미 있는 kernel32 함수(SetThreadExecutionState 등)만 구현한 shim
        ["kernel32.dll"] = "libromforge_win32shim.dylib",
        ["kernel32"] = "libromforge_win32shim.dylib",
        // PickPack.Disk의 macOS 구현(macos/Overrides/PickPack.Disk/MacDisk.cs)
        ["libromforge_macdisk"] = "libromforge_macdisk.dylib",
    };

    public static void Register() => AssemblyLoadContext.Default.ResolvingUnmanagedDll += Resolve;

    private static IntPtr Resolve(Assembly assembly, string name)
    {
        if (!Map.TryGetValue(name, out var fileName))
            return IntPtr.Zero;

        foreach (var dir in new[] { AppContext.BaseDirectory, Path.Combine(AppContext.BaseDirectory, "native") })
        {
            string path = Path.Combine(dir, fileName);

            if (File.Exists(path) && NativeLibrary.TryLoad(path, out var handle))
                return handle;
        }

        Log.Error($"네이티브 라이브러리를 찾지 못했습니다: {name} → {fileName}");
        return IntPtr.Zero;
    }
}
