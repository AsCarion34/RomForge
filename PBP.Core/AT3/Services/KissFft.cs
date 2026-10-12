namespace PBP.Core.AT3.Services;

internal sealed class KissFft
{
    private readonly int _nfft;
    private readonly float[] _twr;
    private readonly float[] _twi;
    private readonly int[] _factors;
    private readonly bool _inverse;

    public KissFft(int nfft, bool inverse = false)
    {
        if (nfft < 2 || (nfft & (nfft - 1)) != 0)
            throw new ArgumentException("FFT size must be a power of two", nameof(nfft));

        _nfft = nfft;
        _inverse = inverse;
        _twr = new float[nfft];
        _twi = new float[nfft];

        for (int i = 0; i < nfft; i++)
        {
            double phase = -2 * Math.PI * i / nfft;

            if (inverse)
                phase *= -1;

            _twr[i] = (float)Math.Cos(phase);
            _twi[i] = (float)Math.Sin(phase);
        }

        _factors = Factor(nfft);
    }

    private static int[] Factor(int n)
    {
        var list = new System.Collections.Generic.List<int>();
        int p = 4;

        do
        {
            while (n % p != 0)
                p = p == 4 ? 2 : throw new InvalidOperationException();
            n /= p;
            list.Add(p);
            list.Add(n);
        } while (n > 1);

        return [.. list];
    }

    public void Transform(float[] fin, float[] fout)
    {
        if (ReferenceEquals(fin, fout))
            throw new ArgumentException("In-place transform is not supported");

        Work(fout, 0, fin, 0, 1, 1, 0);
    }

    private void Work(float[] fout, int foutIdx, float[] fin, int finIdx, int fstride, int inStride, int fi)
    {
        int p = _factors[fi++];
        int m = _factors[fi++];
        int begin = foutIdx;
        int end = foutIdx + p * m;

        if (m == 1)
        {
            do
            {
                fout[2 * foutIdx] = fin[2 * finIdx];
                fout[2 * foutIdx + 1] = fin[2 * finIdx + 1];
                finIdx += fstride * inStride;
            } while (++foutIdx != end);
        }
        else
        {
            do
            {
                Work(fout, foutIdx, fin, finIdx, fstride * p, inStride, fi);
                finIdx += fstride * inStride;
            } while ((foutIdx += m) != end);
        }

        if (p == 2)
            Bfly2(fout, begin, fstride, m);
        else
            Bfly4(fout, begin, fstride, m);
    }

    private void Bfly2(float[] f, int idx, int fstride, int m)
    {
        int f2 = idx + m;
        int tw = 0;

        do
        {
            float f2r = f[2 * f2];
            float f2i = f[2 * f2 + 1];
            float tr = f2r * _twr[tw] - f2i * _twi[tw];
            float ti = f2r * _twi[tw] + f2i * _twr[tw];
            tw += fstride;
            f[2 * f2] = f[2 * idx] - tr;
            f[2 * f2 + 1] = f[2 * idx + 1] - ti;
            f[2 * idx] += tr;
            f[2 * idx + 1] += ti;
            f2++;
            idx++;
        } while (--m != 0);
    }

    private void Bfly4(float[] f, int idx, int fstride, int m)
    {
        int k = m;
        int m2 = 2 * m;
        int m3 = 3 * m;
        int tw1 = 0, tw2 = 0, tw3 = 0;

        do
        {
            int a = 2 * (idx + m);
            int b = 2 * (idx + m2);
            int c = 2 * (idx + m3);
            int o = 2 * idx;
            float s0r = f[a] * _twr[tw1] - f[a + 1] * _twi[tw1];
            float s0i = f[a] * _twi[tw1] + f[a + 1] * _twr[tw1];
            float s1r = f[b] * _twr[tw2] - f[b + 1] * _twi[tw2];
            float s1i = f[b] * _twi[tw2] + f[b + 1] * _twr[tw2];
            float s2r = f[c] * _twr[tw3] - f[c + 1] * _twi[tw3];
            float s2i = f[c] * _twi[tw3] + f[c + 1] * _twr[tw3];
            float s5r = f[o] - s1r;
            float s5i = f[o + 1] - s1i;

            f[o] += s1r;
            f[o + 1] += s1i;

            float s3r = s0r + s2r;
            float s3i = s0i + s2i;
            float s4r = s0r - s2r;
            float s4i = s0i - s2i;

            f[b] = f[o] - s3r;
            f[b + 1] = f[o + 1] - s3i;
            tw1 += fstride;
            tw2 += fstride * 2;
            tw3 += fstride * 3;
            f[o] += s3r;
            f[o + 1] += s3i;

            if (_inverse)
            {
                f[a] = s5r - s4i;
                f[a + 1] = s5i + s4r;
                f[c] = s5r + s4i;
                f[c + 1] = s5i - s4r;
            }
            else
            {
                f[a] = s5r + s4i;
                f[a + 1] = s5i - s4r;
                f[c] = s5r - s4i;
                f[c + 1] = s5i + s4r;
            }

            idx++;
        } while (--k != 0);
    }
}