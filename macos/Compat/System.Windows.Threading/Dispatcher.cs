using System.Collections.Concurrent;
using System.Runtime.CompilerServices;

namespace System.Windows.Threading;

public enum DispatcherPriority
{
    Invalid = -1,
    Inactive = 0,
    SystemIdle = 1,
    ApplicationIdle = 2,
    ContextIdle = 3,
    Background = 4,
    Input = 5,
    Loaded = 6,
    Render = 7,
    DataBind = 8,
    Normal = 9,
    Send = 10,
}

public enum DispatcherOperationStatus
{
    Pending = 0,
    Aborted = 1,
    Completed = 2,
    Executing = 3,
}

/// <summary>
/// WPF Dispatcher를 흉내 내는 단일 스레드 작업 루프.
/// ViewModel은 WPF처럼 이 스레드에서만 컬렉션·속성을 바꾸고, await 이후에도 이 스레드로 돌아온다.
/// 우선순위는 구분하지 않고 들어온 순서대로 처리한다.
/// </summary>
public sealed class Dispatcher
{
    private readonly BlockingCollection<Action> _queue = new();
    private readonly Thread _thread;

    public Dispatcher(string name)
    {
        var started = new ManualResetEventSlim();

        _thread = new Thread(() =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(this));
            started.Set();
            Run();
        })
        {
            IsBackground = true,
            Name = name,
        };

        _thread.Start();
        started.Wait();
    }

    /// <summary>작업 중 처리되지 않은 예외. 루프는 멈추지 않는다.</summary>
    public event EventHandler<Exception>? UnhandledException;

    public Thread Thread => _thread;

    public static Dispatcher CurrentDispatcher => Application.Current.Dispatcher;

    public bool CheckAccess() => Thread.CurrentThread == _thread;

    public void VerifyAccess()
    {
        if (!CheckAccess())
            throw new InvalidOperationException("UI 스레드가 아닌 곳에서 호출했습니다.");
    }

    private void Run()
    {
        foreach (var work in _queue.GetConsumingEnumerable())
            Execute(work);
    }

    private void Execute(Action work)
    {
        try
        {
            work();
        }
        catch (Exception ex)
        {
            UnhandledException?.Invoke(this, ex);
        }
    }

    internal void Post(Action work) => _queue.Add(work);

    /// <summary>
    /// 조건이 끝날 때까지 UI 스레드에서 다른 작업을 계속 처리한다.
    /// 모달 대화상자 응답을 기다리는 동안 백그라운드의 Invoke가 막히지 않게 한다.
    /// </summary>
    public static void PushFrame(DispatcherFrame frame)
    {
        var dispatcher = CurrentDispatcher;
        dispatcher.VerifyAccess();

        while (frame.Continue)
        {
            if (dispatcher._queue.TryTake(out var work, 15))
                dispatcher.Execute(work);
        }
    }

    public void Invoke(Action callback) => Invoke(callback, DispatcherPriority.Send);

    public void Invoke(Action callback, DispatcherPriority priority)
    {
        if (CheckAccess())
        {
            callback();
            return;
        }

        var op = new DispatcherOperation();
        Post(() => op.Run(() => { callback(); return null; }));
        op.Task.GetAwaiter().GetResult();
    }

    public TResult Invoke<TResult>(Func<TResult> callback) => Invoke(callback, DispatcherPriority.Send);

    public TResult Invoke<TResult>(Func<TResult> callback, DispatcherPriority priority)
    {
        if (CheckAccess())
            return callback();

        var op = new DispatcherOperation<TResult>();
        Post(() => op.Run(() => callback()));
        return op.Task.GetAwaiter().GetResult();
    }

    public object? Invoke(Delegate method, params object?[]? args)
    {
        if (CheckAccess())
            return method.DynamicInvoke(args);

        var op = new DispatcherOperation();
        Post(() => op.Run(() => method.DynamicInvoke(args)));
        op.Task.GetAwaiter().GetResult();
        return op.Result;
    }

    public DispatcherOperation InvokeAsync(Action callback) => InvokeAsync(callback, DispatcherPriority.Normal);

    public DispatcherOperation InvokeAsync(Action callback, DispatcherPriority priority)
    {
        var op = new DispatcherOperation();
        Post(() => op.Run(() => { callback(); return null; }, ReportException));
        return op;
    }

    // 결과를 기다리는 쪽이 없는 비동기 작업의 예외는 여기로 알린다(WPF는 UnhandledException으로 올린다).
    private void ReportException(Exception ex) => UnhandledException?.Invoke(this, ex);

    public DispatcherOperation InvokeAsync(Action callback, DispatcherPriority priority, CancellationToken cancellationToken) =>
        InvokeAsync(callback, priority);

    public DispatcherOperation<TResult> InvokeAsync<TResult>(Func<TResult> callback) =>
        InvokeAsync(callback, DispatcherPriority.Normal);

    public DispatcherOperation<TResult> InvokeAsync<TResult>(Func<TResult> callback, DispatcherPriority priority)
    {
        var op = new DispatcherOperation<TResult>();
        Post(() => op.Run(() => callback(), ReportException));
        return op;
    }

    public DispatcherOperation BeginInvoke(Delegate method, params object?[]? args)
    {
        var op = new DispatcherOperation();
        Post(() => op.Run(() => method.DynamicInvoke(args), ReportException));
        return op;
    }

    public DispatcherOperation BeginInvoke(DispatcherPriority priority, Delegate method) => BeginInvoke(method);

    public DispatcherOperation BeginInvoke(DispatcherPriority priority, Delegate method, object? arg) => BeginInvoke(method, arg);

    public DispatcherOperation BeginInvoke(Delegate method, DispatcherPriority priority, params object?[]? args) => BeginInvoke(method, args);
}

