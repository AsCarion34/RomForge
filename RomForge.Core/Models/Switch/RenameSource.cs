namespace RomForge.Core.Models.Switch;

public sealed record RenameSource(string FilePath, string? Name, string? KoreanTitleName, string? TitleName, string? TitleId, string? Tag, string? DisplayVersion, string? Version, bool HasMetadata);