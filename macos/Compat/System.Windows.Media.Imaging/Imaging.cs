using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace System.Windows.Media.Imaging;

public enum BitmapCacheOption
{
    Default = 0,
    OnDemand = 0,
    OnLoad = 1,
    None = 2,
}

[Flags]
public enum BitmapCreateOptions
{
    None = 0,
    PreservePixelFormat = 1,
    DelayCreation = 2,
    IgnoreColorProfile = 4,
    IgnoreImageCache = 8,
}

public sealed class BitmapPalette { }

/// <summary>
/// 화면에 그리지 않으므로 이미지를 "인코딩된 바이트(PNG 등)" 또는 "원시 픽셀"로만 들고 있다.
/// SwiftUI 쪽으로 보낼 때는 <see cref="GetEncodedBytes"/>로 PNG 등을 얻는다.
/// pack:// 리소스는 바이트 대신 <see cref="AssetUri"/>만 기록해 두고 앱 번들의 같은 이름 이미지를 쓴다.
/// </summary>
public class BitmapSource : ImageSource
{
    private byte[]? _encoded;

    internal byte[]? EncodedBytes
    {
        get => _encoded;
        set => _encoded = value;
    }

    internal Array? Pixels { get; set; }

    internal int Stride { get; set; }

    public string? AssetUri { get; protected set; }

    public int PixelWidth { get; protected set; }

    public int PixelHeight { get; protected set; }

    public double DpiX { get; protected set; } = 96;

    public double DpiY { get; protected set; } = 96;

    public PixelFormat Format { get; protected set; } = PixelFormats.Default;

    public override double Width => PixelWidth;

    public override double Height => PixelHeight;

    public static BitmapSource Create(int pixelWidth, int pixelHeight, double dpiX, double dpiY, PixelFormat pixelFormat, BitmapPalette? palette, Array pixels, int stride) => new()
    {
        PixelWidth = pixelWidth,
        PixelHeight = pixelHeight,
        DpiX = dpiX,
        DpiY = dpiY,
        Format = pixelFormat,
        Pixels = pixels,
        Stride = stride,
    };

    /// <summary>PNG/JPEG 등 인코딩된 이미지 바이트. 원시 픽셀이면 PNG로 인코딩한다.</summary>
    public byte[]? GetEncodedBytes()
    {
        if (_encoded != null)
            return _encoded;

        if (Pixels is not byte[] raw || PixelWidth <= 0 || PixelHeight <= 0)
            return null;

        using var image = new Image<Bgra32>(PixelWidth, PixelHeight);
        int bpp = Format.BitsPerPixel / 8;

        image.ProcessPixelRows(rows =>
        {
            for (int y = 0; y < rows.Height; y++)
            {
                var row = rows.GetRowSpan(y);
                int offset = y * Stride;

                for (int x = 0; x < rows.Width; x++)
                {
                    int i = offset + x * bpp;
                    byte b = raw[i], g = raw[i + 1], r = raw[i + 2];
                    byte a = Format == PixelFormats.Bgra32 || Format == PixelFormats.Pbgra32 ? raw[i + 3] : (byte)0xFF;
                    row[x] = new Bgra32(r, g, b, a);
                }
            }
        });

        using var ms = new MemoryStream();
        image.SaveAsPng(ms);
        _encoded = ms.ToArray();
        return _encoded;
    }

    protected void ReadSize(byte[] bytes)
    {
        try
        {
            var info = Image.Identify(bytes);
            PixelWidth = info.Width;
            PixelHeight = info.Height;
        }
        catch
        {
            // 크기를 몰라도 표시에는 문제없다.
        }
    }
}

public sealed class BitmapImage : BitmapSource
{
    public BitmapImage() { }

    public BitmapImage(Uri uriSource)
    {
        UriSource = uriSource;
        Load();
    }

    public Uri? UriSource { get; set; }

    public Stream? StreamSource { get; set; }

    public BitmapCacheOption CacheOption { get; set; }

    public BitmapCreateOptions CreateOptions { get; set; }

    public int DecodePixelWidth { get; set; }

    public int DecodePixelHeight { get; set; }

    public void BeginInit() { }

    public void EndInit() => Load();

    private void Load()
    {
        if (StreamSource != null)
        {
            using var ms = new MemoryStream();

            if (StreamSource.CanSeek)
                StreamSource.Position = 0;

            StreamSource.CopyTo(ms);
            EncodedBytes = ms.ToArray();
            ReadSize(EncodedBytes);
            return;
        }

        if (UriSource == null)
            return;

        if (UriSource.IsAbsoluteUri && UriSource.Scheme == "pack")
        {
            AssetUri = UriSource.OriginalString;
            return;
        }

        string path = UriSource.IsAbsoluteUri ? UriSource.LocalPath : UriSource.OriginalString;

        if (File.Exists(path))
        {
            EncodedBytes = File.ReadAllBytes(path);
            ReadSize(EncodedBytes);
        }
        else
        {
            AssetUri = UriSource.OriginalString;
        }
    }
}

public sealed class BitmapFrame : BitmapSource
{
    public static BitmapFrame Create(BitmapSource source)
    {
        var frame = new BitmapFrame
        {
            PixelWidth = source.PixelWidth,
            PixelHeight = source.PixelHeight,
            Format = source.Format,
        };

        frame.EncodedBytes = source.GetEncodedBytes();
        return frame;
    }

    internal static BitmapFrame FromEncoded(byte[] bytes)
    {
        var frame = new BitmapFrame { EncodedBytes = bytes };
        frame.ReadSize(bytes);
        return frame;
    }
}

public abstract class BitmapDecoder
{
    public IList<BitmapFrame> Frames { get; } = new List<BitmapFrame>();

    public static BitmapDecoder Create(Stream bitmapStream, BitmapCreateOptions createOptions, BitmapCacheOption cacheOption)
    {
        using var ms = new MemoryStream();
        bitmapStream.CopyTo(ms);

        var decoder = new EncodedBitmapDecoder();
        decoder.Frames.Add(BitmapFrame.FromEncoded(ms.ToArray()));
        return decoder;
    }

    private sealed class EncodedBitmapDecoder : BitmapDecoder { }
}

public abstract class BitmapEncoder
{
    public IList<BitmapFrame> Frames { get; } = new List<BitmapFrame>();

    public abstract void Save(Stream stream);
}

public sealed class PngBitmapEncoder : BitmapEncoder
{
    public override void Save(Stream stream)
    {
        if (Frames.Count == 0)
            throw new InvalidOperationException("저장할 프레임이 없습니다.");

        byte[] bytes = Frames[0].GetEncodedBytes() ?? throw new InvalidOperationException("이미지 데이터가 없습니다.");

        // 원본이 PNG가 아니면 PNG로 바꿔 저장한다.
        if (bytes.Length < 8 || bytes[0] != 0x89 || bytes[1] != 0x50)
        {
            using var image = Image.Load(bytes);
            image.SaveAsPng(stream);
            return;
        }

        stream.Write(bytes);
    }
}
