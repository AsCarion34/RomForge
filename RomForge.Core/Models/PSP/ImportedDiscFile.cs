namespace RomForge.Core.Models.PSP;

public record ImportedDiscFile(string Path, string GameId, long Size, byte[]? PresetConfig);