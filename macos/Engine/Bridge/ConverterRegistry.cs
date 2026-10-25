using System.Reflection;
using System.Windows.Data;

namespace RomForge.Mac.Engine.Bridge;

/// <summary>
/// upstream 값 변환기(RomForge.Converters, Common.WPF.Converters, NSW.WPF.Converters)를 이름으로 찾아 만든다.
/// XAML에서 쓰는 리소스 키(예: "InverseBool" → InverseBoolConverter)도 받는다.
/// </summary>
internal static class ConverterRegistry
{
    // XAML x:Key → 변환기 클래스 이름 (upstream XAML 리소스 선언과 같게 유지)
    private static readonly Dictionary<string, string> Aliases = new(StringComparer.Ordinal)
    {
        ["InverseBool"] = "InverseBoolConverter",
        ["LogColor"] = "LogLevelToColorConverter",
        ["LanguageLabelConverter"] = "Locale3dsLanguageToLabelConverter",
    };

    private static readonly Dictionary<string, object> Instances = new(StringComparer.Ordinal);
    private static Dictionary<string, Type>? _types;

    public static object Get(string name)
    {
        string typeName = Aliases.GetValueOrDefault(name, name);

        lock (Instances)
        {
            if (Instances.TryGetValue(typeName, out var existing))
                return existing;

            var type = Types().GetValueOrDefault(typeName)
                ?? throw new KeyNotFoundException($"변환기를 찾을 수 없습니다: {name}");

            var instance = Activator.CreateInstance(type)!;
            Instances[typeName] = instance;
            return instance;
        }
    }

    public static IReadOnlyCollection<string> Names => Types().Keys;

    private static Dictionary<string, Type> Types()
    {
        if (_types != null)
            return _types;

        var result = new Dictionary<string, Type>(StringComparer.Ordinal);

        foreach (var name in new[] { "RomForge", "Common.WPF", "NSW.WPF", "RomForge.Mac.Compat" })
        {
            Assembly assembly;

            try
            {
                assembly = Assembly.Load(name);
            }
            catch
            {
                continue;
            }

            foreach (var type in assembly.GetTypes())
            {
                if (type is { IsAbstract: false, IsClass: true } &&
                    (typeof(IValueConverter).IsAssignableFrom(type) || typeof(IMultiValueConverter).IsAssignableFrom(type)) &&
                    type.GetConstructor(Type.EmptyTypes) != null)
                {
                    result.TryAdd(type.Name, type);
                }
            }
        }

        return _types = result;
    }
}
