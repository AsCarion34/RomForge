using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Processing;
using IsImage = SixLabors.ImageSharp.Image;
using IsBgra32 = SixLabors.ImageSharp.PixelFormats.Bgra32;

// System.Drawing.Common(GDI+)은 .NET 7부터 Windows 전용이다.
// upstream이 쓰는 범위(비트맵 생성·LockBits·확대축소·PNG/JPEG 저장)만 ImageSharp로 구현한다.
// Color, Rectangle 등은 BCL(System.Drawing.Primitives)에 있으므로 여기서 정의하지 않는다.

namespace System.Drawing
{
    public abstract class Image : IDisposable
    {
        internal SixLabors.ImageSharp.Image<IsBgra32> Pixels { get; set; } = null!;

        public int Width => Pixels.Width;

        public int Height => Pixels.Height;

        public PixelFormat PixelFormat { get; protected set; } = PixelFormat.Format32bppArgb;

        public static Image FromStream(Stream stream) => new Bitmap(stream);

        public static Image FromFile(string filename)
        {
            using var fs = File.OpenRead(filename);
            return new Bitmap(fs);
        }

        public void Save(Stream stream, ImageFormat format)
        {
            if (format.Guid == ImageFormat.Jpeg.Guid)
                Pixels.SaveAsJpeg(stream, new JpegEncoder { Quality = 75 });
            else
                Pixels.SaveAsPng(stream);
        }

        public void Save(Stream stream, ImageCodecInfo encoder, EncoderParameters? encoderParams)
        {
            if (encoder.FormatID != ImageFormat.Jpeg.Guid)
            {
                Pixels.SaveAsPng(stream);
                return;
            }

            long quality = 75;

            foreach (var p in encoderParams?.Param ?? [])
            {
                if (p != null && p.Encoder.Guid == Imaging.Encoder.Quality.Guid)
                    quality = p.Value;
            }

            Pixels.SaveAsJpeg(stream, new JpegEncoder { Quality = (int)Math.Clamp(quality, 1, 100) });
        }

        public void Save(string filename, ImageFormat format)
        {
            using var fs = File.Create(filename);
            Save(fs, format);
        }

        public void Dispose()
        {
            Pixels?.Dispose();
            GC.SuppressFinalize(this);
        }
    }

    public sealed class Bitmap : Image
    {
        public Bitmap(int width, int height) : this(width, height, PixelFormat.Format32bppArgb) { }

        public Bitmap(int width, int height, PixelFormat format)
        {
            Pixels = new SixLabors.ImageSharp.Image<IsBgra32>(width, height);
            PixelFormat = format;
        }

        public Bitmap(Stream stream) => Pixels = IsImage.Load<IsBgra32>(stream);

        public Bitmap(string filename) => Pixels = IsImage.Load<IsBgra32>(filename);

        public BitmapData LockBits(Rectangle rect, ImageLockMode flags, PixelFormat format)
        {
            int stride = rect.Width * 4;
            var data = new BitmapData
            {
                Width = rect.Width,
                Height = rect.Height,
                Stride = stride,
                PixelFormat = format,
                Scan0 = Marshal.AllocHGlobal(stride * rect.Height),
                Rect = rect,
                Mode = flags,
            };

            if (flags != ImageLockMode.WriteOnly)
            {
                var buffer = new byte[stride * rect.Height];
                Pixels.ProcessPixelRows(rows =>
                {
                    for (int y = 0; y < rect.Height; y++)
                        MemoryMarshal.AsBytes(rows.GetRowSpan(rect.Y + y).Slice(rect.X, rect.Width)).CopyTo(buffer.AsSpan(y * stride, stride));
                });
                Marshal.Copy(buffer, 0, data.Scan0, buffer.Length);
            }

            return data;
        }

