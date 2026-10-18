using Common;
using Common.WPF.ViewModels;
using NSW.Core;
using NSW.Core.Models;
using NSW.Core.Utils;
using NSW.WPF.Services;
using NSW.WPF.ViewModels;
using RomForge.Core.Models;
using RomForge.Core.Models.Patch;
using RomForge.Core.Models.Switch;
using RomForge.Core.Services;
using RomForge.Core.Services.Switch;
using RomForge.Core.UI.Command;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using Res = NSW.Core.Properties.Resources;

namespace RomForge.ViewModels.Switch;

public class RenameMainViewModel : ToolTabViewModel
{
    #region Fields & Properties

    private static readonly HashSet<string> SupportedExtensions = new(StringComparer.OrdinalIgnoreCase) { ".nsp", ".xci", ".nsz", ".xcz" };

    private CancellationTokenSource _cts = new();
    private string _formatText = SwitchRenamePresets.Default.Format!;
    private NamingFormatPreset _selectedNamingPreset = SwitchRenamePresets.Default;
    private string _summary = string.Empty;
    private bool _refreshQueued;

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    public ObservableCollection<RenameFileItem> Items { get; } = [];

    public static IReadOnlyList<NamingFormatPreset> NamingPresets => SwitchRenamePresets.All;

    public Visibility HintVisibility => Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    public ICommand RunCommand { get; }

    public NamingFormatPreset SelectedNamingPreset
    {
        get => _selectedNamingPreset;
        set
        {
            if (value is null || value.IsSeparator || ReferenceEquals(_selectedNamingPreset, value))
                return;

            _selectedNamingPreset = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsFormatReadOnly));

