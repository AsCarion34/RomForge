using Common;
using Common.WPF.ViewModels;
using NSW.Core;
using NSW.Core.Models;
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
using RomForge.Core.Services;

namespace RomForge.ViewModels.Switch;

public class SplitMainViewModel : ToolTabViewModel
{
    private readonly Stopwatch _totalSw = new();
    private CancellationTokenSource? _cts;

    private string _outputPath = string.Empty;

    private static readonly HashSet<string> SupportedExtensions = new(StringComparer.OrdinalIgnoreCase) { ".nsp", ".xci", ".nsz", ".xcz" };

    private readonly List<SplitRow> _files = [];

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    public ObservableCollection<SplitRow> Rows { get; } = [];

    public bool HasFiles => _files.Count > 0;

    private int _progressPct;
    private string _progressLabel = "대기 중...";
    private string _progressPercent = string.Empty;
    private string _progressTime = "00:00 경과";
    private string _progressSpeed = string.Empty;
    private SwitchOutputFormat _outputFormat = SwitchOutputFormat.NSP;
    private bool? _allSelected = false;

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

    public bool? AllSelected
    {
        get => _allSelected;
        set
        {
            if (_allSelected != value)
            {
                _allSelected = value;
                OnPropertyChanged();
            }
        }
    }

    public ICommand OpenWorkSpaceCommand { get; }

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

    public async Task AddFilesAsync(IEnumerable<string> paths)
    {
        var candidates = await Task.Run(() => paths.Where(p => SupportedExtensions.Contains(Path.GetExtension(p))).ToList());
        var added = new List<SplitRow>();
        bool hasKey = KeySetProvider.Instance.KeySet != null;

        foreach (var path in candidates)
        {
            if (_files.Any(f => string.Equals(f.FilePath, path, StringComparison.OrdinalIgnoreCase)))
                continue;

            var row = new SplitRow(path)
            {
                SizeBytes = GetFileLength(path),
                TypeText = hasKey ? Res.Status_Analyzing : Res.Status_NoKey
            };

            _files.Add(row);
            Rows.Add(row);
            added.Add(row);
        }

        OnPropertyChanged(nameof(HasFiles));

        foreach (var row in added)
        {
            if (_files.Contains(row))
                await AnalyzeAsync(row);
        }
    }

    private static long GetFileLength(string path)
    {
        try
        {
            return new FileInfo(path).Length;
        }
        catch
        {
            return 0;
        }
    }

    private static string TitleOf(MetadataResult meta) => !string.IsNullOrWhiteSpace(meta.KrTitle) ? meta.KrTitle : !string.IsNullOrWhiteSpace(meta.EnTitle) ? meta.EnTitle : string.Empty;

    private static string Letter(string tag) => tag switch
    {
        "Base" => "B",
        "Update" => "U",
        "DLC" => "D",
        _ => "?"
    };

    private static int TypeOrder(string tag) => tag switch
    {
        "Base" => 0,
        "Update" => 1,
        _ => 2
    };

    private static async Task AnalyzeAsync(SplitRow row)
    {
        var keySet = KeySetProvider.Instance.KeySet;

        if (keySet == null)
        {
            row.TypeText = Res.Status_NoKey;
            return;
        }

        row.TypeText = Res.Status_Analyzing;

        var metas = await Task.Run(() =>
        {
            try
            {
                return MetadataReader.GetMetadataFromContainer(keySet.Clone(), row.FilePath, true);
            }
            catch
            {
                return null;
            }
        });

        if (metas == null || metas.Count == 0)
        {
            row.TypeText = "?";
            return;
        }

        var ordered = metas.OrderBy(m => TypeOrder(m.GetTypeTag())).ThenBy(m => m.TitleId, StringComparer.OrdinalIgnoreCase).ToList();
        var main = ordered[0];
        string mainName = TitleOf(main);

        if (!string.IsNullOrEmpty(mainName))
            row.Name = mainName;

        row.Icon = ordered.FirstOrDefault(m => m.IconData != null)?.IconData?.ToBitmapImage();
        row.TitleId = main.TitleId;
        row.Version = main.GetEffectiveDisplayVersion();
        row.TypeText = string.Join("+", ordered.Select(m => Letter(m.GetTypeTag())).Distinct());

        row.Children.Clear();

        if (ordered.Count > 1)
        {
            foreach (var meta in ordered)
            {
                string childName = TitleOf(meta);

                row.Children.Add(new SplitRow(row.FilePath, row)
                {
                    Name = string.IsNullOrEmpty(childName) ? row.Name : childName,
                    TitleId = meta.TitleId,
                    TypeText = Letter(meta.GetTypeTag()),
                    Version = meta.GetEffectiveDisplayVersion(),
                    SizeBytes = meta.Size,
                });
            }
        }

        row.Analyzed = true;
        row.NotifyStructureChanged();
    }

