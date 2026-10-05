using System.Collections;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using RomForge.Mac.Engine.Bridge;
using RomForge.ViewModels;

namespace RomForge.Mac.Engine;

/// <summary>
/// upstream ViewModel 스키마(타입별 속성·커맨드·메서드·enum 값)를 JSON으로 출력한다(--dump-schema [파일]).
/// upstream을 머지하기 전후의 스키마를 비교하면 SwiftUI 화면에서 고칠 곳이 정확히 나온다.
/// </summary>
internal static class SchemaDump
{
    public static int Run(Application app, string[] args)
    {
        int at = Array.IndexOf(args, "--dump-schema");
        string? output = args.Length > at + 1 ? args[at + 1] : null;

        var schema = app.Dispatcher.Invoke(() =>
        {
            var root = new MainViewModel();
            var types = new SortedDictionary<string, object>(StringComparer.Ordinal);
            var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);
            Walk(root, types, visited, 0);
            return types;
        });

        string json = JsonSerializer.Serialize(schema, new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });

        if (output == null)
            Console.WriteLine(json);
        else
            File.WriteAllText(output, json + "\n");

        return 0;
    }

    private static bool IsUpstream(Type t) =>
        t.Assembly.GetName().Name is { } n && !n.StartsWith("System") && !n.StartsWith("Microsoft") && n != "RomForge.Mac.Compat" && !t.IsEnum;

    private static void Walk(object obj, SortedDictionary<string, object> types, HashSet<object> visited, int depth)
    {
        if (depth > 8 || !visited.Add(obj))
            return;

        var type = obj.GetType();
        Describe(type, types);

        foreach (var prop in ValueCodec.ReadableProperties(type))
        {
            object? value;
            try { value = prop.GetValue(obj); } catch { continue; }

            if (value == null || value is string || value is ICommand)
                continue;

            if (value is IEnumerable enumerable)
            {
                var element = prop.PropertyType.IsGenericType ? prop.PropertyType.GetGenericArguments().LastOrDefault() : null;
                if (element != null && IsUpstream(element))
                    Describe(element, types);

                foreach (var item in enumerable.Cast<object?>().Take(3))
                    if (item != null && IsUpstream(item.GetType()))
                        Walk(item, types, visited, depth + 1);
                continue;
            }

            if (IsUpstream(value.GetType()))
                Walk(value, types, visited, depth + 1);
        }
    }

    private static void Describe(Type type, SortedDictionary<string, object> types)
    {
        string key = type.FullName ?? type.Name;
        if (types.ContainsKey(key))
            return;

        var props = new SortedDictionary<string, string>(StringComparer.Ordinal);
        var enums = new SortedDictionary<string, string[]>(StringComparer.Ordinal);

        foreach (var prop in ValueCodec.ReadableProperties(type))
        {
            var t = Nullable.GetUnderlyingType(prop.PropertyType) ?? prop.PropertyType;
            props[prop.Name] = Name(prop.PropertyType) + (prop.SetMethod?.IsPublic == true ? " { set; }" : "");

            if (t.IsEnum)
                enums[prop.Name] = Enum.GetNames(t);
        }

        var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Instance)
            .Where(m => !m.IsSpecialName && m.DeclaringType != typeof(object) && m.DeclaringType?.Namespace?.StartsWith("System") != true)
            .Select(m => $"{m.Name}({string.Join(", ", m.GetParameters().Select(p => Name(p.ParameterType)))})")
            .Distinct()
            .OrderBy(m => m, StringComparer.Ordinal)
            .ToArray();

        types[key] = new SortedDictionary<string, object>(StringComparer.Ordinal)
        {
            ["properties"] = props,
            ["enums"] = enums,
            ["methods"] = methods,
        };
    }

    private static string Name(Type t)
    {
        if (Nullable.GetUnderlyingType(t) is { } inner)
            return Name(inner) + "?";

        if (!t.IsGenericType)
            return t.Name;

        string baseName = t.Name[..t.Name.IndexOf('`')];
        return $"{baseName}<{string.Join(", ", t.GetGenericArguments().Select(Name))}>";
    }
}
