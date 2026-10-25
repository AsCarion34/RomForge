namespace Common;

public static class ProgressInfoExtensions
{
    public static void ReportStatus(this IProgress<ProgressInfo>? progress, string label, int percent = -1) =>　progress?.Report(new ProgressInfo(percent, label, string.Empty, string.Empty, string.Empty));
}