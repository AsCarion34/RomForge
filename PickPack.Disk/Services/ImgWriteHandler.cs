using PickPack.Disk.Interfaces;
using PickPack.Disk.Models;

namespace PickPack.Disk.Services;

public class ImgWriteHandler : IImageWriteHandler
{
    public async Task<(Stream stream, long length)> OpenStreamAsync(string imagePath, CancellationToken ct)
    {
        await Task.Yield();

        var stream = new FileStream(imagePath, FileMode.Open, FileAccess.Read, FileShare.Read, Optimal.BufferSize * 2, FileOptions.SequentialScan);

        return (stream, stream.Length);
    }
}