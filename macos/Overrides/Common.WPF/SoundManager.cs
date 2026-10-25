using System.Diagnostics;

namespace Common.WPF;

// upstream Common.WPF/SoundManager.cs의 macOS 대체.
// upstream은 NAudio(WaveOutEvent·Mp3FileReader → Windows winmm·ACM)로 재생한다. macOS에서는 기본 제공 afplay로 재생한다.
// pack://application:,,,/Assets/Sounds/x.mp3 는 엔진 실행 파일 옆 Assets/Sounds/x.mp3(macos/build/Mac.targets가 복사)를 쓴다.
// 공개 API는 upstream과 같게 유지해야 한다(RomForge.Core SoundPlayer가 사용).
public static class SoundManager
{
    private const string PackPrefix = "pack://application:,,,/";

    private static readonly object _lock = new();
    private static Process? _player;

    public static async Task PlayFromWpfResourceAsync(string packUriString)
    {
        string path;

        try
        {
            path = ResolvePath(packUriString);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"오디오 스트림 로드 오류: {ex.Message}");
            return;
        }

        lock (_lock)
            StopInternal();

        await Task.Run(() =>
        {
            lock (_lock)
            {
                try
                {
                    string extension = Path.GetExtension(path).ToLowerInvariant();

                    // upstream과 같은 형식만 재생한다.
                    if (extension is not (".wav" or ".mp3"))
                        throw new NotSupportedException($"지원하지 않는 오디오 형식입니다: {extension}");

                    var psi = new ProcessStartInfo("/usr/bin/afplay") { UseShellExecute = false };
                    psi.ArgumentList.Add(path);

                    _player = Process.Start(psi);
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"오디오 재생 중 오류 발생: {ex.Message}");
                    DisposeResources();
                }
            }
        });
    }

    public static async Task PlayFromFileAsync(string filePath) => await PlayFromWpfResourceAsync(filePath);

    public static void Stop()
    {
        lock (_lock)
            StopInternal();
    }

    private static string ResolvePath(string packUriString)
    {
        if (Path.IsPathRooted(packUriString) || File.Exists(packUriString))
            return packUriString;

        if (!packUriString.StartsWith(PackPrefix, StringComparison.OrdinalIgnoreCase))
            throw new FileNotFoundException($"WPF 리소스를 찾을 수 없습니다: {packUriString}");

        string path = Path.Combine(AppContext.BaseDirectory, Uri.UnescapeDataString(packUriString[PackPrefix.Length..]));

        return File.Exists(path) ? path : throw new FileNotFoundException($"WPF 리소스를 찾을 수 없습니다: {packUriString}");
    }

    private static void StopInternal()
    {
        try
        {
            if (_player is { HasExited: false })
                _player.Kill();
        }
        catch
        {
            // 이미 끝난 프로세스
        }
        finally
        {
            DisposeResources();
        }
    }

    private static void DisposeResources()
    {
        _player?.Dispose();
        _player = null;
    }
}
