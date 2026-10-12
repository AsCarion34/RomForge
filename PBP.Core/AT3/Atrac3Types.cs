using System;
using System.Collections.Generic;

namespace PBP.Core.AT3;

public readonly record struct GainPoint(uint Level, uint Location);

public struct GainEnergyScale
{
    public float PrevHalf;
    public float CurHalf;
    public float Frame;

    public static GainEnergyScale Identity => new() { PrevHalf = 1.0f, CurHalf = 1.0f, Frame = 1.0f };
}

public sealed class SubbandInfo
{
    public const int MaxGainPointsNum = 8;

    public List<GainPoint>[] Info;

    public SubbandInfo()
    {
        Info = NewInfo(4);
    }

    private static List<GainPoint>[] NewInfo(int n)
    {
        var info = new List<GainPoint>[n];
        for (int i = 0; i < n; i++)
            info[i] = new List<GainPoint>();
        return info;
    }

    public void ResizeBands(int n)
    {
        var info = NewInfo(n);
        for (int i = 0; i < Math.Min(n, Info.Length); i++)
            info[i] = Info[i];
        Info = info;
    }

    public int GetQmfNum() => Info.Length;

    public List<GainPoint> GetGainPoints(int band) => Info[band];

    public void Reset()
    {
        foreach (var v in Info)
            v.Clear();
    }
}

public readonly record struct TonalVal(ushort Pos, double Val, byte Bfu);

public sealed class TonalBlock
{
    public TonalVal Val;
    public ScaledBlock ScaledBlock = new();
}

public sealed class SingleChannelElement
{
    public SubbandInfo SubbandInfo = new();
    public List<TonalBlock> TonalBlocks = new();
    public List<ScaledBlock> ScaledBlocks = new();
    public float Loudness;
    public GainEnergyScale[] GainEnergyScale =
    {
        AT3.GainEnergyScale.Identity, AT3.GainEnergyScale.Identity,
        AT3.GainEnergyScale.Identity, AT3.GainEnergyScale.Identity
    };
}
