namespace RomForge.Core.Models.PS;

public record ImportResult(List<ImportedDiscFile> Imported, int OverLimitSkipped, List<ImportFailure> Failures);