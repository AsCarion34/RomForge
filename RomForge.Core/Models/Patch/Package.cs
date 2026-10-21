namespace RomForge.Core.Models.Patch;

public class Package
{
    public string DisplayName { get; init; } = string.Empty;

    public string DatFileName { get; init; } = string.Empty;

    public List<PackageEntry> Entries { get; init; } = [];
}