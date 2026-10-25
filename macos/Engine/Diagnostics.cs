using System.Windows;
using SevenZip;

namespace RomForge.Mac.Engine;

/// <summary>
/// 라이브러리 단위 점검(개발·CI용).
///   --test-7z 압축파일 [비밀번호]   SevenZipSharp 대체 구현으로 목록·압축 해제·CRC 확인
///   --test-disks                   PickPack.Disk macOS 구현의 디스크 목록(예외를 그대로 보여 준다)
///   --test-audio                   효과음(SoundManager → afplay)과 PSP 배경음 미리듣기(BgmPreviewViewModel → WaveOutEvent → AudioQueue)를
///                                  무음 WAV로 재생·일시정지·이동·끝까지 재생해 본다(소리는 나지 않는다)
/// </summary>
internal static class Diagnostics
{
    public static int TestAudio(Application app)
    {
        var failures = new List<string>();
        void Check(bool ok, string what)
        {
            Console.WriteLine($"{(ok ? "통과" : "실패")}: {what}");
            if (!ok)
                failures.Add(what);
        }

        byte[] wav = SilentWav(1.5);
        string file = Path.Combine(Path.GetTempPath(), $"rf-audio-{Guid.NewGuid():N}.wav");
        File.WriteAllBytes(file, wav);

        try
        {
            // 1) 효과음: upstream SoundPlayer가 부르는 SoundManager(macOS 대체: afplay)
            app.Dispatcher.Invoke(() => Common.WPF.SoundManager.PlayFromFileAsync(file)).GetAwaiter().GetResult();
            var player = typeof(Common.WPF.SoundManager).GetField("_player", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!.GetValue(null) as System.Diagnostics.Process;
            Check(player != null, "효과음 재생 시작(afplay)");
            Common.WPF.SoundManager.Stop();
            Check(File.Exists(Path.Combine(AppContext.BaseDirectory, "Assets", "Sounds", "complete.mp3")), "기본 효과음 파일(Assets/Sounds/complete.mp3)");

            // 2) 배경음 미리듣기: upstream BgmPreviewViewModel 그대로
            var logs = new List<string>();
            var vm = app.Dispatcher.Invoke(() => new RomForge.ViewModels.PSP.BgmPreviewViewModel((message, level) => logs.Add($"{level}: {message}")));
            T Ui<T>(Func<T> f) => app.Dispatcher.Invoke(f);

            app.Dispatcher.Invoke(() => vm.Load(wav));
            Check(Math.Abs(Ui(() => vm.DurationSeconds) - 1.5) < 0.05, $"길이 {Ui(() => vm.DurationText)}");
            Thread.Sleep(600);
            Check(Ui(() => vm.IsPlaying) && Ui(() => vm.PositionSeconds) > 0.2, $"재생 중 위치 {Ui(() => vm.PositionSeconds):0.00}s");

            app.Dispatcher.Invoke(() => vm.TogglePlayCommand.Execute(null));
            Thread.Sleep(250);
            double paused = Ui(() => vm.PositionSeconds);
            Thread.Sleep(400);
            Check(!Ui(() => vm.IsPlaying) && Math.Abs(Ui(() => vm.PositionSeconds) - paused) < 0.05, $"일시정지 위치 유지 {paused:0.00}s");

            app.Dispatcher.Invoke(() => vm.PositionSeconds = 1.0);
            app.Dispatcher.Invoke(() => vm.TogglePlayCommand.Execute(null));
            Thread.Sleep(150);
            Check(Ui(() => vm.IsPlaying) && Ui(() => vm.PositionSeconds) >= 0.95, $"이동 후 재생 {Ui(() => vm.PositionSeconds):0.00}s");

            var deadline = DateTime.UtcNow.AddSeconds(3);
            while (Ui(() => vm.IsPlaying) && DateTime.UtcNow < deadline)
                Thread.Sleep(50);
            Check(!Ui(() => vm.IsPlaying) && Ui(() => vm.PositionSeconds) == 0, "끝까지 재생하면 멈추고 처음으로(PlaybackStopped)");

            Check(logs.Count == 0, logs.Count == 0 ? "오류 로그 없음" : string.Join(" / ", logs));
            app.Dispatcher.Invoke(vm.Clear);
        }
        catch (Exception ex)
        {
            Check(false, $"{ex.GetType().Name}: {ex.Message}");
        }
        finally
        {
            File.Delete(file);
        }

        return failures.Count == 0 ? 0 : 1;
    }

    private static byte[] SilentWav(double seconds)
    {
        var format = new NAudio.Wave.WaveFormat(44100, 16, 2);
        var ms = new MemoryStream();

        using (var writer = new NAudio.Wave.WaveFileWriter(ms, format))
        {
            var silence = new byte[(int)(format.AverageBytesPerSecond * seconds) / format.BlockAlign * format.BlockAlign];
            writer.Write(silence, 0, silence.Length);
        }

        return ms.ToArray();
    }

    public static int TestDisks()
    {
        var type = typeof(PickPack.Disk.Helpers.DriveInfos).Assembly.GetType("PickPack.Disk.Helpers.MacDisk")!;
        var list = type.GetMethod("ListWholeDisks", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)!;

        try
        {
            foreach (var disk in (System.Collections.IEnumerable)list.Invoke(null, null)!)
                Console.WriteLine(disk);
            return 0;
        }
        catch (System.Reflection.TargetInvocationException ex)
        {
            Console.WriteLine($"실패: {ex.InnerException}");
            return 1;
        }
    }

    public static int Test7z(string[] args)
    {
        int at = Array.IndexOf(args, "--test-7z");
        string archive = args[at + 1];
        string? password = args.Length > at + 2 ? args[at + 2] : null;
        string outDir = Path.Combine(Path.GetTempPath(), $"rf7z-{Guid.NewGuid():N}");

        try
        {
            using var extractor = new SevenZipExtractor(archive, password);
            Console.WriteLine($"항목 {extractor.FilesCount}개, solid={extractor.IsSolid}");

            foreach (var info in extractor.ArchiveFileData)
                Console.WriteLine($"  [{info.Index}] {(info.IsDirectory ? "<DIR> " : "")}{info.FileName} {info.Size:N0}B crc={info.Crc:X8} enc={info.Encrypted}");

            int lastPercent = -1;
            extractor.Extracting += (_, e) => lastPercent = e.PercentDone;
            extractor.ExtractArchive(outDir);

            var files = Directory.GetFiles(outDir, "*", SearchOption.AllDirectories);
            Console.WriteLine($"압축 해제 성공: 파일 {files.Length}개, 마지막 진행률 {lastPercent}%");

            using var ms = new MemoryStream();
            var first = extractor.ArchiveFileData.First(i => !i.IsDirectory);
            extractor.ExtractFile(first.Index, ms);
            Console.WriteLine($"단일 추출 성공: {first.FileName} {ms.Length:N0}B");
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"실패: {ex.GetType().Name}: {ex.Message}");
            return 1;
        }
        finally
        {
            if (Directory.Exists(outDir))
                Directory.Delete(outDir, true);
        }
    }
}
