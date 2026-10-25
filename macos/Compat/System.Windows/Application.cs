using System.Windows.Threading;
using RomForge.Mac.Compat;

namespace System.Windows;

public class Application
{
    public static Application Current { get; private set; } = null!;

    public Application()
    {
        RegisterPackScheme();
        Current = this;
        Dispatcher = new Dispatcher("RomForge UI");
    }

    // WPF(WindowsBase PackUriHelper)는 시작할 때 "pack" 스킴을 등록한다. 없으면 pack://application:,,,/ 주소가 깨진다.
    internal static void RegisterPackScheme()
    {
        if (!UriParser.IsKnownScheme("pack"))
            UriParser.Register(new GenericUriParser(GenericUriParserOptions.GenericAuthority), "pack", -1);
    }

    public Dispatcher Dispatcher { get; }

    public Window? MainWindow { get; set; }

    public event EventHandler? ShutdownRequested;

    public void Shutdown() => Shutdown(0);

    public void Shutdown(int exitCode) => ShutdownRequested?.Invoke(this, EventArgs.Empty);
}

public class Window
{
    public string? Title { get; set; }

    public Window? Owner { get; set; }

    public bool? DialogResult { get; set; }

    public Visibility Visibility { get; set; }

    /// <summary>엔진에는 실제 창이 없어 항상 false다.</summary>
    public bool IsActive => false;

    public void Close() { }
}

public abstract class Freezable
{
    public bool IsFrozen { get; private set; }

    public bool CanFreeze => true;

    public void Freeze() => IsFrozen = true;
}

public enum Visibility
{
    Visible = 0,
    Hidden = 1,
    Collapsed = 2,
}

public enum MessageBoxButton
{
    OK = 0,
    OKCancel = 1,
    YesNoCancel = 3,
    YesNo = 4,
}

public enum MessageBoxImage
{
    None = 0,
    Hand = 16,
    Stop = 16,
    Error = 16,
    Question = 32,
    Exclamation = 48,
    Warning = 48,
    Asterisk = 64,
    Information = 64,
}

public enum MessageBoxResult
{
    None = 0,
    OK = 1,
    Cancel = 2,
    Yes = 6,
    No = 7,
}

public static class MessageBox
{
    public static MessageBoxResult Show(string messageBoxText) =>
        Show(messageBoxText, string.Empty, MessageBoxButton.OK, MessageBoxImage.None);

    public static MessageBoxResult Show(string messageBoxText, string caption) =>
        Show(messageBoxText, caption, MessageBoxButton.OK, MessageBoxImage.None);

    public static MessageBoxResult Show(string messageBoxText, string caption, MessageBoxButton button) =>
        Show(messageBoxText, caption, button, MessageBoxImage.None);

    public static MessageBoxResult Show(string messageBoxText, string caption, MessageBoxButton button, MessageBoxImage icon)
    {
        var host = UiHost.Current;

        if (host == null)
            return button is MessageBoxButton.OK or MessageBoxButton.OKCancel ? MessageBoxResult.OK : MessageBoxResult.Yes;

        return host.ShowMessageBox(messageBoxText, caption, button, icon);
    }

    public static MessageBoxResult Show(string messageBoxText, string caption, MessageBoxButton button, MessageBoxImage icon, MessageBoxResult defaultResult) =>
        Show(messageBoxText, caption, button, icon);

    public static MessageBoxResult Show(Window? owner, string messageBoxText) =>
        Show(messageBoxText);

    public static MessageBoxResult Show(Window? owner, string messageBoxText, string caption) =>
        Show(messageBoxText, caption);

    public static MessageBoxResult Show(Window? owner, string messageBoxText, string caption, MessageBoxButton button) =>
        Show(messageBoxText, caption, button);

    public static MessageBoxResult Show(Window? owner, string messageBoxText, string caption, MessageBoxButton button, MessageBoxImage icon) =>
        Show(messageBoxText, caption, button, icon);
}
