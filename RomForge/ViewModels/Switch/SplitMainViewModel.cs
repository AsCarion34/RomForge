using Common;
using Common.WPF.ViewModels;
using NSW.Core;
using NSW.WPF.Services;
using RomForge.Core;
using RomForge.Core.Models;
using RomForge.Core.Models.Switch;
using RomForge.Core.Services.Switch;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Input;
using Res = NSW.Core.Properties.Resources;
using RomForge.Core.UI.Command;
using NSW.WPF.ViewModels;
using RomForge.Core.Services;

namespace RomForge.ViewModels.Switch;

public class SplitMainViewModel : ToolTabViewModel
{
    private readonly Stopwatch _totalSw = new();
    private CancellationTokenSource? _cts;

    private string _outputPath = string.Empty;

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    private int _progressPct;
    private string _progressLabel = "대기 중...";
    private string _progressPercent = string.Empty;
    private string _progressTime = "00:00 경과";
    private string _progressSpeed = string.Empty;
    private SwitchOutputFormat _outputFormat = SwitchOutputFormat.NSP;

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

    public string OutputPath
    {
        get => _outputPath;
        set
        {
            _outputPath = value;
            OnPropertyChanged();
            AppConfig.Instance.OutputFolders.SwitchSplitOutputPath = value;
        }
    }

    public SwitchOutputFormat OutputFormat
    {
        get => _outputFormat;
        set { _outputFormat = value; OnPropertyChanged(); }
    }

    public ICommand OpenWorkSpaceCommand { get; }

    public event EventHandler SettingsClicked;

    public SplitMainViewModel()
    {
        var folders = AppConfig.Instance.OutputFolders;

        if (!string.IsNullOrWhiteSpace(folders.SwitchSplitOutputPath))
            OutputPath = folders.SwitchSplitOutputPath;
        else if (!string.IsNullOrWhiteSpace(folders.SwitchMergeOutputPath))
            OutputPath = folders.SwitchMergeOutputPath;
        else
            OutputPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "output");

        OpenWorkSpaceCommand = new RelayCommand(_ => ExecuteOpenWorkSpace());
    }

    public async Task SplitAsync(IList<GameFile> gameFiles)
    {
        string outputDir = OutputPath?.Trim() ?? string.Empty;

        if (string.IsNullOrEmpty(outputDir))
        {
            Log(Res.Main_Err_NoOutput, LogLevel.Error);
            return;
        }

        if (!Directory.Exists(outputDir))
            Directory.CreateDirectory(outputDir);

        _totalSw.Restart();
        using (BeginWork())
        {
            try
            {
                _cts = new CancellationTokenSource();
                var progress = BuildProgressReporter();

                var config = AppConfig.Instance.Switch;
                int compressLevel = config.CompressLevel < 3 ? 0 : config.CompressLevel;
                int resultCount = 0;

                for (int i = 0; i < gameFiles.Count; i++)
                {
                    _cts.Token.ThrowIfCancellationRequested();
                    resultCount += await SwitchSplitService.Split(gameFiles[i].FilePath, outputDir, compressLevel, config.UseBlockMode, config.VerifyCompress, config.ForceKeyGen0, OutputFormat == SwitchOutputFormat.XCI, i + 1, gameFiles.Count, progress, Log, _cts.Token);
                }

                Log(string.Format(Res.Main_Log_AllComplete, _totalSw.Elapsed.ToString(@"mm\:ss")), LogLevel.Ok);

                if (resultCount > 0)
                {
                    Log(Res.Main_Msg_SplitDone);
                    await SoundPlayer.PlayCompleteAsync();
                }
            }
            catch (OperationCanceledException)
            {
                Log("분리가 취소되었습니다.", LogLevel.Error);
                await SoundPlayer.PlayCancelAsync();
            }
            catch (Exception ex)
            {
                Log($"{Res.Log_Error}: {ex.Message}", LogLevel.Error);
                await SoundPlayer.PlayErrorAsync();
            }
            finally
            {
                _cts?.Dispose();
                _cts = null;
                ProgressPct = 0;
            }
        }
    }

    public void Cancel() => _cts?.Cancel();

    private Progress<ProgressInfo> BuildProgressReporter() =>
        new(info => Application.Current.Dispatcher.BeginInvoke(() =>
        {
            ProgressPct = info.Percent;
            ProgressLabel = info.Label;
            ProgressPercent = $"{info.Percent}%";
            ProgressTime = info.TimeInfo;
            ProgressSpeed = info.Speed;
        }));

    private void ExecuteOpenWorkSpace()
    {
        var path = OutputPath?.Trim();

        if (string.IsNullOrEmpty(path) || !Directory.Exists(path))
            return;

        path.OpenFolder();
    }

    public void Log(string msg, LogLevel level = LogLevel.Info, string titleId = "") => Application.Current.Dispatcher.Invoke(() => LogEntries.Add(new LogEntry { Message = msg, Level = level }));

    public void NavigateSettings() => SettingsClicked?.Invoke(this, EventArgs.Empty);
}
