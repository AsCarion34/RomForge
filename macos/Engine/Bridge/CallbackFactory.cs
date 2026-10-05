using System.Collections;
using System.Linq.Expressions;
using System.Reflection;
using System.Text.Json.Nodes;

namespace RomForge.Mac.Engine.Bridge;

/// <summary>
/// ViewModel의 대리자 속성(Func·Action)에 넣을 대리자를 만든다. upstream code-behind가
/// <c>vm.RequestSourceSelectionAsync = ShowSourceSelectionDialogAsync</c>처럼 창을 띄우는 메서드를 넣던 자리다.
/// 대리자가 불리면 인자를 값으로 펼쳐 앱에 ui.callback {name, args}로 묻고, 답을 반환 타입으로 바꿔 돌려준다.
/// </summary>
internal sealed class CallbackFactory(UiHostBridge host, ValueCodec codec)
{
    public Delegate Create(Type delegateType, string name)
    {
        var invoke = delegateType.GetMethod("Invoke")
            ?? throw new ArgumentException($"대리자 타입이 아닙니다: {delegateType}");

        var parameters = invoke.GetParameters().Select(p => Expression.Parameter(p.ParameterType, p.Name)).ToArray();
        var args = Expression.NewArrayInit(typeof(object), parameters.Select(p => Expression.Convert(p, typeof(object))));
        var returnType = invoke.ReturnType;

        var target = returnType == typeof(void) ? Method(nameof(InvokeVoid))
            : returnType == typeof(Task) ? Method(nameof(InvokeTask))
            : returnType.IsGenericType && returnType.GetGenericTypeDefinition() == typeof(Task<>)
                ? Method(nameof(InvokeTaskOf)).MakeGenericMethod(returnType.GetGenericArguments()[0])
                : Method(nameof(InvokeOf)).MakeGenericMethod(returnType);

        var body = Expression.Call(Expression.Constant(this), target, Expression.Constant(name), args);
        return Expression.Lambda(delegateType, body, parameters).Compile();
    }

    private static MethodInfo Method(string name) => typeof(CallbackFactory).GetMethod(name)!;

    // 아래 메서드는 Create가 만든 대리자가 부른다.
    public void InvokeVoid(string name, object?[] args) => host.Callback(name, Snapshot(args));

    public async Task InvokeTask(string name, object?[] args) => await host.CallbackAsync(name, Snapshot(args));

    public async Task<T> InvokeTaskOf<T>(string name, object?[] args) => Decode<T>(await host.CallbackAsync(name, Snapshot(args)));

    public T InvokeOf<T>(string name, object?[] args) => Decode<T>(host.Callback(name, Snapshot(args)));

    private T Decode<T>(JsonNode? node) => codec.Decode(node, typeof(T)) is T value ? value : default!;

    private JsonArray Snapshot(object?[] args) => new([.. args.Select(a => Snapshot(a, depth: 2))]);

    /// <summary>
    /// 앱이 엔진에 다시 묻지 않고 바로 그릴 수 있게 인자를 값으로 펼친다.
    /// 목록은 배열, 객체는 공개 속성(엔진 객체 번호 $obj도 함께)으로 보낸다.
    /// </summary>
    private JsonNode? Snapshot(object? value, int depth)
    {
        if (value == null || value is string || value.GetType().IsPrimitive || value is Enum or decimal or DateTime or DateTimeOffset or TimeSpan or Guid)
            return codec.Encode(value);

        if (depth > 0 && value is IEnumerable items)
            return new JsonArray([.. items.Cast<object?>().Select(i => Snapshot(i, depth - 1))]);

        var encoded = codec.Encode(value);

        if (depth > 0 && encoded is JsonObject result)
        {
            foreach (var prop in ValueCodec.ReadableProperties(value.GetType()))
            {
                try { result[prop.Name] = Snapshot(prop.GetValue(value), depth - 1); }
                catch (Exception) { /* 읽을 수 없는 속성은 뺀다 */ }
            }
        }

        return encoded;
    }
}
