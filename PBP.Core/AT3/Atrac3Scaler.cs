using System;
using System.Collections.Generic;

namespace PBP.Core.AT3;

public sealed class ScaledBlock
{
    public byte ScaleFactorIndex;
    public float[] Values = Array.Empty<float>();
    public float Energy;
}

public static class Atrac3Scaler
{
    private const float MaxScale = 1.0f;

    public static ScaledBlock Scale(ReadOnlySpan<float> input)
    {
        float maxAbsSpec = 0;
        for (int i = 0; i < input.Length; ++i)
        {
            float absSpec = MathF.Abs(input[i]);
            if (absSpec > maxAbsSpec)
                maxAbsSpec = absSpec;
        }
        if (maxAbsSpec > MaxScale)
            maxAbsSpec = MaxScale;

        float[] table = Atrac3Data.ScaleTable;
        int idx = LowerBound(table, maxAbsSpec);
        float scaleFactor = table[idx];

        var res = new ScaledBlock
        {
            ScaleFactorIndex = (byte)idx,
            Values = new float[input.Length],
            Energy = 0.0f
        };

        for (int i = 0; i < input.Length; ++i)
        {
            float scaledValue = input[i] / scaleFactor;
            float energy = input[i] * input[i];
            res.Energy += energy;
            if (Math.Abs(scaledValue) >= 1.0)
                scaledValue = (scaledValue > 0) ? (float)0.99999 : (float)-0.99999;
            res.Values[i] = scaledValue;
        }
        return res;
    }

    public static List<ScaledBlock> ScaleFrame(ReadOnlySpan<float> specs)
    {
        var blocks = new List<ScaledBlock>(Atrac3Data.MaxBfus);
        for (int band = 0; band < Atrac3Data.NumQmf; ++band)
        {
            for (int block = Atrac3Data.BlocksPerBand[band]; block < Atrac3Data.BlocksPerBand[band + 1]; ++block)
            {
                int start = Atrac3Data.BlockSizeTab[block];
                int len = Atrac3Data.SpecsPerBlock[block];
                blocks.Add(Scale(specs.Slice(start, len)));
            }
        }
        return blocks;
    }

    private static int LowerBound(float[] table, float value)
    {
        int lo = 0;
        int hi = table.Length - 1;
        while (lo < hi)
        {
            int mid = (lo + hi) >> 1;
            if (table[mid] < value)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo;
    }
}
