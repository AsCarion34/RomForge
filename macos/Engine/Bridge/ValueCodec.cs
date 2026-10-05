using System.Collections;
using System.Globalization;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace RomForge.Mac.Engine.Bridge;

/// <summary>
/// .NET 값을 JSON으로 바꾸고(엔진 → 앱), JSON을 .NET 값으로 바꾼다(앱 → 엔진).
///   기본형·문자열 → JSON 값, enum → 이름 문자열, Visibility → 이름 문자열
///   색/브러시 → {"$color":"#AARRGGBB"}, 이미지 → {"$image":id,...}
///   ICommand → {"$cmd":id,"canExecute":bool}, 컬렉션 → {"$list":id,"count":n}
///   그 밖의 객체 → {"$obj":id,"type":"..."}
/// </summary>
internal sealed class ValueCodec(ObjectRegistry registry, Func<ICommand, int> registerCommand)
{
    public JsonNode? Encode(object? value)
    {
        switch (value)
        {
            case null:
                return null;
            case string s:
                return s;
            case bool b:
                return b;
            case Enum e:
                return e.ToString();
            case char c:
                return c.ToString();
            case double d:
                return double.IsFinite(d) ? d : null;
            case float f:
                return float.IsFinite(f) ? f : null;
            case byte or sbyte or short or ushort or int or uint or long or ulong or decimal:
            {
                // 앱의 JSON 숫자는 Double이라 2^53을 넘는 정수(Switch Title ID 등)는 10진 문자열로 보낸다. Decode가 다시 정수로 읽는다.
                var number = Convert.ToDecimal(value, CultureInfo.InvariantCulture);
                return Math.Abs(number) > MaxExactDouble ? number.ToString(CultureInfo.InvariantCulture) : JsonValue.Create(number);
            }
            case DateTime dt:
                return dt.ToString("o", CultureInfo.InvariantCulture);
            case DateTimeOffset dto:
                return dto.ToString("o", CultureInfo.InvariantCulture);
            case TimeSpan ts:
                return ts.ToString("c", CultureInfo.InvariantCulture);
            case Guid g:
                return g.ToString();
            case SolidColorBrush brush:
                return new JsonObject { ["$color"] = brush.Color.ToString() };
            case Color color:
                return new JsonObject { ["$color"] = color.ToString() };
            case BitmapSource bitmap:
                return new JsonObject
                {
                    ["$image"] = registry.GetId(bitmap),
                    ["asset"] = bitmap.AssetUri,
                    ["width"] = bitmap.PixelWidth,
                    ["height"] = bitmap.PixelHeight,
                };
            case ImageSource image:
                return new JsonObject { ["$image"] = registry.GetId(image) };
            case ICommand command:
                return new JsonObject
                {
                    ["$cmd"] = registerCommand(command),
                    ["canExecute"] = SafeCanExecute(command),
                };
            case IEnumerable enumerable:
                return new JsonObject
                {
                    ["$list"] = registry.GetId(enumerable),
                    ["count"] = enumerable is ICollection col ? col.Count : null,
                };
        }

        var type = value.GetType();

        if (type.IsValueType)
            return value.ToString();

        return new JsonObject
        {
            ["$obj"] = registry.GetId(value),
            ["type"] = type.Name,
        };
    }

    public static bool SafeCanExecute(ICommand command)
    {
        try
        {
            return command.CanExecute(null);
        }
        catch
        {
            return false;
        }
    }

    public object? Decode(JsonNode? node, Type targetType)
    {
        var underlying = Nullable.GetUnderlyingType(targetType) ?? targetType;

        if (node == null)
            return null;

        // 객체 참조({"$obj":id} 등)는 등록된 객체로 되돌린다.
        if (node is JsonObject o)
        {
            foreach (var key in new[] { "$obj", "$list", "$image", "$cmd" })
            {
                if (o.TryGetPropertyValue(key, out var idNode) && idNode != null)
                    return registry.Get(idNode.GetValue<int>());
            }

            return o.Deserialize(underlying, Transport.JsonOptions);
        }

        if (node is JsonArray array)
        {
            var elementType = underlying.IsArray ? underlying.GetElementType()! :
                underlying.IsGenericType ? underlying.GetGenericArguments()[0] : typeof(object);

            var items = array.Select(n => Decode(n, elementType)).ToList();

            if (underlying.IsArray)
            {
                var result = Array.CreateInstance(elementType, items.Count);
                for (int i = 0; i < items.Count; i++)
                    result.SetValue(items[i], i);
                return result;
            }

            var listType = typeof(List<>).MakeGenericType(elementType);
            var list = (IList)Activator.CreateInstance(listType)!;
            foreach (var item in items)
                list.Add(item);

            if (underlying.IsAssignableFrom(listType) || underlying == typeof(object))
                return list;

            // HashSet<T>, ObservableCollection<T> 등: IEnumerable<T>를 받는 생성자로 만든다.
            var enumerableType = typeof(IEnumerable<>).MakeGenericType(elementType);
            return underlying.GetConstructor([enumerableType]) != null
                ? Activator.CreateInstance(underlying, list)
                : list;
        }

        var value = node.AsValue();

        if (underlying.IsEnum)
            return Enum.Parse(underlying, value.ToString(), ignoreCase: true);

        if (value.GetValueKind() == JsonValueKind.String && IsInteger(underlying))
            return ParseInteger(value.GetValue<string>(), underlying);

        if (underlying == typeof(string))
            return value.ToString();

        if (underlying == typeof(object))
            return value.GetValueKind() switch
            {
                JsonValueKind.String => value.GetValue<string>(),
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.Number => value.GetValue<double>(),
                _ => null,
            };

        return value.Deserialize(underlying, Transport.JsonOptions);
    }

    private const decimal MaxExactDouble = 9007199254740992m; // 2^53

    private static bool IsInteger(Type type) =>
        type == typeof(byte) || type == typeof(sbyte) || type == typeof(short) || type == typeof(ushort) ||
        type == typeof(int) || type == typeof(uint) || type == typeof(long) || type == typeof(ulong);

    /// <summary>"72057594037927936" 또는 "0x0100000000010000" 같은 문자열 정수.</summary>
    private static object ParseInteger(string text, Type type)
    {
        text = text.Trim();

        var number = text.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? (decimal)ulong.Parse(text.AsSpan(2), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture)
            : decimal.Parse(text, NumberStyles.Integer, CultureInfo.InvariantCulture);

        return Convert.ChangeType(number, type, CultureInfo.InvariantCulture);
    }

    public static IEnumerable<PropertyInfo> ReadableProperties(Type type) =>
        type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => p.CanRead && p.GetIndexParameters().Length == 0 && p.GetMethod!.IsPublic);
}
