namespace PBP.Core.AT3.Models;

public sealed class ScaledBlock
{
    public byte ScaleFactorIndex;

    public float[] Values = Array.Empty<float>();

    public float Energy;
}