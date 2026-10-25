namespace RomForge.Core.Models.Switch;

public sealed record PatchMatch(string? Path, IReadOnlyList<string> Covered, IReadOnlyList<string> Missing);