    public void ToggleExpand(SplitRow row)
    {
        if (!row.CanExpand)
            return;

        int index = Rows.IndexOf(row);

        if (index < 0)
            return;

        if (row.IsExpanded)
        {
            foreach (var child in row.Children)
                Rows.Remove(child);

            row.IsExpanded = false;
            return;
        }

        for (int i = 0; i < row.Children.Count; i++)
            Rows.Insert(index + 1 + i, row.Children[i]);

        row.IsExpanded = true;
    }

    public void RemoveRows(IEnumerable<SplitRow> selected)
    {
        var parents = selected.Select(r => r.Parent ?? r).Distinct().ToList();

        foreach (var parent in parents)
        {
            foreach (var child in parent.Children)
                Rows.Remove(child);

            Rows.Remove(parent);
            _files.Remove(parent);
        }

        OnPropertyChanged(nameof(HasFiles));
    }

    public void ClearAll()
    {
        Rows.Clear();
        _files.Clear();
        OnPropertyChanged(nameof(HasFiles));
    }

    public void SelectAll(bool isChecked)
    {
        foreach (var file in _files)
            file.SetAll(isChecked);
    }

    public void SelectExceptBase()
    {
        foreach (var file in _files)
            file.SetExceptBase();
    }

    public async Task SplitAsync()
    {
        foreach (var row in _files.Where(f => !f.Analyzed).ToList())
        {
            await AnalyzeAsync(row);

            if (!row.Analyzed)
                Log($"{row.Name}: 타이틀 정보를 읽지 못해 건너뜁니다.", LogLevel.Error);
        }

        var jobs = new List<(string FilePath, IReadOnlySet<string> TitleIds)>();

        foreach (var file in _files.Where(f => f.Analyzed))
        {
            var ids = file.GetSelectedTitleIds();

            if (ids.Count > 0)
                jobs.Add((file.FilePath, ids));
        }

        if (jobs.Count == 0)
        {
            Log("분리할 타이틀을 선택하세요.", LogLevel.Error);
            return;
        }

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

                int resultCount = 0;
                var progress = BuildProgressReporter();                
                var config = AppConfig.Instance.Switch;                
                bool compress = OutputFormat is SwitchOutputFormat.NSZ or SwitchOutputFormat.XCZ;
                bool asXci = OutputFormat is SwitchOutputFormat.XCI or SwitchOutputFormat.XCZ;
                int compressLevel = compress ? 18 : 0;

                for (int i = 0; i < jobs.Count; i++)
                {
                    _cts.Token.ThrowIfCancellationRequested();
                    resultCount += await SwitchSplitService.Split(jobs[i].FilePath, outputDir, compressLevel, true, config.VerifyCompress, config.ForceKeyGen0, asXci, i + 1, jobs.Count, progress, Log, jobs[i].TitleIds, _cts.Token);
                }

                Log(string.Format(Res.Main_Log_AllComplete, _totalSw.Elapsed.ToString(@"mm\:ss")), LogLevel.Ok);

                if (resultCount > 0)
                {
                    Log(Res.Main_Msg_SplitDone);
                    AppConfig.Instance.OutputFolders.SwitchSplitOutputPath?.OpenFolder();
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
}