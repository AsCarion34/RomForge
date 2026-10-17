using Common;

namespace NSW.M1.Core.Models;

public class ProgressContext(long totalSize)
{
    public long TotalSize { get; } = totalSize;

    public ProgressReporter Reporter { get; set; } = new(string.Empty, string.Empty, totalSize, null);
}
