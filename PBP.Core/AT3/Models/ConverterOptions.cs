namespace PBP.Core.AT3.Models;

public class ConverterOptions
{
    public At3Bitrate BitrateKbps { get; set; } = At3Bitrate.Kbps132;

    public int MaxSeconds { get; set; } = 30;

    public bool EnableTonal { get; set; } = true;

    public bool EnableGain { get; set; } = true;

    public Action<double>? OnProgress { get; set; }
}