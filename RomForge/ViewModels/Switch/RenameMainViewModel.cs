using Common;
using Common.WPF.ViewModels;
using NSW.Utils;
using NSW.WPF.ViewModels;
using RomForge.Core.Models;
using RomForge.Core.Models.Patch;
using RomForge.Core.Models.Switch;
using RomForge.Core.Services;
using RomForge.Core.Services.Switch;
using System.Collections.ObjectModel;
using System.Windows;
using Res = NSW.Core.Properties.Resources;

namespace RomForge.ViewModels.Switch;

public class RenameMainViewModel : ToolTabViewModel
{
    #region Fields & Properties

    private CancellationTokenSource? _cts;
    private string _formatText = SwitchRenamePresets.Default.Format!;
    private NamingFormatPreset _selectedNamingPreset = SwitchRenamePresets.Default;
    private string _summary = string.Empty;
    private IReadOnlyList<RenamePreviewItem> _previewItems = [];

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    public static IReadOnlyList<NamingFormatPreset> NamingPresets => SwitchRenamePresets.All;

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
        set => SetProperty(ref _formatText, value);
    }

    public string Summary
    {
        get => _summary;
        private set => SetProperty(ref _summary, value);
    }

    public IReadOnlyList<RenamePreviewItem> PreviewItems
    {
        get => _previewItems;
        private set => SetProperty(ref _previewItems, value);
    }

    #endregion

    #region Public Methods

    public void RefreshPreview(IList<GameFile> gameFiles)
    {
        var plans = BuildPlans(gameFiles);

        PreviewItems = [.. plans.Select(p => new RenamePreviewItem(p))];

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

    public async Task ExecuteStartWorkAsync(IList<GameFile> gameFiles)
    {
        if (IsLocked)
            return;

        if (gameFiles.Count == 0)
        {
            Log(Res.Main_Err_NoFiles, LogLevel.Error);
            return;
        }

        var plans = BuildPlans(gameFiles);
        var ready = plans.Where(p => p.State == SwitchRenameState.Ready).ToList();

        if (ready.Count == 0)
        {
            Log("변경할 파일이 없습니다.", LogLevel.Error);
            return;
        }

        int skipped = CountSkipped(plans);

        if (skipped > 0)
            Log($"건너뜀 {skipped}개 (정보 없음 / 이름 오류 / 중복 / 대상 파일 존재)");

        using (BeginWork())
        {
            try
            {
                _cts = new CancellationTokenSource();
                var token = _cts.Token;

                var results = await Task.Run(() => SwitchRenameService.Apply(ready, token));

                int succeeded = 0;
                int failed = 0;

                foreach (var result in results)
                {
                    if (result.Success)
                    {
                        succeeded++;
                        ReplaceGameFile(gameFiles, result.Plan);
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
            finally
            {
                _cts?.Dispose();
                _cts = null;
            }
        }
    }

    public void Cancel() => _cts?.Cancel();

    #endregion

    #region Private Methods

    private List<SwitchRenamePlan> BuildPlans(IEnumerable<GameFile> gameFiles) =>
        SwitchRenameService.BuildPlans(gameFiles.Select(ToSource), FormatText);

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
        !string.IsNullOrEmpty(file.TitleID)
        && file.FileType != Res.Status_NoKey
        && file.FileType != Res.Status_Analyzing
        && file.FileType != "?";

    private static int CountSkipped(IEnumerable<SwitchRenamePlan> plans) =>
        plans.Count(p => p.State is not (SwitchRenameState.Ready or SwitchRenameState.Unchanged));

    private static void ReplaceGameFile(IList<GameFile> gameFiles, SwitchRenamePlan plan)
    {
        for (int i = 0; i < gameFiles.Count; i++)
        {
            var old = gameFiles[i];

            if (!string.Equals(old.FilePath, plan.SourcePath, StringComparison.OrdinalIgnoreCase))
                continue;

            gameFiles[i] = new GameFile(plan.TargetPath)
            {
                TitleName = old.TitleName,
                TitleID = old.TitleID,
                Version = old.Version,
                Icon = old.Icon,
                Naming = old.Naming,
                FileType = old.FileType,
                ProgramIdOffsets = old.ProgramIdOffsets,
                PatchPath = old.PatchPath,
                PatchPassword = old.PatchPassword
            };

            return;
        }
    }

    public void Log(string msg, LogLevel level = LogLevel.Info) => Application.Current.Dispatcher.Invoke(() => LogEntries.Add(new LogEntry { Message = msg, Level = level }));

    #endregion
}