using System.Globalization;

namespace System.Windows.Media;

public struct Color : IEquatable<Color>
{
    public byte A { get; set; }
    public byte R { get; set; }
    public byte G { get; set; }
    public byte B { get; set; }

    public static Color FromRgb(byte r, byte g, byte b) => new() { A = 0xFF, R = r, G = g, B = b };

    public static Color FromArgb(byte a, byte r, byte g, byte b) => new() { A = a, R = r, G = g, B = b };

    public readonly bool Equals(Color other) => A == other.A && R == other.R && G == other.G && B == other.B;

    public override readonly bool Equals(object? obj) => obj is Color c && Equals(c);

    public override readonly int GetHashCode() => HashCode.Combine(A, R, G, B);

    public static bool operator ==(Color left, Color right) => left.Equals(right);

    public static bool operator !=(Color left, Color right) => !left.Equals(right);

    public override readonly string ToString() => $"#{A:X2}{R:X2}{G:X2}{B:X2}";
}

public static class Colors
{
    public static Color Transparent => Color.FromArgb(0x00, 0xFF, 0xFF, 0xFF);
    public static Color Black => Color.FromRgb(0x00, 0x00, 0x00);
    public static Color White => Color.FromRgb(0xFF, 0xFF, 0xFF);
    public static Color Gray => Color.FromRgb(0x80, 0x80, 0x80);
    public static Color DarkGray => Color.FromRgb(0xA9, 0xA9, 0xA9);
    public static Color LightGray => Color.FromRgb(0xD3, 0xD3, 0xD3);
    public static Color Red => Color.FromRgb(0xFF, 0x00, 0x00);
    public static Color Green => Color.FromRgb(0x00, 0x80, 0x00);
    public static Color Blue => Color.FromRgb(0x00, 0x00, 0xFF);
    public static Color Orange => Color.FromRgb(0xFF, 0xA5, 0x00);
    public static Color Yellow => Color.FromRgb(0xFF, 0xFF, 0x00);
    public static Color LimeGreen => Color.FromRgb(0x32, 0xCD, 0x32);
    public static Color Tomato => Color.FromRgb(0xFF, 0x63, 0x47);
    public static Color Gold => Color.FromRgb(0xFF, 0xD7, 0x00);
    public static Color SkyBlue => Color.FromRgb(0x87, 0xCE, 0xEB);
    public static Color Silver => Color.FromRgb(0xC0, 0xC0, 0xC0);
}

public static class ColorConverter
{
    public static object ConvertFromString(string value)
    {
        string s = value.Trim();

        if (!s.StartsWith('#'))
        {
            var prop = typeof(Colors).GetProperty(s, Reflection.BindingFlags.Public | Reflection.BindingFlags.Static | Reflection.BindingFlags.IgnoreCase);

            if (prop?.GetValue(null) is Color named)
                return named;

            throw new FormatException($"알 수 없는 색: {value}");
        }

        string hex = s[1..];

        if (hex.Length is 3 or 4)
            hex = string.Concat(hex.Select(c => new string(c, 2)));

        uint v = uint.Parse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture);

        return hex.Length switch
        {
            6 => Color.FromRgb((byte)(v >> 16), (byte)(v >> 8), (byte)v),
            8 => Color.FromArgb((byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v),
            _ => throw new FormatException($"알 수 없는 색: {value}"),
        };
    }
}

public abstract class Brush : Freezable
{
    public double Opacity { get; set; } = 1.0;
}

public sealed class SolidColorBrush : Brush
{
    public SolidColorBrush() { }

    public SolidColorBrush(Color color) => Color = color;

    public Color Color { get; set; }

    public override string ToString() => Color.ToString();
}

public static class Brushes
{
    private static SolidColorBrush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    public static SolidColorBrush Transparent { get; } = Frozen(Colors.Transparent);
    public static SolidColorBrush Black { get; } = Frozen(Colors.Black);
    public static SolidColorBrush White { get; } = Frozen(Colors.White);
    public static SolidColorBrush Gray { get; } = Frozen(Colors.Gray);
    public static SolidColorBrush DarkGray { get; } = Frozen(Colors.DarkGray);
    public static SolidColorBrush LightGray { get; } = Frozen(Colors.LightGray);
    public static SolidColorBrush Red { get; } = Frozen(Colors.Red);
    public static SolidColorBrush Green { get; } = Frozen(Colors.Green);
    public static SolidColorBrush Blue { get; } = Frozen(Colors.Blue);
    public static SolidColorBrush Orange { get; } = Frozen(Colors.Orange);
    public static SolidColorBrush Yellow { get; } = Frozen(Colors.Yellow);
    public static SolidColorBrush LimeGreen { get; } = Frozen(Colors.LimeGreen);
    public static SolidColorBrush Tomato { get; } = Frozen(Colors.Tomato);
    public static SolidColorBrush Gold { get; } = Frozen(Colors.Gold);
    public static SolidColorBrush SkyBlue { get; } = Frozen(Colors.SkyBlue);
    public static SolidColorBrush Silver { get; } = Frozen(Colors.Silver);
}

public abstract class ImageSource : Freezable
{
    public virtual double Width => 0;

    public virtual double Height => 0;
}

public readonly struct PixelFormat : IEquatable<PixelFormat>
{
    internal PixelFormat(string name, int bitsPerPixel)
    {
        Name = name;
        BitsPerPixel = bitsPerPixel;
    }

    internal string Name { get; }

    public int BitsPerPixel { get; }

    public bool Equals(PixelFormat other) => Name == other.Name;

    public override bool Equals(object? obj) => obj is PixelFormat p && Equals(p);

    public override int GetHashCode() => Name?.GetHashCode() ?? 0;

    public static bool operator ==(PixelFormat left, PixelFormat right) => left.Equals(right);

    public static bool operator !=(PixelFormat left, PixelFormat right) => !left.Equals(right);

    public override string ToString() => Name;
}

public static class PixelFormats
{
    public static PixelFormat Default { get; } = new("Default", 0);
    public static PixelFormat Bgr24 { get; } = new("Bgr24", 24);
    public static PixelFormat Rgb24 { get; } = new("Rgb24", 24);
    public static PixelFormat Bgr32 { get; } = new("Bgr32", 32);
    public static PixelFormat Bgra32 { get; } = new("Bgra32", 32);
    public static PixelFormat Pbgra32 { get; } = new("Pbgra32", 32);
    public static PixelFormat Gray8 { get; } = new("Gray8", 8);
}