        public void UnlockBits(BitmapData data)
        {
            try
            {
                if (data.Mode == ImageLockMode.ReadOnly)
                    return;

                var buffer = new byte[data.Stride * data.Height];
                Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);

                // Format32bppArgb의 메모리 배치(B,G,R,A)는 ImageSharp Bgra32와 같다.
                Pixels.ProcessPixelRows(rows =>
                {
                    for (int y = 0; y < data.Height; y++)
                        buffer.AsSpan(y * data.Stride, data.Stride).CopyTo(MemoryMarshal.AsBytes(rows.GetRowSpan(data.Rect.Y + y).Slice(data.Rect.X, data.Width)));
                });
            }
            finally
            {
                Marshal.FreeHGlobal(data.Scan0);
                data.Scan0 = IntPtr.Zero;
            }
        }
    }

    public sealed class Graphics : IDisposable
    {
        private readonly Image _target;

        private Graphics(Image target) => _target = target;

        public static Graphics FromImage(Image image) => new(image);

        public CompositingQuality CompositingQuality { get; set; }

        public InterpolationMode InterpolationMode { get; set; }

        public SmoothingMode SmoothingMode { get; set; }

        public PixelOffsetMode PixelOffsetMode { get; set; }

        public void Clear(Color color)
        {
            var fill = new IsBgra32(color.R, color.G, color.B, color.A);
            _target.Pixels.ProcessPixelRows(rows =>
            {
                for (int y = 0; y < rows.Height; y++)
                    rows.GetRowSpan(y).Fill(fill);
            });
        }

        public void DrawImage(Image image, int x, int y, int width, int height)
        {
            using var scaled = image.Pixels.Clone(c => c.Resize(width, height, InterpolationMode is InterpolationMode.NearestNeighbor ? KnownResamplers.NearestNeighbor : KnownResamplers.Bicubic));
            _target.Pixels.Mutate(c => c.DrawImage(scaled, new SixLabors.ImageSharp.Point(x, y), 1f));
        }

        public void DrawImage(Image image, Rectangle rect) => DrawImage(image, rect.X, rect.Y, rect.Width, rect.Height);

        public void DrawImage(Image image, int x, int y) => DrawImage(image, x, y, image.Width, image.Height);

        public void Dispose() { }
    }
}

namespace System.Drawing.Imaging
{
    public enum PixelFormat
    {
        Format24bppRgb = 137224,
        Format32bppRgb = 139273,
        Format32bppArgb = 2498570,
        Format32bppPArgb = 925707,
    }

    public enum ImageLockMode
    {
        ReadOnly = 1,
        WriteOnly = 2,
        ReadWrite = 3,
        UserInputBuffer = 4,
    }

    public sealed class BitmapData
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public int Stride { get; set; }
        public PixelFormat PixelFormat { get; set; }
        public IntPtr Scan0 { get; set; }
        internal Rectangle Rect { get; set; }
        internal ImageLockMode Mode { get; set; }
    }

    public sealed class ImageFormat(Guid guid)
    {
        public Guid Guid { get; } = guid;

        public static ImageFormat Png { get; } = new(new Guid("b96b3caf-0728-11d3-9d7b-0000f81ef32e"));
        public static ImageFormat Jpeg { get; } = new(new Guid("b96b3cae-0728-11d3-9d7b-0000f81ef32e"));
        public static ImageFormat Bmp { get; } = new(new Guid("b96b3cab-0728-11d3-9d7b-0000f81ef32e"));
    }

    public sealed class ImageCodecInfo
    {
        public Guid FormatID { get; init; }
        public string? MimeType { get; init; }

        public static ImageCodecInfo[] GetImageEncoders() =>
        [
            new() { FormatID = ImageFormat.Png.Guid, MimeType = "image/png" },
            new() { FormatID = ImageFormat.Jpeg.Guid, MimeType = "image/jpeg" },
        ];
    }

    public sealed class Encoder(Guid guid)
    {
        public Guid Guid { get; } = guid;

        public static readonly Encoder Quality = new(new Guid("1d5be4b5-fa4a-452d-9cdd-5db35105e7eb"));
    }

    public sealed class EncoderParameter(Encoder encoder, long value)
    {
        public Encoder Encoder { get; } = encoder;
        public long Value { get; } = value;
    }

    public sealed class EncoderParameters(int count) : IDisposable
    {
        public EncoderParameter?[] Param { get; set; } = new EncoderParameter?[count];

        public void Dispose() { }
    }
}

namespace System.Drawing.Drawing2D
{
    public enum CompositingQuality { Invalid = -1, Default = 0, HighSpeed = 1, HighQuality = 2, GammaCorrected = 3, AssumeLinear = 4 }

    public enum InterpolationMode { Invalid = -1, Default = 0, Low = 1, High = 2, Bilinear = 3, Bicubic = 4, NearestNeighbor = 5, HighQualityBilinear = 6, HighQualityBicubic = 7 }

    public enum SmoothingMode { Invalid = -1, Default = 0, HighSpeed = 1, HighQuality = 2, None = 3, AntiAlias = 4 }

    public enum PixelOffsetMode { Invalid = -1, Default = 0, HighSpeed = 1, HighQuality = 2, None = 3, Half = 4 }
}
