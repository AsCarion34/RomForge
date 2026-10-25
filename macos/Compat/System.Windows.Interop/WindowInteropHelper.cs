namespace System.Windows.Interop;

/// <summary>
/// WPF WindowInteropHelper 대체. 엔진에는 Win32 창이 없으므로 창 핸들은 항상 0이다.
/// 창 핸들을 받아 Win32 API를 부르는 upstream 코드(작업 표시줄 깜빡임 등)는 핸들이 0이면 그냥 돌아간다.
/// </summary>
public sealed class WindowInteropHelper(Window? window)
{
    public IntPtr Handle => IntPtr.Zero;

    public IntPtr Owner { get; set; }

    public Window? Window => window;

    public IntPtr EnsureHandle() => IntPtr.Zero;
}
