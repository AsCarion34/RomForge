using RomForge.Core.Models.Patch;
using System.IO;

namespace RomForge.Core.Services.Patch;

public static class RomHasher
{
    private const int CopyBufferSize = 1024 * 1024;

    public static Task<RomHashResult> HashFileAsync(string path, IProgress<double>? progress, CancellationToken ct) =>
        Task.Run(() =>
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.SequentialScan);
            return HashStream(fs, fs.Length, progress, ct);
        }, ct);

    public static RomHashResult HashStream(Stream source, long totalBytes, IProgress<double>? progress, CancellationToken ct)
    {
        using var sink = new RomHashSink(totalBytes, progress, ct);

        source.CopyTo(sink, CopyBufferSize);

        return sink.Complete();
    }
}