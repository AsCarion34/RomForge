using RomForge.Core.Models.CD;
using System.Globalization;
using System.Windows.Data;

namespace RomForge.Converters;

public class CdOutputFormatLabelConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture) => value switch
    {
        OutputFormat.Iso => "ISO",
        OutputFormat.BinCue => "CUE",
        _ => value?.ToString() ?? string.Empty
    };

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}