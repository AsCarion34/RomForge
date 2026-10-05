using System.Windows;

namespace RomForge.Mac.Engine;

/// <summary>
/// macOS 빌드의 진입점. upstream WPF 앱의 App.xaml 대신 화면 없이 ViewModel 트리를 띄우고,
/// stdio로 SwiftUI 앱과 통신한다.
/// </summary>
public static class Program
{
    public static int Main(string[] args)
    {
        NativeLibraries.Register();

        var app = new Application();
        app.Dispatcher.UnhandledException += (_, ex) => Log.Error($"UI 스레드 예외: {ex}");

        if (args.Contains("--selftest"))
            return SelfTest.Run(app);

        if (args.Contains("--test-7z"))
            return Diagnostics.Test7z(args);

        if (args.Contains("--test-disks"))
            return Diagnostics.TestDisks();

        if (args.Contains("--dump-schema"))
            return SchemaDump.Run(app, args);

        return BridgeHost.Run(app);
    }
}

internal static class Log
{
    // stdout은 SwiftUI 앱과의 통신 전용이라 로그는 stderr로 보낸다.
    public static void Info(string message) => Console.Error.WriteLine($"[engine] {message}");

    public static void Error(string message) => Console.Error.WriteLine($"[engine:error] {message}");
}
