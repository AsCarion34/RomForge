using Common;
using Common.WPF.ViewModels;
using NAudio.Wave;
using NSW.WPF.Services;
using PBP.Core.AT3.Models;
using PBP.Core.Models;
using PBP.Core.Services;
using RomForge.Core;
using RomForge.Core.Models;
using RomForge.Core.Models.PS;
using RomForge.Core.Services.PS;
using RomForge.Core.UI.Command;
using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace RomForge.ViewModels.PS;

public class PackingMainViewModel : ToolTabViewModel
{
    private const int MaxItems = 5;

    public record FmvFixOption(string Label, uint Value);

    public ObservableCollection<FmvFixOption> FmvFixPresets { get; } = [new("0x04 (다수 게임에서 검증됨)", 0x04), new("0x07 (실험적)", 0x07)];

    private readonly DiscImportService _importService = new();
    private readonly CoverArtUpdater _coverArtUpdater = new();

    private CancellationTokenSource _cts = new();

    private string? _lastIconGameId;
    private string _gameTitle = string.Empty;
    private int _progressPct;
    private string _progressLabel = string.Empty;
    private string _progressPercent = "0%";
    private string _progressTime = string.Empty;
    private string _progressSpeed = string.Empty;
    private bool _isDownloading;
    private bool _isValidating;
    private bool _useFmvFix;
    private bool _useCdTimingFix;
    private byte[]? _previewPcmBytes;
    private WaveOutEvent? _waveOut;
    private WaveStream? _waveStream;
    private readonly DispatcherTimer _previewTimer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private bool _isSeeking;
    private double _previewPositionSeconds;
    private double _previewDurationSeconds;

    public byte[] Icon0Bytes { get; set; } = EmbeddedAssetProvider.GetDefaultIcon0();

    public byte[] Pic0Bytes { get; set; } = EmbeddedAssetProvider.GetDefaultPic0();

    public byte[] Pic1Bytes { get; set; } = EmbeddedAssetProvider.GetDefaultPic1();

    public byte[]? BootLogoBytes { get; set; }

    public byte[]? BgmBytes { get; set; }

    private string? _bgmFilePath;
    public string? BgmFilePath
    {
        get => _bgmFilePath;
        set
        {
            SetProperty(ref _bgmFilePath, value);
            OnPropertyChanged(nameof(BgmFileName));
            OnPropertyChanged(nameof(HasBgm));
        }
    }

    public string BgmFileName => !string.IsNullOrEmpty(BgmFilePath) ? Path.GetFileName(BgmFilePath) : string.Empty;

    public bool HasBgm => !string.IsNullOrEmpty(BgmFilePath);

    public bool IsHighQualityMode
    {
        get => AppConfig.Instance.PS1.IsHighQualityMode;
        set
        {
            if (IsBgmConverting)
                return;

            if (AppConfig.Instance.PS1.IsHighQualityMode != value)
            {
                AppConfig.Instance.PS1.IsHighQualityMode = value;

                OnPropertyChanged();

                if (!string.IsNullOrEmpty(BgmFilePath))
                    _ = SetBgmPathAsync(BgmFilePath);
            }
        }
    }

    private bool _isPlayingBgm;
    public bool IsPlayingBgm
    {
        get => _isPlayingBgm;
        set => SetProperty(ref _isPlayingBgm, value);
    }

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

