using Common;
using Common.WPF.ViewModels;
using RomForge.Core.Models;
using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;

namespace RomForge.ViewModels;

public abstract class ToolTabViewModel : ViewModelBase
{
    private int _lockCount;
    private readonly List<ToolTabViewModel> _tools = [];    

    private int _progressPct;
    public int ProgressPct
    {
        get => _progressPct;
        set
        {
            _progressPct = value;

            MainViewModel.SetTaskbarProgress(_progressPct);
            OnPropertyChanged();
        }
    }

    private string _progressLabel = "대기 중...";
    public string ProgressLabel
    {
        get => _progressLabel;
        set { _progressLabel = value; OnPropertyChanged(); }
    }

    private string _progressPercent = string.Empty;
    public string ProgressPercent
    {
        get => _progressPercent;
        set { _progressPercent = value; OnPropertyChanged(); }
    }

    private string _progressTime = "00:00 경과";
    public string ProgressTime
    {
        get => _progressTime;
        set { _progressTime = value; OnPropertyChanged(); }
    }

    private string _progressSpeed = string.Empty;
    public string ProgressSpeed
    {
        get => _progressSpeed;
        set { _progressSpeed = value; OnPropertyChanged(); }
    }


    public bool IsLocked => _lockCount > 0;

    public bool IsUnlocked => _lockCount == 0;

    public bool IsIdle => !IsLocked && Tools.All(c => c.IsIdle);

    public List<ToolTabViewModel> Tools => _tools;

    public ICommand? CancelCommand { set;  get; }

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    protected CancellationTokenSource? CancellationTokenSource { get; set; }

    protected void RegisterChild(ToolTabViewModel child)
    {
        child.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(IsLocked) or nameof(IsIdle))
                OnPropertyChanged(nameof(IsIdle));
        };
    }

    public IDisposable BeginWork()
    {
        Interlocked.Increment(ref _lockCount);
        OnPropertyChanged(nameof(IsLocked));
        OnPropertyChanged(nameof(IsUnlocked));
        OnPropertyChanged(nameof(IsIdle));
        CommandManager.InvalidateRequerySuggested();

        return new ActionDisposable(() =>
        {
            Interlocked.Decrement(ref _lockCount);
            OnPropertyChanged(nameof(IsLocked));
            OnPropertyChanged(nameof(IsUnlocked));
            OnPropertyChanged(nameof(IsIdle));
            CommandManager.InvalidateRequerySuggested();
        });
    }

    protected Progress<ProgressInfo> BuildProgressReporter() =>
        new(info =>
        {
            ProgressPct = info.Percent;
            ProgressLabel = info.Label;
            ProgressPercent = $"{info.Percent}%";
            ProgressTime = info.TimeInfo;
            ProgressSpeed = info.Speed;
        });

    protected void CleanupTask()
    {
        CancellationTokenSource?.Dispose();
        CancellationTokenSource = null;
        ProgressPct = 0;
        ProgressLabel = string.Empty;
        ProgressPercent = "0%";
        ProgressTime = string.Empty;
        ProgressSpeed = string.Empty;
    }

    public void CancelAll()
    {
        foreach (var child in Tools)
        {
            if (child.IsLocked && child.CancelCommand?.CanExecute(null) == true)
                child.CancelCommand.Execute(null);

            if (child.Tools != null)
                child.CancelAll();
        }
    }

    public virtual void Cancel() => CancellationTokenSource?.Cancel();

    public void AppendLog(string msg, LogLevel level = LogLevel.Info) => Application.Current?.Dispatcher?.Invoke(() => LogEntries.Add(new LogEntry { Message = msg, Level = level }));

    public virtual void ClearLog() => Application.Current?.Dispatcher?.Invoke(() => LogEntries.Clear());

    private sealed class ActionDisposable(Action action) : IDisposable
    {
        public void Dispose() => action();
    }
}