using RomForge.Core.Models._3DS;

namespace RomForge.Core.Services._3DS;

public static class RepackOutputFormatExtensions
{
    public static string ToFileExtension(this RepackOutputFormat format) => format switch
    {
        RepackOutputFormat.Cia => ".cia",
        RepackOutputFormat.Zcci => ".zcci",
        RepackOutputFormat.Cci => ".cci",
        _ => throw new NotSupportedException($"지원하지 않는 포맷: {format}"),
    };
}