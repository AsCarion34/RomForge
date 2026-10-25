namespace PickPack.Disk.Interfaces;

public interface IImageReaderHandler
{
    Task WriteImageAsync(Stream sourceStream, string outputPath, long totalSize, CancellationToken ct);
}