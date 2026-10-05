using System.Globalization;

namespace System.Windows.Data;

// upstream 값 변환기(RomForge/Converters 등)를 macOS 엔진에서 그대로 쓰기 위한 WPF 인터페이스 대체.
// 엔진의 convert 요청이 변환기를 만들어 직접 부른다(BridgeHost.cs).

public interface IValueConverter
{
    object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture);

    object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture);
}

public interface IMultiValueConverter
{
    object? Convert(object?[] values, Type targetType, object? parameter, CultureInfo culture);

    object?[]? ConvertBack(object? value, Type[] targetTypes, object? parameter, CultureInfo culture);
}

public sealed class Binding
{
    /// <summary>변환기가 "값을 바꾸지 않음"을 알릴 때 돌려주는 값.</summary>
    public static readonly object DoNothing = new();
}

[AttributeUsage(AttributeTargets.Class, AllowMultiple = true)]
public sealed class ValueConversionAttribute(Type sourceType, Type targetType) : Attribute
{
    public Type SourceType { get; } = sourceType;
    public Type TargetType { get; } = targetType;
}