    public bool IsDownloading
    {
        get => _isDownloading;
        set
        {
            _isDownloading = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanRun));
            Application.Current.Dispatcher.InvokeAsync(CommandManager.InvalidateRequerySuggested);
        }
    }

    public bool IsValidating
    {
        get => _isValidating;
        set
        {
            _isValidating = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanAdd));
        }
    }

    private FmvFixOption _selectedFmvFix;
    public FmvFixOption SelectedFmvFix
    {
        get => _selectedFmvFix;
        set => SetProperty(ref _selectedFmvFix, value);
    }

    public bool UseFmvFix
    {
        get => _useFmvFix;
        set => SetProperty(ref _useFmvFix, value);
    }

    public bool UseCdTimingFix
    {
        get => _useCdTimingFix;
        set => SetProperty(ref _useCdTimingFix, value);
    }

    private BitmapImage? _icon0Image;
    public BitmapImage? Icon0Image
    {
        get => _icon0Image;
        set => SetProperty(ref _icon0Image, value);
    }

    private BitmapImage? _pic0Image;
    public BitmapImage? Pic0Image
    {
        get => _pic0Image;
        set => SetProperty(ref _pic0Image, value);
    }

    private BitmapImage? _pic1Image;
    public BitmapImage? Pic1Image
    {
        get => _pic1Image;
        set => SetProperty(ref _pic1Image, value);
    }

    private BitmapImage? _bootLogoImage;
    public BitmapImage? BootLogoImage
    {
        get => _bootLogoImage;
        set
        {
            SetProperty(ref _bootLogoImage, value);
            OnPropertyChanged(nameof(HasBootLogo));
            OnPropertyChanged(nameof(ShowBootLogoHint));
        }
    }

    private bool _isBgmConverting;
    public bool IsBgmConverting
    {
        get => _isBgmConverting;
        private set => SetProperty(ref _isBgmConverting, value);
    }

    private int _bgmProgressPct;
    public int BgmProgressPct
    {
        get => _bgmProgressPct;
        private set
        {
            if (SetProperty(ref _bgmProgressPct, value))
                OnPropertyChanged(nameof(BgmProgressText));
        }
    }

    public bool HasBootLogo => BootLogoImage != null;

    public bool ShowBootLogoHint => !HasBootLogo;

    public bool HasPresetConfig => FileItems.FirstOrDefault(i => i.No == 1)?.HasPresetConfig ?? false;

    public bool CanEditPopsConfig => IsUnlocked && !HasPresetConfig;

    public ObservableCollection<LogEntry> LogEntries { get; } = [];

    public ObservableCollection<DiscFileItem> FileItems { get; } = [];

    public Visibility HintVisibility => FileItems.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    public bool CanAdd => !IsLocked && FileItems.Count < MaxItems;

    public bool CanRun => !IsLocked && FileItems.Count > 0 && !IsDownloading;

    public ICommand RunCommand { get; }

    public ICommand SettingsCommand { get; }

    public ICommand TogglePlayBgmCommand { get; }

    public bool HasPreview => _previewPcmBytes is { Length: > 0 };

    public double PreviewDurationSeconds
    {
        get => _previewDurationSeconds;
        private set
        {
            if (SetProperty(ref _previewDurationSeconds, value))
                OnPropertyChanged(nameof(PreviewDurationText));
        }
    }

    public double PreviewPositionSeconds
    {
        get => _previewPositionSeconds;
        set
        {
            value = Math.Clamp(value, 0, _previewDurationSeconds);

            if (Math.Abs(value - _previewPositionSeconds) < 0.001)
                return;

            SetPreviewPosition(value);

            if (!_isSeeking)
                SeekPreview(value);
        }
    }

    public string PreviewPositionText => FormatPreviewTime(_previewPositionSeconds);

    public string PreviewDurationText => FormatPreviewTime(_previewDurationSeconds);

    public event EventHandler RunNavigateSettings;

    public PackingMainViewModel()
    {
        RunCommand = new RelayCommand(async _ => await RunAsync(), _ => CanRun);
        CancelCommand = new RelayCommand(_ => _cts.Cancel(), _ => IsLocked);
        SettingsCommand = new RelayCommand(async _ => RunNavigateSettings?.Invoke(this, EventArgs.Empty), _ => !IsLocked);
        TogglePlayBgmCommand = new RelayCommand(_ => TogglePlayBgm());
        _previewTimer.Tick += (_, _) => UpdatePreviewPosition();

        Icon0Image = Icon0Bytes.ToBitmapImage();
        Pic0Image = Pic0Bytes.ToBitmapImage();
        Pic1Image = Pic1Bytes.ToBitmapImage();

        SelectedFmvFix = FmvFixPresets[0];

        FileItems.CollectionChanged += (s, e) => OnPropertyChanged(nameof(CanAdd));

        PropertyChanged += (sender, e) =>
        {
            if (e.PropertyName == nameof(IsLocked))
                OnPropertyChanged(nameof(CanAdd));
        };
    }

    public async void AddPaths(IEnumerable<string> paths)
    {
        try
        {
            await AddPathsCoreAsync(paths);
        }
        catch (Exception ex)
        {
            AppendLog($"파일 추가 중 오류: {ex.Message}", LogLevel.Error);
            IsValidating = false;
        }
    }

    private async Task AddPathsCoreAsync(IEnumerable<string> paths)
    {
        var inputPaths = paths.ToList();

        if (inputPaths.Count == 0)
            return;

        var existingPaths = FileItems.Select(f => f.FilePath);
        var room = MaxItems - FileItems.Count;

        IsValidating = true;

        ImportResult result;

        try
        {
            result = await _importService.ImportAsync(inputPaths, existingPaths, room);
        }
        finally
        {
            IsValidating = false;
        }

        foreach (var failure in result.Failures)
            AppendLog($"[{failure.FileName}] GameID 인식 실패: {failure.Reason}", LogLevel.Error);

        foreach (var disc in result.Imported)
        {
            var item = new DiscFileItem(disc.Path)
            {
                GameId = disc.GameId,
                FileSizeBytes = disc.Size,
                PresetConfigBytes = disc.PresetConfig
            };

            FileItems.Add(item);
        }

        if (result.OverLimitSkipped > 0)
            AppendLog($"최대 {MaxItems}개까지만 등록할 수 있습니다. {result.OverLimitSkipped}개 파일이 제외되었습니다.", LogLevel.Error);

        if (result.Failures.Count > 0)
            AppendLog($"{result.Failures.Count}개 파일에서 GameID 인식에 실패해 제외되었습니다.", LogLevel.Error);

        if (result.Imported.Count > 0)
        {
            OnPropertyChanged(nameof(HintVisibility));
            DiscListSorter.SortAndRenumber(FileItems);
            _ = UpdateImageAsync();
            OnPropertyChanged(nameof(HasPresetConfig));
            OnPropertyChanged(nameof(CanEditPopsConfig));
        }

        CommandManager.InvalidateRequerySuggested();
    }

    public void RemoveItems(IEnumerable<DiscFileItem> items)
    {
        foreach (var item in items.ToList())
            FileItems.Remove(item);

        OnPropertyChanged(nameof(HintVisibility));
        DiscListSorter.SortAndRenumber(FileItems);
        _ = UpdateImageAsync();
        OnPropertyChanged(nameof(HasPresetConfig));
        OnPropertyChanged(nameof(CanEditPopsConfig));
    }

    public void ClearItems()
    {
        FileItems.Clear();
        OnPropertyChanged(nameof(HintVisibility));
        _lastIconGameId = null;
        ResetBaseImages();
        ResetBootLogo();
        ResetBgm();
        OnPropertyChanged(nameof(HasPresetConfig));
        OnPropertyChanged(nameof(CanEditPopsConfig));
    }

    public void SetIcon0FromBytes(byte[] rawBytes)
    {
        var (bytes, img) = AssetImageEditor.Resize(rawBytes, 80, 80);
        Icon0Bytes = bytes;
        Icon0Image = img;
    }

    public void SetPic0FromBytes(byte[] rawBytes)
    {
        var (bytes, img) = AssetImageEditor.Resize(rawBytes, 270, 150);
        Pic0Bytes = bytes;
        Pic0Image = img;
    }

    public void SetPic1FromBytes(byte[] rawBytes)
    {
        var (bytes, img) = AssetImageEditor.Resize(rawBytes, 480, 272);
        Pic1Bytes = bytes;
        Pic1Image = img;
    }

    public void SetBootLogoFromBytes(byte[] rawBytes)
    {
        var (bytes, img) = AssetImageEditor.Resize(rawBytes, 480, 272);
        BootLogoBytes = bytes;
        BootLogoImage = img;
    }

    public string BgmProgressText => $"{BgmProgressPct}%";

    public async Task SetBgmPathAsync(string filePath)
    {
        if (IsBgmConverting)
            return;

        IsBgmConverting = true;
        BgmProgressPct = 0;

        ReleasePreviewPlayer();
        SetPreviewPosition(0);

        try
        {
            string ext = Path.GetExtension(filePath).ToLowerInvariant();
            int lastPct = -1;
            var options = new ConverterOptions
            {
                BitrateKbps = IsHighQualityMode ? Bitrate.Kbps132 : Bitrate.Kbps66,
                MaxSeconds = IsHighQualityMode ? 30 : 60,
                OnProgress = p =>
                {
                    int pct = (int)(p * 100);

                    if (pct == lastPct)
                        return;

                    lastPct = pct;

                    Application.Current.Dispatcher.InvokeAsync(() => BgmProgressPct = pct);
                }
            };

            await Task.Run(() =>
            {
                byte[] rawBytes = File.ReadAllBytes(filePath);
                byte[] bgm = ext == ".at3" ? rawBytes : At3Encoder.Convert(rawBytes, ext == ".wav", options);

                BgmBytes = bgm;

                try
                {
                    _previewPcmBytes = At3Decoder.ToWav(bgm);
                }
                catch (Exception ex)
                {
                    _previewPcmBytes = null;
                    AppendLog($"미리듣기 준비 실패: {ex.Message}", LogLevel.Info);
                }
            });

            PreviewDurationSeconds = GetPreviewDuration(_previewPcmBytes);
            OnPropertyChanged(nameof(HasPreview));

            BgmFilePath = filePath;
            AppendLog($"배경음 설정 완료: {Path.GetFileName(filePath)}", LogLevel.Info);
        }
        catch (Exception ex)
        {
            AppendLog($"배경음 처리 중 오류 발생: {ex.Message}", LogLevel.Error);
        }
        finally
        {
            IsBgmConverting = false;
        }
    }

    public void ResetBaseImages()
    {
        Icon0Bytes = EmbeddedAssetProvider.GetDefaultIcon0();
        Icon0Image = Icon0Bytes.ToBitmapImage();
        Pic0Bytes = EmbeddedAssetProvider.GetDefaultPic0();
        Pic0Image = Pic0Bytes.ToBitmapImage();
        Pic1Bytes = EmbeddedAssetProvider.GetDefaultPic1();
        Pic1Image = Pic1Bytes.ToBitmapImage();
    }

    public void ResetBootLogo()
    {
        BootLogoBytes = null;
        BootLogoImage = null;
    }

    private async Task UpdateImageAsync()
    {
        var primary = FileItems.FirstOrDefault(i => i.No == 1);

        if (primary == null || primary.GameId == _lastIconGameId || primary.GameId is "인식중..." or "인식실패")
            return;

        _lastIconGameId = primary.GameId;
        IsDownloading = true;

        try
        {
            var result = await _coverArtUpdater.FetchAsync(primary.GameId);

            if (result == null)
                return;

            if (result.ETitle != null)
                GameTitle = result.ETitle;

            Icon0Bytes = result.Icon0Png;
            Icon0Image = Icon0Bytes.ToBitmapImage();

            Pic0Bytes = result.Pic0Png;
            Pic0Image = Pic0Bytes.ToBitmapImage();

            Pic1Bytes = result.Pic1Png;
            Pic1Image = Pic1Bytes.ToBitmapImage();
        }
        finally
        {
            IsDownloading = false;
        }
    }

    private async Task RunAsync()
    {
        _cts.Dispose();
        _cts = new CancellationTokenSource();

        if (FileItems.Count == 0)
        {
            AppendLog("추가된 파일이 없습니다.", LogLevel.Error);
            return;
        }

        if (FileItems.Any(i => i.GameId is "인식중..." or "인식실패"))
        {
            AppendLog("GameID 인식 오류", LogLevel.Error);
            return;
        }

        using (BeginWork())
        {
            var orderedItems = FileItems.OrderBy(i => i.No).ToList();
            var gameTitle = string.IsNullOrWhiteSpace(GameTitle) ? DiscListSorter.GuessTitle(orderedItems[0].FilePath) : GameTitle;
            var mainGameId = orderedItems[0].GameId;
            var assets = new PbpAssets
            {
                Icon0Png = Icon0Bytes.ResizePng(80, 80),
                Pic0Png = Pic0Bytes.ResizePng(480, 272),
                Pic1Png = Pic1Bytes.ResizePng(480, 272),
                BootPng = BootLogoBytes?.ResizePng(480, 272),
                Snd0At3 = BgmBytes,
                DataPsp = EmbeddedAssetProvider.GetDefaultData()
            };
            var plan = PackingJobRunner.PlanOutput(orderedItems[0].FilePath, gameTitle, mainGameId);
            byte[]? popsConfig = orderedItems[0].PresetConfigBytes;

            if (popsConfig == null && (UseFmvFix || UseCdTimingFix))
            {
                var fmvValue = UseFmvFix ? SelectedFmvFix.Value : 0;
                popsConfig = ExternalConfigBuilder.Build(UseFmvFix, fmvValue, UseCdTimingFix);
            }

            try
            {
                AppendLog($"작업 시작: {gameTitle} [{mainGameId}] ({orderedItems.Count}개 디스크)", LogLevel.Highlight);
                await PackingJobRunner.RunAsync(orderedItems, gameTitle, mainGameId, plan, AppConfig.Instance.PS1.CompressLevel, assets, popsConfig, BuildProgressReporter(), _cts.Token);

                ProgressPct = 100;

                AppendLog($"작업 완료: {plan.TargetOutputPath}", LogLevel.Ok);
                Path.GetDirectoryName(plan.TargetOutputPath).OpenFolder();
            }
            catch (OperationCanceledException)
            {
                AppendLog("작업이 취소되었습니다.", LogLevel.Error);
                CleanupTask();
                MainViewModel.SetTaskbarProgress(0);
                TryDeleteFileAndFolder(plan.TargetOutputPath, plan.GameDirectory);
            }
            catch (Exception ex)
            {
                AppendLog($"오류: [{gameTitle}] {ex.Message}", LogLevel.Error);
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

    public static string GetFileDialogFilter() => DiscImportService.GetFileDialogFilter();

    private void TogglePlayBgm()
    {
        if (IsPlayingBgm)
            PausePreview();
        else
            StartBgmPreview();
    }

    private bool EnsurePreviewPlayer()
    {
        if (_waveOut != null && _waveStream != null)
            return true;

        if (_previewPcmBytes == null || _previewPcmBytes.Length == 0)
            return false;

        try
        {
            _waveStream = new WaveFileReader(new MemoryStream(_previewPcmBytes));
            _waveOut = new WaveOutEvent();
            _waveOut.Init(_waveStream);
            _waveOut.PlaybackStopped += OnPreviewPlaybackStopped;

            return true;
        }
        catch (Exception ex)
        {
            AppendLog($"미리듣기 재생 중 오류: {ex.Message}", LogLevel.Error);
            ReleasePreviewPlayer();

            return false;
        }
    }

    private void StartBgmPreview()
    {
        if (!EnsurePreviewPlayer())
            return;

        try
        {
            _waveOut!.Play();
            IsPlayingBgm = true;
            _previewTimer.Start();
        }
        catch (Exception ex)
        {
            AppendLog($"미리듣기 재생 중 오류: {ex.Message}", LogLevel.Error);
            ReleasePreviewPlayer();
        }
    }

    private void PausePreview()
    {
        _waveOut?.Pause();
        _previewTimer.Stop();
        IsPlayingBgm = false;
        UpdatePreviewPosition();
    }

    private void SeekPreview(double seconds)
    {
        if (!EnsurePreviewPlayer())
            return;

        _waveStream!.CurrentTime = TimeSpan.FromSeconds(seconds);
    }

    public void BeginPreviewSeek()
    {
        _isSeeking = true;
    }

    public void EndPreviewSeek()
    {
        _isSeeking = false;
        SeekPreview(_previewPositionSeconds);
    }

    private void UpdatePreviewPosition()
    {
        if (_isSeeking || _waveStream == null)
            return;

        SetPreviewPosition(_waveStream.CurrentTime.TotalSeconds);
    }

    private void SetPreviewPosition(double seconds)
    {
        _previewPositionSeconds = Math.Clamp(seconds, 0, _previewDurationSeconds);

        OnPropertyChanged(nameof(PreviewPositionSeconds));
        OnPropertyChanged(nameof(PreviewPositionText));
    }

    private void OnPreviewPlaybackStopped(object? sender, StoppedEventArgs e)
    {
        if (!ReferenceEquals(sender, _waveOut))
            return;

        if (e.Exception != null)
            AppendLog($"미리듣기 재생 중 오류: {e.Exception.Message}", LogLevel.Error);

        ReleasePreviewPlayer();
        SetPreviewPosition(0);
    }

    private void ReleasePreviewPlayer()
    {
        _previewTimer.Stop();

        try
        {
            if (_waveOut != null)
            {
                _waveOut.PlaybackStopped -= OnPreviewPlaybackStopped;
                _waveOut.Stop();
                _waveOut.Dispose();
                _waveOut = null;
            }

            _waveStream?.Dispose();
            _waveStream = null;
        }
        catch { }
        finally
        {
            IsPlayingBgm = false;
        }
    }

    private static double GetPreviewDuration(byte[]? wav)
    {
        if (wav == null || wav.Length == 0)
            return 0;

        using var reader = new WaveFileReader(new MemoryStream(wav));

        return reader.TotalTime.TotalSeconds;
    }

    private static string FormatPreviewTime(double seconds)
    {
        var t = TimeSpan.FromSeconds(Math.Max(0, seconds));

        return $"{(int)t.TotalMinutes}:{t.Seconds:00}";
    }

    public void ResetBgm()
    {
        ReleasePreviewPlayer();
        SetPreviewPosition(0);

        PreviewDurationSeconds = 0;
        BgmBytes = null;
        BgmFilePath = null;
        _previewPcmBytes = null;

        OnPropertyChanged(nameof(HasPreview));
    }
}