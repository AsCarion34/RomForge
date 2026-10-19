namespace RomForge.Core.Models.PS;

public record ImportedDiscFile(string Path, string GameId, long Size, byte[]? PresetConfig);