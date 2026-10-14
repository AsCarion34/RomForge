using Common;
using Common.WPF.ViewModels;
using RomForge.Core;
using RomForge.Core.Models;
using RomForge.Core.Services.PS;
using RomForge.Core.UI.Command;
using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Input;
using NSW.WPF.Services;
using RomForge.Core.Services;

namespace RomForge.ViewModels.PS;

public class PackingMainViewModel : ToolTabViewModel
{
    private CancellationTokenSource _cts = new();

    private string _gameTitle = string.Empty;
    private int _progressPct;
    private string _progressLabel = string.Empty;
    private string _progressPercent = "0%";
    private string _progressTime = string.Empty;
    private string _progressSpeed = string.Empty;

    public PackingMainViewModel()
    {
        Files = new DiscListViewModel(AppendLog);
        Images = new PackingImagesViewModel();
        Bgm = new BgmViewModel(AppendLog);
        PopsOptions = new PopsOptionsViewModel();

        RunCommand = new RelayCommand(async _ => await RunAsync(), _ => CanRun);
        CancelCommand = new RelayCommand(_ => _cts.Cancel(), _ => IsLocked);
        SettingsCommand = new RelayCommand(async _ => RunNavigateSettings?.Invoke(this, EventArgs.Empty), _ => !IsLocked);

        Files.FileItems.CollectionChanged += (_, _) => OnPropertyChanged(nameof(CanAdd));
        Files.Changed += OnFilesChanged;
        Files.Cleared += OnFilesCleared;

        Images.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName != nameof(PackingImagesViewModel.IsDownloading))
                return;

            OnPropertyChanged(nameof(CanRun));
            Application.Current.Dispatcher.InvokeAsync(CommandManager.InvalidateRequerySuggested);
        };

        PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(IsLocked))
                OnPropertyChanged(nameof(CanAdd));
        };
    }

    public DiscListViewModel Files { get; }

    public PackingImagesViewModel Images { get; }

    public BgmViewModel Bgm { get; }

    public PopsOptionsViewModel PopsOptions { get; }

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    public ICommand RunCommand { get; }

    public ICommand SettingsCommand { get; }

    public event EventHandler RunNavigateSettings;

    public string GameTitle
    {
        get => _gameTitle;
        set { _gameTitle = value; OnPropertyChanged(); }
    }

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

    public string ProgressLabel
    {
        get => _progressLabel;
        set { _progressLabel = value; OnPropertyChanged(); }
    }

    public string ProgressPercent
    {
        get => _progressPercent;
        set { _progressPercent = value; OnPropertyChanged(); }
    }

    public string ProgressTime
    {
        get => _progressTime;
        set { _progressTime = value; OnPropertyChanged(); }
    }

    public string ProgressSpeed
    {
        get => _progressSpeed;
        set { _progressSpeed = value; OnPropertyChanged(); }
    }

    public bool CanEditPopsConfig => IsUnlocked && !Files.HasPresetConfig;

    public bool CanAdd => !IsLocked && Files.FileItems.Count < DiscListViewModel.MaxItems;

    public bool CanRun => !IsLocked && Files.FileItems.Count > 0 && !Images.IsDownloading;

    private void OnFilesChanged(object? sender, EventArgs e)
    {
        _ = UpdateCoverArtAsync();

        OnPropertyChanged(nameof(CanEditPopsConfig));
        CommandManager.InvalidateRequerySuggested();
    }

    private void OnFilesCleared(object? sender, EventArgs e)
    {
        Images.ResetAll();
        Bgm.Reset();

        OnPropertyChanged(nameof(CanEditPopsConfig));
    }

    private async Task UpdateCoverArtAsync()
    {
        var title = await Images.UpdateFromGameIdAsync(Files.Primary?.GameId);

        if (title != null)
            GameTitle = title;
    }

    private async Task RunAsync()
    {
        _cts.Dispose();
        _cts = new CancellationTokenSource();

        if (Files.FileItems.Count == 0)
        {
            AppendLog("추가된 파일이 없습니다.", LogLevel.Error);
            return;
        }

        if (Files.FileItems.Any(i => i.GameId is "인식중..." or "인식실패"))
        {
            AppendLog("GameID 인식 오류", LogLevel.Error);
            return;
        }

        using (BeginWork())
        {
            var orderedItems = Files.FileItems.OrderBy(i => i.No).ToList();
            var gameTitle = string.IsNullOrWhiteSpace(GameTitle) ? DiscListSorter.GuessTitle(orderedItems[0].FilePath) : GameTitle;
            var mainGameId = orderedItems[0].GameId;
            var assets = Images.BuildAssets(Bgm.Bytes);
            var plan = PackingJobRunner.PlanOutput(orderedItems[0].FilePath, gameTitle, mainGameId);
            var popsConfig = PopsOptions.BuildConfig(orderedItems[0].PresetConfigBytes);

            try
            {
                AppendLog($"작업 시작: {gameTitle} [{mainGameId}] ({orderedItems.Count}개 디스크)", LogLevel.Highlight);
                await PackingJobRunner.RunAsync(orderedItems, gameTitle, mainGameId, plan, AppConfig.Instance.PS1.CompressLevel, assets, popsConfig, BuildProgressReporter(), _cts.Token);

                ProgressPct = 100;

                AppendLog($"작업 완료: {plan.TargetOutputPath}", LogLevel.Ok);
                await SoundPlayer.PlayCompleteAsync();
                Path.GetDirectoryName(plan.TargetOutputPath).OpenFolder();
            }
            catch (OperationCanceledException)
            {
                AppendLog("작업이 취소되었습니다.", LogLevel.Error);
                await SoundPlayer.PlayCancelAsync();
                CleanupTask();
                MainViewModel.SetTaskbarProgress(0);
                TryDeleteFileAndFolder(plan.TargetOutputPath, plan.GameDirectory);
            }
            catch (Exception ex)
            {
                AppendLog($"오류: [{gameTitle}] {ex.Message}", LogLevel.Error);
                await SoundPlayer.PlayErrorAsync();
                MainViewModel.SetTaskbarProgress(100, System.Windows.Shell.TaskbarItemProgressState.Error);
                CleanupTask();
                TryDeleteFileAndFolder(plan.TargetOutputPath, plan.GameDirectory);
            }
        }
    }

    private Progress<ProgressInfo> BuildProgressReporter() =>
        new(info =>
        {
            ProgressPct = info.Percent;
            ProgressLabel = info.Label;
            ProgressPercent = $"{info.Percent}%";
            ProgressTime = info.TimeInfo;
            ProgressSpeed = info.Speed;
        });

    private void CleanupTask()
    {
        ProgressLabel = string.Empty;
        ProgressPercent = "0%";
        ProgressTime = string.Empty;
        ProgressSpeed = string.Empty;
    }

    private void TryDeleteFileAndFolder(string? filePath, string? folderPath)
    {
        try
        {
            PackingJobRunner.CleanupFailedOutput(filePath, folderPath);
        }
        catch (Exception ex)
        {
            AppendLog($"취소/실패 정리 작업 중 예외 발생: {ex.Message}", LogLevel.Error);
        }
    }

    private void AppendLog(string msg, LogLevel level = LogLevel.Info)
    {
        if (Application.Current?.Dispatcher == null)
            return;

        Application.Current.Dispatcher.Invoke(() => LogEntries.Add(new LogEntry { Message = msg, Level = level }));
    }
}