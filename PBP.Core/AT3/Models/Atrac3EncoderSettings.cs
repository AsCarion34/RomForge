namespace PBP.Core.AT3.Models;

public sealed class Atrac3EncoderSettings
{
    public uint Bitrate;

    public uint BfuIdxConst;

    public bool NoGainControl = false;

    public bool NoTonalComponents = false;
}