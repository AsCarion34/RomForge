namespace PBP.Core.AT3;

public class At3ConverterOptions
{
    public int BitrateKbps { get; set; } = 132;
    public bool EnableTonal { get; set; } = true;
    public bool EnableGain { get; set; } = true;
    public Action<double>? OnProgress { get; set; }
}