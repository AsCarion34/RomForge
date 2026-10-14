using NAudio.Wave;
using System.IO;
using System.Windows;
using System.Windows.Resources;

namespace Common.WPF;

public static class SoundManager
{
    private static readonly object _lock = new object();
    private static IWavePlayer? _waveOutDevice;
    private static Mp3FileReader? _audioFileReader;
    private static MemoryStream? _memoryStream;

    public static async Task PlayFromWpfResourceAsync(string packUriString)
    {
        StreamResourceInfo resourceStreamInfo = null;
        try
        {
            var uri = new Uri(packUriString, UriKind.Absolute);
            resourceStreamInfo = Application.GetResourceStream(uri);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"WPF 리소스 로드 오류: {ex.Message}");
            return;
        }

        if (resourceStreamInfo == null)
        {
            throw new FileNotFoundException($"WPF 리소스를 찾을 수 없습니다: {packUriString}");
        }

        await Task.Run(() =>
        {
            lock (_lock)
            {
                try
                {
                    StopInternal();

                    var memoryStream = new MemoryStream();

                    resourceStreamInfo.Stream.CopyTo(memoryStream);

                    memoryStream.Position = 0;
                    _memoryStream = memoryStream;

                    _audioFileReader = new Mp3FileReader(_memoryStream);
                    _waveOutDevice = new WaveOutEvent();

                    _waveOutDevice.Init(_audioFileReader);

                    _waveOutDevice.PlaybackStopped += (s, e) => {
                        lock (_lock)
                        {
                            DisposeResources();
                        }
                    };

                    _waveOutDevice.Play();
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"오디오 재생 중 오류 발생: {ex.Message}");
                    DisposeResources();
                }
            }
        });
    }

    public static void Stop()
    {
        lock (_lock)
            StopInternal();
    }

    private static void StopInternal()
    {
        try
        {
            _waveOutDevice?.Stop();
        }
        catch
        {
        }
        finally
        {
            DisposeResources();
        }
    }

    private static void DisposeResources()
    {
        _waveOutDevice?.Dispose();
        _waveOutDevice = null;

        _audioFileReader?.Dispose();
        _audioFileReader = null;

        _memoryStream?.Dispose();
        _memoryStream = null;
    }
}