public class DispatcherOperation
{
    private protected readonly TaskCompletionSource<object?> Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public DispatcherOperationStatus Status { get; private set; } = DispatcherOperationStatus.Pending;

    public Task Task => Completion.Task;

    public object? Result => Completion.Task.IsCompletedSuccessfully ? Completion.Task.Result : null;

    public TaskAwaiter GetAwaiter() => ((Task)Completion.Task).GetAwaiter();

    public DispatcherOperationStatus Wait()
    {
        Completion.Task.Wait();
        return Status;
    }

    internal void Run(Func<object?> work, Action<Exception>? reportException = null)
    {
        Status = DispatcherOperationStatus.Executing;

        try
        {
            Completion.SetResult(work());
        }
        catch (Exception ex)
        {
            var actual = ex is System.Reflection.TargetInvocationException { InnerException: { } inner } ? inner : ex;
            reportException?.Invoke(actual);
            Completion.SetException(actual);
        }
        finally
        {
            Status = DispatcherOperationStatus.Completed;
        }
    }
}

public sealed class DispatcherOperation<TResult> : DispatcherOperation
{
    private Task<TResult>? _typed;

    // 원래 예외를 그대로 전달하도록(AggregateException으로 감싸지 않도록) async로 변환한다.
    public new Task<TResult> Task => _typed ??= Convert(Completion.Task);

    public new TResult Result => (TResult)base.Result!;

    public new TaskAwaiter<TResult> GetAwaiter() => Task.GetAwaiter();

    private static async Task<TResult> Convert(Task<object?> source) => (TResult)(await source.ConfigureAwait(false))!;
}

public sealed class DispatcherFrame
{
    public bool Continue { get; set; } = true;
}

public sealed class DispatcherSynchronizationContext(Dispatcher dispatcher) : SynchronizationContext
{
    public override void Post(SendOrPostCallback d, object? state) => dispatcher.Post(() => d(state));

    public override void Send(SendOrPostCallback d, object? state) => dispatcher.Invoke(() => d(state));

    public override SynchronizationContext CreateCopy() => this;
}
