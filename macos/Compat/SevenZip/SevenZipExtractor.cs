using System.Collections.ObjectModel;
using System.IO.Hashing;
using SharpCompress.Archives;
using SharpCompress.Archives.SevenZip;
using SharpCompress.Common;
using SharpCompress.Readers;

namespace SevenZip;

// SevenZipSharp(Windows 7z.dll을 COM으로 부르는 NuGet) 대체. upstream이 쓰는 범위를 SharpCompress로 구현한다.
// - 분할 볼륨(.7z.001, .002 …)은 첫 파일을 열면 나머지를 함께 연다(7z.dll과 같은 동작).
// - 압축 해제한 데이터는 CRC32로 확인한다. 틀린 비밀번호로 잘못된 데이터가 조용히 써지지 않게 하고,
//   upstream이 예외를 "비밀번호 필요"로 처리하는 흐름(SevenZipArchivePatchSource)을 그대로 따른다.

public struct ArchiveFileInfo
{
    public int Index { get; set; }
    public string FileName { get; set; }
    public ulong Size { get; set; }
    public uint Crc { get; set; }
    public bool IsDirectory { get; set; }
    public bool Encrypted { get; set; }
    public DateTime LastWriteTime { get; set; }
    public DateTime CreationTime { get; set; }
    public DateTime LastAccessTime { get; set; }

    public override readonly string ToString() => FileName;
}

public sealed class ProgressEventArgs(byte percentDone, byte percentDelta) : EventArgs
{
    public byte PercentDone { get; } = percentDone;
    public byte PercentDelta { get; } = percentDelta;
    public bool Cancel { get; set; }
}

public class SevenZipException(string message, Exception? inner = null) : Exception(message, inner);

public sealed class SevenZipArchiveException(string message, Exception? inner = null) : SevenZipException(message, inner);

public sealed class ExtractionFailedException(string message, Exception? inner = null) : SevenZipException(message, inner);

public abstract class SevenZipBase
{
    /// <summary>Windows 7z.dll 경로 지정. macOS에서는 쓰지 않는다.</summary>
    public static void SetLibraryPath(string libraryPath) { }
}

public sealed class SevenZipExtractor : SevenZipBase, IDisposable
{
    private readonly IArchive _archive;
    private readonly List<IArchiveEntry> _entries;
    private byte _lastPercent;

    public SevenZipExtractor(string archiveFullName) : this(archiveFullName, null) { }

    public SevenZipExtractor(string archiveFullName, string? password)
    {
        try
        {
            var options = new ReaderOptions { Password = string.IsNullOrEmpty(password) ? null : password };
            var parts = VolumeParts(archiveFullName);

            _archive = parts.Count > 1
                ? SevenZipArchive.OpenArchive(parts.Select(p => new FileInfo(p)).ToList(), options)
                : SevenZipArchive.OpenArchive(archiveFullName, options);

            _entries = [.. _archive.Entries];
        }
        catch (Exception ex) when (ex is not SevenZipException)
        {
            throw new SevenZipArchiveException($"7z 파일을 열 수 없습니다: {Path.GetFileName(archiveFullName)} ({ex.Message})", ex);
        }

        ArchiveFileData = new ReadOnlyCollection<ArchiveFileInfo>([.. _entries.Select((e, i) => new ArchiveFileInfo
        {
            Index = i,
            FileName = e.Key ?? string.Empty,
            Size = (ulong)Math.Max(0, e.Size),
            Crc = (uint)e.Crc,
            IsDirectory = e.IsDirectory,
            Encrypted = e.IsEncrypted,
            LastWriteTime = e.LastModifiedTime ?? DateTime.MinValue,
            CreationTime = e.CreatedTime ?? DateTime.MinValue,
            LastAccessTime = e.LastAccessedTime ?? DateTime.MinValue,
        })]);
    }

    public event EventHandler<ProgressEventArgs>? Extracting;

    public ReadOnlyCollection<ArchiveFileInfo> ArchiveFileData { get; }

    public uint FilesCount => (uint)ArchiveFileData.Count;

    public bool IsSolid => _archive.IsSolid;

    public void ExtractArchive(string directory) =>
        ExtractFiles(directory, [.. ArchiveFileData.Select(i => i.Index)]);

