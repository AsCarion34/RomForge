using System;

namespace PBP.Core.AT3;

public abstract class MdctBase
{
    protected readonly int N;
    protected readonly float[] SinCos;
    protected readonly float[] FftIn;
    protected readonly float[] FftOut;
    private readonly KissFft _fft;

    protected MdctBase(int n, float scale)
    {
        N = n;
        SinCos = CalcSinCos(n, scale);
        FftIn = new float[n >> 1];
        FftOut = new float[n >> 1];
        _fft = new KissFft(n >> 2);
    }

    private static float[] CalcSinCos(int n, float scale)
    {
        var tmp = new float[n >> 1];
        float alpha = (float)(2.0 * Math.PI / (8.0 * n));
        float omiga = (float)(2.0 * Math.PI / n);
        scale = (float)Math.Sqrt(scale / n);
        for (int i = 0; i < (n >> 2); ++i)
        {
            float arg = omiga * i + alpha;
            tmp[2 * i + 0] = scale * MathF.Cos(arg);
            tmp[2 * i + 1] = scale * MathF.Sin(arg);
        }
        return tmp;
    }

    protected void RunFft() => _fft.Transform(FftIn, FftOut);
}

public sealed class Mdct : MdctBase
{
    public int InputSize => N;
    public int OutputSize => N >> 1;

    public Mdct(int n, float scale = 1.0f) : base(n, scale)
    {
    }

    public void Transform(ReadOnlySpan<float> input, Span<float> output)
    {
        int n2 = N >> 1;
        int n4 = N >> 2;
        int n34 = 3 * n4;
        int n54 = 5 * n4;
        float[] sc = SinCos;
        float[] fi = FftIn;
        int n;

        for (n = 0; n < n4; n += 2)
        {
            float r0 = input[n34 - 1 - n] + input[n34 + n];
            float i0 = input[n4 + n] - input[n4 - 1 - n];
            float c = sc[n];
            float s = sc[n + 1];
            fi[n] = r0 * c + i0 * s;
            fi[n + 1] = i0 * c - r0 * s;
        }

        for (; n < n2; n += 2)
        {
            float r0 = input[n34 - 1 - n] - input[n - n4];
            float i0 = input[n4 + n] + input[n54 - 1 - n];
            float c = sc[n];
            float s = sc[n + 1];
            fi[n] = r0 * c + i0 * s;
            fi[n + 1] = i0 * c - r0 * s;
        }

        RunFft();

        float[] fo = FftOut;
        for (n = 0; n < n2; n += 2)
        {
            float r0 = fo[n];
            float i0 = fo[n + 1];
            float c = sc[n];
            float s = sc[n + 1];
            output[n] = -r0 * c - i0 * s;
            output[n2 - 1 - n] = -r0 * s + i0 * c;
        }
    }
}

public sealed class Midct : MdctBase
{
    public int InputSize => N >> 1;
    public int OutputSize => N;

    public Midct(int n, float? scale = null) : base(n, (scale ?? n) / 2)
    {
    }

    public void Transform(ReadOnlySpan<float> input, Span<float> output)
    {
        int n2 = N >> 1;
        int n4 = N >> 2;
        int n34 = 3 * n4;
        int n54 = 5 * n4;
        float[] sc = SinCos;
        float[] fi = FftIn;
        int n;

        for (n = 0; n < n2; n += 2)
        {
            float r0 = input[n];
            float i0 = input[n2 - 1 - n];
            float c = sc[n];
            float s = sc[n + 1];
            fi[n] = -2.0f * (i0 * s + r0 * c);
            fi[n + 1] = -2.0f * (i0 * c - r0 * s);
        }

        RunFft();

        float[] fo = FftOut;
        for (n = 0; n < n4; n += 2)
        {
            float r0 = fo[n];
            float i0 = fo[n + 1];
            float c = sc[n];
            float s = sc[n + 1];
            float r1 = r0 * c + i0 * s;
            float i1 = r0 * s - i0 * c;
            output[n34 - 1 - n] = r1;
            output[n34 + n] = r1;
            output[n4 + n] = i1;
            output[n4 - 1 - n] = -i1;
        }

        for (; n < n2; n += 2)
        {
            float r0 = fo[n];
            float i0 = fo[n + 1];
            float c = sc[n];
            float s = sc[n + 1];
            float r1 = r0 * c + i0 * s;
            float i1 = r0 * s - i0 * c;
            output[n34 - 1 - n] = r1;
            output[n - n4] = -r1;
            output[n4 + n] = i1;
            output[n54 - 1 - n] = i1;
        }
    }
}
