using SevenZip;

namespace RomForge.Mac.Engine;

/// <summary>
/// 라이브러리 단위 점검(개발·CI용).
///   --test-7z 압축파일 [비밀번호]   SevenZipSharp 대체 구현으로 목록·압축 해제·CRC 확인
///   --test-disks                   PickPack.Disk macOS 구현의 디스크 목록(예외를 그대로 보여 준다)
/// </summary>
internal static class Diagnostics
{
    public static int TestDisks()
    {
        var type = typeof(PickPack.Disk.DriveInfos).Assembly.GetType("PickPack.Disk.ETC.MacDisk")!;
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
