namespace PickPack.Disk.Interfaces;

public interface IImageWriteHandler
{
    Task<(Stream stream, long length)> OpenStreamAsync(string imagePath, CancellationToken ct);
}