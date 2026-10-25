namespace System.Windows.Threading;

/// <summary>
/// WPF DispatcherTimer 대체. Tick은 WPF처럼 Dispatcher 스레드에서 실행되고,
/// 앞 Tick이 끝난 뒤에 다음 Tick을 예약하므로 Tick이 밀려 쌓이지 않는다.
/// </summary>
public class DispatcherTimer
{
    private readonly object _lock = new();
    private readonly Dispatcher? _dispatcher;
    private Timer? _timer;
    private TimeSpan _interval;
    private int _generation;

    public DispatcherTimer() : this(DispatcherPriority.Background)
    {
    }

    public DispatcherTimer(DispatcherPriority priority) => _dispatcher = Application.Current?.Dispatcher;

    public DispatcherTimer(DispatcherPriority priority, Dispatcher dispatcher) => _dispatcher = dispatcher;

    public DispatcherTimer(TimeSpan interval, DispatcherPriority priority, EventHandler callback, Dispatcher dispatcher) : this(priority, dispatcher)
    {
        Interval = interval;
        Tick += callback;
        Start();
    }

    public event EventHandler? Tick;

    /// <summary>ViewModel이 Application보다 먼저 만들어져도 되도록 Start할 때 Dispatcher를 정한다.</summary>
    public Dispatcher Dispatcher => _dispatcher ?? Application.Current.Dispatcher;

    public TimeSpan Interval
    {
        get => _interval;
        set
        {
            if (value < TimeSpan.Zero)
                throw new ArgumentOutOfRangeException(nameof(value));

            lock (_lock)
            {
                _interval = value;

                if (IsEnabled)
                    Arm();
            }
        }
    }

    public bool IsEnabled { get; private set; }

    public object? Tag { get; set; }

    public void Start()
    {
        lock (_lock)
        {
            IsEnabled = true;
            Arm();
        }
    }

    public void Stop()
    {
        lock (_lock)
        {
            IsEnabled = false;
            _generation++;
            _timer?.Dispose();
            _timer = null;
        }
    }

    // 호출하는 쪽이 _lock을 잡고 있어야 한다.
    private void Arm()
    {
        int generation = ++_generation;
        var dispatcher = Dispatcher;

        _timer?.Dispose();
        _timer = new Timer(_ => dispatcher.Post(() => OnTick(generation)), null, _interval, Timeout.InfiniteTimeSpan);
    }

    private void OnTick(int generation)
    {
        lock (_lock)
        {
            if (!IsEnabled || generation != _generation)
                return;
        }

        Tick?.Invoke(this, EventArgs.Empty);

        lock (_lock)
        {
            if (IsEnabled && generation == _generation)
                Arm();
        }
    }
}
