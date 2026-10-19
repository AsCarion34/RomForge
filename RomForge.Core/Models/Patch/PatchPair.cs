namespace RomForge.Core.Models.Patch;

public class PatchPair
{
    public string  SourcePath  { get; set; } = string.Empty;

    public string  PatchPath   { get; set; } = string.Empty;

    public string  BaseName    { get; set; } = string.Empty;

    public PairStatus Status   { get; set; }
}
