using System.Globalization;
using System.Windows.Data;

namespace System.Windows.Controls;

// WPF 기본 제공 변환기 대체(upstream XAML이 리소스로 선언해 쓴다).
public sealed class BooleanToVisibilityConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is true ? Visibility.Visible : Visibility.Collapsed;

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        value is Visibility.Visible;
}
