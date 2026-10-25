namespace RomForge.Core.Models.Switch;

public sealed record RenameResult(RenamePlan Plan, bool Success, string? Error);