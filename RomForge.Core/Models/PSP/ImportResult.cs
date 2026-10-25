namespace RomForge.Core.Models.PSP;

public record ImportResult(List<ImportedDiscFile> Imported, int OverLimitSkipped, List<ImportFailure> Failures);