    public void ExtractFiles(string directory, params int[] indexes)
    {
        var wanted = indexes.Select(i => _entries[i]).Where(e => !e.IsDirectory).Select(e => e.Key ?? string.Empty).ToHashSet(StringComparer.Ordinal);
        long total = indexes.Sum(i => _entries[i].IsDirectory ? 0 : Math.Max(0, _entries[i].Size));
        long done = 0;

        foreach (int i in indexes.Where(i => _entries[i].IsDirectory))
            Directory.CreateDirectory(SafeCombine(directory, _entries[i].Key ?? string.Empty));

        try
        {
            // solid 압축은 앞에서부터 풀어야 하므로 순차 읽기로 한 번에 처리한다.
            using var reader = _archive.ExtractAllEntries();

            while (reader.MoveToNextEntry())
            {
                var entry = reader.Entry;

                if (entry.IsDirectory || !wanted.Contains(entry.Key ?? string.Empty))
                    continue;

                string target = SafeCombine(directory, entry.Key ?? string.Empty);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);

                using (var file = File.Create(target))
                using (var checking = new CrcCheckingStream(file))
                {
                    reader.WriteEntryTo(checking);
                    checking.Verify(entry);
                }

                done += Math.Max(0, entry.Size);
                Report(done, total);
            }
        }
        catch (Exception ex) when (ex is not SevenZipException && ex is not OperationCanceledException)
        {
            throw new ExtractionFailedException($"압축 해제 실패: {ex.Message}", ex);
        }

        Report(total, total);
    }

    public void ExtractFile(int index, Stream stream)
    {
        var entry = _entries[index];

        try
        {
            using var source = entry.OpenEntryStream();
            var checking = new CrcCheckingStream(stream);
            source.CopyTo(checking);
            checking.Verify(entry);
        }
        catch (Exception ex) when (ex is not SevenZipException && ex is not OperationCanceledException)
        {
            throw new ExtractionFailedException($"압축 해제 실패: {ex.Message}", ex);
        }

        Report(1, 1);
    }

    public void ExtractFile(string fileName, Stream stream)
    {
        int index = _entries.FindIndex(e => string.Equals(e.Key, fileName.Replace('\\', '/'), StringComparison.OrdinalIgnoreCase));

        if (index < 0)
            throw new SevenZipArchiveException($"압축 파일에 없는 항목입니다: {fileName}");

        ExtractFile(index, stream);
    }

    public void Dispose() => _archive.Dispose();

    private void Report(long done, long total)
    {
        byte percent = (byte)(total <= 0 ? 100 : Math.Min(100, done * 100 / total));

        if (percent == _lastPercent && percent != 100)
            return;

        byte delta = (byte)Math.Max(0, percent - _lastPercent);
        _lastPercent = percent;
        Extracting?.Invoke(this, new ProgressEventArgs(percent, delta));
    }

    private static string SafeCombine(string directory, string key)
    {
        string root = Path.GetFullPath(directory);
        string full = Path.GetFullPath(Path.Combine(root, key.Replace('\\', '/')));

        if (!full.StartsWith(root.TrimEnd('/') + "/", StringComparison.Ordinal) && full != root)
            throw new SevenZipArchiveException($"압축 파일 밖을 가리키는 경로입니다: {key}");

        return full;
    }

    /// <summary>"x.7z.001"이면 같은 폴더의 .001, .002 … 를 순서대로 돌려준다.</summary>
    private static List<string> VolumeParts(string path)
    {
        string name = Path.GetFileName(path);
        int dot = name.LastIndexOf('.');

        if (dot < 0 || !name[(dot + 1)..].All(char.IsAsciiDigit) || name.Length - dot - 1 < 3)
            return [path];

        string dir = Path.GetDirectoryName(Path.GetFullPath(path))!;
        string stem = name[..dot];
        int width = name.Length - dot - 1;
        var parts = new List<string>();

        for (int n = 1; ; n++)
        {
            string part = Path.Combine(dir, $"{stem}.{n.ToString().PadLeft(width, '0')}");
            if (!File.Exists(part))
                break;
            parts.Add(part);
        }

        return parts.Count > 0 ? parts : [path];
    }

    /// <summary>쓰면서 CRC32를 계산하고, 끝나면 압축 파일에 기록된 값과 비교한다.</summary>
    private sealed class CrcCheckingStream(Stream inner) : Stream
    {
        private readonly Crc32 _crc = new();
        private long _length;

        public void Verify(IEntry entry)
        {
            if (entry.Crc == 0 && entry.Size != 0)
                return; // CRC가 기록되지 않은 항목

            uint actual = _crc.GetCurrentHashAsUInt32();

            if (_length != entry.Size || actual != (uint)entry.Crc)
                throw new ExtractionFailedException($"데이터 확인 실패({entry.Key}): 비밀번호가 틀렸거나 압축 파일이 손상되었습니다.");
        }

        public override void Write(byte[] buffer, int offset, int count) => Write(buffer.AsSpan(offset, count));

        public override void Write(ReadOnlySpan<byte> buffer)
        {
            _crc.Append(buffer);
            _length += buffer.Length;
            inner.Write(buffer);
        }

        public override void Flush() => inner.Flush();
        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => _length;
        public override long Position { get => _length; set => throw new NotSupportedException(); }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
    }
}
