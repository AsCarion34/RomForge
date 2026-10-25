namespace RomForge.Core.Models.Switch;

public sealed record RenamePlan(string SourcePath, string TargetPath, string OldName, string NewName, RenameState State);