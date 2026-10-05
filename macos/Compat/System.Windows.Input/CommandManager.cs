using System.Windows.Threading;

namespace System.Windows.Input;

/// <summary>
/// WPF CommandManager 대체. WPF처럼 구독자를 약한 참조로 들고 있다가,
/// InvalidateRequerySuggested가 불리면 UI 스레드에서 한 번에 모아 알린다.
/// </summary>
public static class CommandManager
{
    private static readonly List<WeakReference<EventHandler>> Handlers = [];
    private static int _pending;

    public static event EventHandler RequerySuggested
    {
        add
        {
            lock (Handlers)
                Handlers.Add(new WeakReference<EventHandler>(value));
        }
        remove
        {
            lock (Handlers)
                Handlers.RemoveAll(w => !w.TryGetTarget(out var h) || h == value);
        }
    }

    public static void InvalidateRequerySuggested()
    {
        if (Interlocked.Exchange(ref _pending, 1) == 1)
            return;

        var dispatcher = Application.Current?.Dispatcher;

        if (dispatcher == null)
        {
            _pending = 0;
            Raise();
            return;
        }

        dispatcher.InvokeAsync(() =>
        {
            Interlocked.Exchange(ref _pending, 0);
            Raise();
        }, DispatcherPriority.Background);
    }

    private static void Raise()
    {
        List<EventHandler> alive = [];

        lock (Handlers)
        {
            Handlers.RemoveAll(w => !w.TryGetTarget(out _));

            foreach (var w in Handlers)
            {
                if (w.TryGetTarget(out var h))
                    alive.Add(h);
            }
        }

        foreach (var h in alive)
            h(null, EventArgs.Empty);
    }
}