            if (!value.IsCustom)
                FormatText = value.Format!;
        }
    }

    public bool IsFormatReadOnly => !_selectedNamingPreset.IsCustom;

    public string FormatText
    {
        get => _formatText;
        set
        {
            if (SetProperty(ref _formatText, value))
                ScheduleRefresh();
        }
    }

    public string Summary
    {
        get => _summary;
        private set => SetProperty(ref _summary, value);
    }

    #endregion

    #region Constructor

    public RenameMainViewModel()
    {
        RunCommand = new RelayCommand(async _ => await RunAsync(), _ => !IsLocked && Items.Count > 0);
        CancelCommand = new RelayCommand(_ => _cts.Cancel(), _ => IsLocked);

        Items.CollectionChanged += Items_CollectionChanged;
    }

    #endregion

    #region Public Methods

    public async Task AddPathsAsync(IEnumerable<string> paths)
    {
        var keySet = KeySetProvider.Instance.KeySet;
        var existing = Items.Select(f => f.FilePath).ToHashSet(StringComparer.OrdinalIgnoreCase);

        var newPaths = await Task.Run(() =>
            paths.Where(p => SupportedExtensions.Contains(Path.GetExtension(p)))
                 .Where(p => existing.Add(p))
                 .ToList());

        var added = new List<RenameFileItem>();

        foreach (var path in newPaths)
        {
            var item = new RenameFileItem(path)
            {
                FileType = keySet == null ? Res.Status_NoKey : Res.Status_Analyzing,
                TitleName = Path.GetFileNameWithoutExtension(path)
            };

            Items.Add(item);
            added.Add(item);
        }

        if (keySet == null)
            return;

        foreach (var item in added)
        {
            var info = await Task.Run<GameFileInfo?>(() =>
            {
                try
                {
                    return MetadataReader.ReadGameFileInfo(keySet.Clone(), item.FilePath);
                }
                catch
                {
                    return null;
                }
            });

            ApplyInfo(item, info);
        }
    }

    public void RemoveItems(IEnumerable<RenameFileItem> items)
    {
        foreach (var item in items.ToList())
            Items.Remove(item);
    }

    public void ClearItems() => Items.Clear();

    public void RefreshPreview()
    {
        var plans = BuildPlans();

        if (plans.Count != Items.Count)
            return;

        for (int i = 0; i < Items.Count; i++)
            Items[i].ApplyPlan(plans[i], GetStatusOverride(Items[i]));

        if (plans.Count == 0)
        {
            Summary = string.Empty;
            return;
        }

        int ready = plans.Count(p => p.State == SwitchRenameState.Ready);
        int skipped = CountSkipped(plans);

        Summary = skipped == 0
            ? $"변경 예정 {ready}개 / 전체 {plans.Count}개"
            : $"변경 예정 {ready}개 / 전체 {plans.Count}개 (건너뜀 {skipped}개)";
    }

    public async Task RunAsync()
    {
        if (IsLocked)
            return;

        if (Items.Count == 0)
        {
            Log(Res.Main_Err_NoFiles, LogLevel.Error);
            return;
        }

        var plans = BuildPlans();
        var ready = plans.Where(p => p.State == SwitchRenameState.Ready).ToList();

        if (ready.Count == 0)
        {
            Log("변경할 파일이 없습니다.", LogLevel.Error);
            return;
        }

        int skipped = CountSkipped(plans);

        if (skipped > 0)
            Log($"건너뜀 {skipped}개 (정보 없음 / 이름 오류 / 중복 / 대상 파일 존재)");

        _cts.Dispose();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        using (BeginWork())
        {
            try
            {
                var results = await Task.Run(() => SwitchRenameService.Apply(ready, token));

                int succeeded = 0;
                int failed = 0;

                foreach (var result in results)
                {
                    if (result.Success)
                    {
                        succeeded++;
                        ReplaceItem(result.Plan);
                        Log($"{result.Plan.OldName} → {result.Plan.NewName}");
                    }
                    else
                    {
                        failed++;
                        Log($"{result.Plan.OldName}: {result.Error}", LogLevel.Error);
                    }
                }

                if (token.IsCancellationRequested)
                {
                    Log("작업이 취소되었습니다.", LogLevel.Error);
                    await SoundPlayer.PlayCancelAsync();
                }
                else if (failed == 0)
                {
                    Log($"파일명 변경 완료: {succeeded}개", LogLevel.Ok);
                    await SoundPlayer.PlayCompleteAsync();
                }
                else
                {
                    Log($"파일명 변경 완료: 성공 {succeeded}개 / 실패 {failed}개", LogLevel.Error);
                    await SoundPlayer.PlayErrorAsync();
                }
            }
            catch (Exception ex)
            {
                Log($"{Res.Log_Error}: {ex.Message}", LogLevel.Error);
                await SoundPlayer.PlayErrorAsync();
            }
        }
    }

    public void Log(string msg, LogLevel level = LogLevel.Info) => Application.Current.Dispatcher.Invoke(() => LogEntries.Add(new LogEntry { Message = msg, Level = level }));

    #endregion

    #region Private Methods

    private void Items_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.OldItems != null)
        {
            foreach (RenameFileItem item in e.OldItems)
                item.PropertyChanged -= Item_PropertyChanged;
        }

        if (e.NewItems != null)
        {
            foreach (RenameFileItem item in e.NewItems)
                item.PropertyChanged += Item_PropertyChanged;
        }

        OnPropertyChanged(nameof(HintVisibility));
        CommandManager.InvalidateRequerySuggested();
        ScheduleRefresh();
    }

    private void Item_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(GameFile.FileType) or nameof(GameFile.TitleID) or nameof(GameFile.Version))
            ScheduleRefresh();
    }

    private void ScheduleRefresh()
    {
        if (_refreshQueued)
            return;

        _refreshQueued = true;

        Application.Current.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
        {
            _refreshQueued = false;
            RefreshPreview();
        }));
    }

    private static void ApplyInfo(RenameFileItem item, GameFileInfo? info)
    {
        if (info == null)
        {
            item.FileType = "?";
            return;
        }

        if (!string.IsNullOrEmpty(info.TitleName))
            item.TitleName = info.TitleName;

        if (info.IconData != null)
            item.Icon = info.IconData.ToBitmapImage();

        item.Naming = info.Naming;
        item.TitleID = info.TitleId;
        item.Version = info.DisplayVersion;
        item.FileType = info.Type;
    }

    private static string? GetStatusOverride(GameFile file)
    {
        if (file.FileType == Res.Status_Analyzing)
            return "분석 중";

        if (file.FileType == Res.Status_NoKey)
            return "키 없음";

        return null;
    }

    private List<SwitchRenamePlan> BuildPlans() => SwitchRenameService.BuildPlans(Items.Select(ToSource), FormatText);

    private static SwitchRenameSource ToSource(GameFile file)
    {
        var naming = file.Naming;

        string tag = NspNameBuilder.BuildTagPart(file.FileType.Contains('B'), file.FileType.Contains('U'), naming?.DlcCount ?? 0);

        string name = naming is null ? string.Empty : NspNameBuilder.BuildNamePart(naming.KrTitle, naming.EnTitle);

        return new SwitchRenameSource(
            file.FilePath,
            name,
            naming?.KoreanTitle,
            naming?.DefaultTitle,
            file.TitleID,
            tag,
            naming?.DisplayVersion ?? file.Version,
            naming?.TitleVersion.ToString(),
            HasMetadata(file));
    }

    private static bool HasMetadata(GameFile file) =>
        file.Naming is not null
        && !string.IsNullOrEmpty(file.TitleID)
        && file.FileType != Res.Status_NoKey
        && file.FileType != Res.Status_Analyzing
        && file.FileType != "?";

    private static int CountSkipped(IEnumerable<SwitchRenamePlan> plans) =>
        plans.Count(p => p.State is not (SwitchRenameState.Ready or SwitchRenameState.Unchanged));

    private void ReplaceItem(SwitchRenamePlan plan)
    {
        for (int i = 0; i < Items.Count; i++)
        {
            var old = Items[i];

            if (!string.Equals(old.FilePath, plan.SourcePath, StringComparison.OrdinalIgnoreCase))
                continue;

            Items[i] = new RenameFileItem(plan.TargetPath)
            {
                TitleName = old.TitleName,
                TitleID = old.TitleID,
                Version = old.Version,
                Icon = old.Icon,
                Naming = old.Naming,
                FileType = old.FileType
            };

            return;
        }
    }

    #endregion
}