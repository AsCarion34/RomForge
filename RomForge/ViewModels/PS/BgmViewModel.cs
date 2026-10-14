using Common;
using Common.WPF.ViewModels;
using PBP.Core.AT3.Models;
using RomForge.Core;
using RomForge.Core.Services.PS;
using System.IO;
using System.Windows;

namespace RomForge.ViewModels.PS;

public class BgmViewModel : ViewModelBase
{
    private readonly Action<string, LogLevel> _log;

    private string? _filePath;
    private bool _isConverting;
    private int _progressPct;

    public BgmViewModel(Action<string, LogLevel> log)
    {
        _log = log;

        Preview = new BgmPreviewViewModel(log);
    }

    public BgmPreviewViewModel Preview { get; }

    public byte[]? Bytes { get; private set; }

    public string? FilePath
    {
        get => _filePath;
        private set
        {
            SetProperty(ref _filePath, value);
            OnPropertyChanged(nameof(FileName));
            OnPropertyChanged(nameof(HasBgm));
        }
    }

    public string FileName => !string.IsNullOrEmpty(FilePath) ? Path.GetFileName(FilePath) : string.Empty;

    public bool HasBgm => !string.IsNullOrEmpty(FilePath);

    public bool IsHighQualityMode
    {
        get => AppConfig.Instance.PS1.IsHighQualityMode;
        set
        {
            if (IsConverting)
                return;

            if (AppConfig.Instance.PS1.IsHighQualityMode != value)
            {
                AppConfig.Instance.PS1.IsHighQualityMode = value;

                OnPropertyChanged();

                if (!string.IsNullOrEmpty(FilePath))
                    _ = SetPathAsync(FilePath);
            }
        }
    }

    public bool IsConverting
    {
        get => _isConverting;
        private set => SetProperty(ref _isConverting, value);
    }

    public int ProgressPct
    {
        get => _progressPct;
        private set
        {
            if (SetProperty(ref _progressPct, value))
                OnPropertyChanged(nameof(ProgressText));
        }
    }

    public string ProgressText => $"{ProgressPct}%";

    public async Task SetPathAsync(string filePath)
    {
        if (IsConverting)
            return;

        IsConverting = true;
        ProgressPct = 0;

        Preview.Stop();

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

                    Application.Current.Dispatcher.InvokeAsync(() => ProgressPct = pct);
                }
            };

            _log($"배경음 변환 시작: {Path.GetFileName(filePath)}", LogLevel.Highlight);

            var (bgm, wav) = await Task.Run(() =>
            {
                byte[] rawBytes = File.ReadAllBytes(filePath);
                byte[] converted = ext == ".at3" ? rawBytes : At3Encoder.Convert(rawBytes, ext == ".wav", options);
                byte[]? preview = null;

                try
                {
                    preview = At3Decoder.ToWav(converted);
                }
                catch (Exception ex)
                {
                    _log($"미리듣기 준비 실패: {ex.Message}", LogLevel.Error);
                }

                return (converted, preview);
            });

            Bytes = bgm;
            Preview.Load(wav);

            FilePath = filePath;
            _log($"배경음 변환 완료: {Path.GetFileName(filePath)}", LogLevel.Ok);
        }
        catch (Exception ex)
        {
            _log($"배경음 변환 중 오류 발생: {ex.Message}", LogLevel.Error);
        }
        finally
        {
            IsConverting = false;
        }
    }

    public void Reset()
    {
        Preview.Clear();

        Bytes = null;
        FilePath = null;
    }
}