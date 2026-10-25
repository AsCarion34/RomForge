namespace RomForge.Core.Models.Patch;

public sealed record NamingFormatPreset(string Name, string? Format)
{
    public bool IsCustom => Format is null && !IsSeparator;

    public bool IsSeparator { get; init; }

    public static NamingFormatPreset Separator { get; } = new(string.Empty, null) { IsSeparator = true };
}