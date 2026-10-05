using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Imaging;
using RomForge.Mac.Compat;
using RomForge.Mac.Engine.Bridge;
using RomForge.ViewModels;

namespace RomForge.Mac.Engine;

/// <summary>
/// SwiftUI 앱과 stdio로 통신하며 upstream ViewModel 트리를 원격으로 노출한다.
///
/// 앱 → 엔진 요청
///   describe {obj}                   객체 속성 스냅샷 + 이후 변경 알림 구독
///   list {obj}                       컬렉션 항목 + 이후 변경 알림 구독
///   set {obj, prop, value}           속성 설정
///   execute {cmd, arg?}              ICommand 실행
///   call {obj, method, args[], exclusive?, cancelKey?}
///                                    공개 메서드 호출(Task면 완료까지 기다림). 뒤쪽 선택 인자는 생략할 수 있다.
///                                    exclusive: 같은 객체·메서드 호출이 끝나기 전에 또 오면 거절(연타 방지)
///                                    cancelKey: CancellationToken 인자 자리에 이 이름의 토큰을 넣는다
///                                    background: 스레드 풀에서 실행(code-behind가 Task.Run으로 돌리던 무거운 계산)
///   callStatic {type, method, args[], …}  정적 메서드 호출. call과 같은 선택 항목을 쓴다
///   create {type, args[]}            객체 생성
///   cancel {key}                     cancelKey로 시작한 호출 취소(code-behind의 _cts.Cancel() 자리)
///   archive.open {path, keep?}       패치 압축 열기(비밀번호가 필요하면 ui.password로 묻는다)
///   bindCallback {obj, prop, name?}  대리자 속성(Func·Action)에 앱 처리기를 건다. 불리면 ui.callback {name, args}로 묻는다
///   convert {converter, …}           upstream 값 변환기 실행(RunConverter 참고)
///   image {img}                      이미지 바이트(base64) 또는 앱 번들 리소스 이름
///   release {objs[]}                 더 쓰지 않는 객체 번호 해제
/// 엔진 → 앱 알림
///   ready {root}, changed {obj, props}, collection {obj, items}, commands {updates[]}, engineError {message}
/// 엔진 → 앱 요청(upstream 코드가 띄우는 창): ui.messageBox, ui.openFile, ui.saveFile, ui.openFolder, ui.password, ui.clipboard, ui.callback
/// </summary>
internal static class BridgeHost
{
    public static int Run(Application app)
    {
        // stdout은 프로토콜 전용이다. upstream·네이티브 코드의 출력은 stderr로 돌린다.
        var stdout = StdioRedirect.DetachProtocolStdout();

        var session = new BridgeSession(app, new Transport(stdout));
        return session.Run();
    }
}

internal sealed class BridgeSession
{
    private const string ProtocolVersion = "1";

    private readonly Application _app;
    private readonly Transport _transport;
    private readonly ObjectRegistry _registry = new();
    private readonly ValueCodec _codec;
    private readonly UiHostBridge _uiHost;
    private readonly CallbackFactory _callbacks;

    // 아래 상태는 UI 스레드에서만 다룬다.
    private readonly HashSet<int> _observedObjects = [];
    private readonly HashSet<int> _observedLists = [];
    private readonly Dictionary<int, bool> _commandStates = [];
    private readonly List<EventHandler> _commandHandlers = []; // CommandManager는 약한 참조라 핸들러를 붙잡아 둔다.
    private readonly HashSet<string> _exclusiveCalls = [];
    private readonly Dictionary<string, CancellationTokenSource> _cancellations = [];

    // 변경 표시는 아무 스레드에서나 들어온다. 50ms마다 UI 스레드에서 모아 보낸다.
    private readonly ConcurrentDictionary<(int Obj, string Prop), byte> _pendingProps = new();
    private readonly ConcurrentDictionary<int, byte> _pendingLists = new();
    private int _commandsDirty;
    private int _flushQueued;

    private MainViewModel? _root;

    public BridgeSession(Application app, Transport transport)
    {
        _app = app;
        _transport = transport;
        _codec = new ValueCodec(_registry, TrackCommand);
        _uiHost = new UiHostBridge(transport);
        _callbacks = new CallbackFactory(_uiHost, _codec);
        UiHost.Current = _uiHost;

        app.Dispatcher.UnhandledException += (_, ex) =>
            _transport.Notify("engineError", new JsonObject { ["message"] = ex.Message, ["detail"] = ex.ToString() });
    }

    public int Run()
    {
        _root = _app.Dispatcher.Invoke(() => new MainViewModel());

        var root = _app.Dispatcher.Invoke(() => _codec.Encode(_root));
        _transport.Notify("ready", new JsonObject { ["protocol"] = ProtocolVersion, ["root"] = root });

        using var timer = new Timer(_ => QueueFlush(), null, 50, 50);

        using var reader = new StreamReader(Console.OpenStandardInput(), new UTF8Encoding(false));
        string? line;

        while ((line = reader.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line))
                continue;

            JsonObject message;

            try
            {
                message = JsonNode.Parse(line)!.AsObject();
            }
            catch (Exception ex)
            {
                Log.Error($"잘못된 메시지: {ex.Message}");
                continue;
            }

            if (_uiHost.TryCompleteResponse(message))
                continue;

            Dispatch(message);
        }

        // 앱이 닫혔다. upstream처럼 설정을 저장하고 끝낸다.
        _app.Dispatcher.Invoke(MainViewModel.SaveConfig);
        return 0;
    }

    private void Dispatch(JsonObject message)
    {
        var id = message["id"];
        string method = message["method"]?.ToString() ?? string.Empty;
        var p = message["params"] as JsonObject ?? [];

        _app.Dispatcher.InvokeAsync(async () =>
        {
            try
            {
                var result = await HandleAsync(method, p);

                if (id != null)
                    _transport.Respond(id, result);
            }
            catch (Exception ex)
            {
                var actual = ex is TargetInvocationException { InnerException: { } inner } ? inner : ex;
                Log.Error($"{method} 실패: {actual}");

                if (id != null)
                    _transport.RespondError(id, actual);
            }
        });
    }

    private async Task<JsonNode?> HandleAsync(string method, JsonObject p)
    {
        switch (method)
        {
            case "ping":
                return "pong";

            case "describe":
                return Describe(Int(p, "obj"));

            case "list":
                return List(Int(p, "obj"));

            case "set":
            {
                var obj = _registry.Get(Int(p, "obj"));
                var prop = obj.GetType().GetProperty(p["prop"]!.ToString(), BindingFlags.Public | BindingFlags.Instance)
                    ?? throw new MissingMemberException(obj.GetType().Name, p["prop"]!.ToString());
                prop.SetValue(obj, _codec.Decode(p["value"], prop.PropertyType));
                return true;
            }

            case "execute":
            {
                var command = (ICommand)_registry.Get(Int(p, "cmd"));
                var arg = _codec.Decode(p["arg"], typeof(object));

                if (!command.CanExecute(arg))
                    return false;

                command.Execute(arg);
                return true;
            }

            case "call":
            {
                var obj = _registry.Get(Int(p, "obj"));
                return await InvokeTrackedAsync(p, obj, obj.GetType(), BindingFlags.Public | BindingFlags.Instance, $"{Int(p, "obj")}");
            }

            case "cancel":
            {
                if (!_cancellations.TryGetValue(p["key"]!.ToString(), out var cts))
                    return false;

                cts.Cancel();
                return true;
            }

            case "image":
            {
                var image = _registry.Get(Int(p, "img")) as BitmapSource;
                var bytes = image?.GetEncodedBytes();

                return new JsonObject
                {
                    ["asset"] = image?.AssetUri,
                    ["data"] = bytes != null ? Convert.ToBase64String(bytes) : null,
                };
            }

            case "release":
                foreach (var n in p["objs"] as JsonArray ?? [])
                    Release(n!.GetValue<int>());
                return true;

            case "convert":
                return RunConverter(p);

            case "bindCallback":
            {
                // code-behind가 ViewModel의 대리자 속성에 창 띄우는 메서드를 넣던 자리
                // (예: NormalVM.RequestSourceSelectionAsync = ShowSourceSelectionDialogAsync). name이 없으면 비운다.
                var obj = _registry.Get(Int(p, "obj"));
                var prop = obj.GetType().GetProperty(p["prop"]!.ToString(), BindingFlags.Public | BindingFlags.Instance)
                    ?? throw new MissingMemberException(obj.GetType().Name, p["prop"]!.ToString());
                string? name = p["name"]?.ToString();
                prop.SetValue(obj, name == null ? null : _callbacks.Create(prop.PropertyType, name));
                return true;
            }

            case "callStatic":
            {
                // upstream code-behind가 쓰는 정적 도우미(예: SwitchGameFileListOrganizer.Reorganize)를 그대로 부른다.
                var type = ResolveType(p["type"]!.ToString());
                return await InvokeTrackedAsync(p, null, type, BindingFlags.Public | BindingFlags.Static, type.FullName!);
            }

            case "create":
            {
                // upstream code-behind가 만드는 도우미 객체(예: new GameFilePatchSyncManager(gameFiles))를 만든다.
                var type = ResolveType(p["type"]!.ToString());
                var (ctor, values) = Bind(type.GetConstructors(), p["args"] as JsonArray ?? [], null)
                    ?? throw new MissingMethodException(type.Name, ".ctor");
                return _codec.Encode(((ConstructorInfo)ctor).Invoke(values));
            }

            case "archive.open":
            case "debug.openArchive": // 예전 이름
            {
                // upstream code-behind와 같은 경로(PasswordPromptWindow.OpenWithPasswordPromptAsync)로 패치 압축을 연다.
                // 필요하면 앱에 비밀번호를 묻는다(ui.password). keep이면 연 압축을 닫지 않고 돌려준다(다 쓰면 call Dispose).
                var opened = await RomForge.Views.PasswordPromptWindow.OpenWithPasswordPromptAsync(p["path"]!.ToString(), null);

                if (opened is not { } result)
                    return new JsonObject { ["opened"] = false };

                var response = new JsonObject
                {
                    ["opened"] = true,
                    ["password"] = result.Password,
                    ["entries"] = new JsonArray([.. result.Archive.EntryPaths.Select(e => (JsonNode?)e)]),
                };

                if (p["keep"]?.GetValue<bool>() == true)
                    response["archive"] = _codec.Encode(result.Archive);
                else
                    result.Archive.Dispose();

                return response;
            }

            default:
                throw new NotSupportedException($"알 수 없는 요청: {method}");
        }
    }

    private static int Int(JsonObject p, string name) =>
        p[name]?.GetValue<int>() ?? throw new ArgumentException($"'{name}' 값이 필요합니다.");

    /// <summary>
    /// upstream 값 변환기 실행.
    ///   {converter, source:{obj, path}, parameter?, targetType?}   ViewModel 속성 값을 그대로(.NET 타입) 넘긴다
    ///   {converter, value, valueType?, parameter?}                 JSON 값을 넘긴다(valueType이 있으면 그 타입으로, 예: enum 이름 → enum 값)
    ///   {converter, sources:[{obj,path}|값…], parameter?}          IMultiValueConverter
    /// </summary>
    private JsonNode? RunConverter(JsonObject p)
    {
        var converter = ConverterRegistry.Get(p["converter"]!.ToString());
        object? parameter = p["parameter"]?.ToString();
        var targetType = TargetType(p["targetType"]?.ToString());
        var culture = System.Globalization.CultureInfo.CurrentCulture;

        object? result = converter switch
        {
            System.Windows.Data.IMultiValueConverter multi =>
                multi.Convert([.. (p["sources"] as JsonArray ?? []).Select(n => SourceValue(n))], targetType, parameter, culture),
            System.Windows.Data.IValueConverter single =>
                single.Convert(p["source"] is JsonObject ? SourceValue(p["source"]) : SourceValue(p["value"], p["valueType"]?.ToString()), targetType, parameter, culture),
            _ => throw new InvalidOperationException("변환기가 아닙니다."),
        };

        return result == System.Windows.Data.Binding.DoNothing
            ? new JsonObject { ["$nothing"] = true }
            : _codec.Encode(result);
    }

    private object? SourceValue(JsonNode? node, string? valueType = null)
    {
        if (node is JsonObject source && source["obj"] != null)
            return ReadPath(_registry.Get(Int(source, "obj")), source["path"]?.ToString() ?? string.Empty);

        return node is JsonValue v ? _codec.Decode(v, valueType != null ? ResolveType(valueType) : typeof(object)) : null;
    }

    /// <summary>"A.B.C" 같은 속성 경로를 읽는다(빈 경로면 객체 자신).</summary>
    private static object? ReadPath(object? obj, string path)
    {
        foreach (var part in path.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            if (obj == null)
                return null;

            obj = obj.GetType().GetProperty(part, BindingFlags.Public | BindingFlags.Instance)?.GetValue(obj);
        }

        return obj;
    }

    private static Type TargetType(string? name) => name switch
    {
        "Visibility" => typeof(Visibility),
        "Brush" => typeof(System.Windows.Media.Brush),
        "ImageSource" => typeof(System.Windows.Media.ImageSource),
        "String" => typeof(string),
        "Boolean" => typeof(bool),
        "Double" => typeof(double),
        _ => typeof(object),
    };

    /// <summary>앱이 화면을 만들 때 쓰는 타입 정보: 속성 종류, enum 선택지, 호출 가능한 메서드.</summary>
    private static void AddTypeInfo(Type type, JsonObject result)
    {
        var types = new JsonObject();
        var enums = new JsonObject();

        foreach (var prop in ValueCodec.ReadableProperties(type))
        {
            var t = Nullable.GetUnderlyingType(prop.PropertyType) ?? prop.PropertyType;
            types[prop.Name] = t.IsEnum ? "enum" : t.Name;

            if (t.IsEnum)
                enums[prop.Name] = new JsonArray([.. Enum.GetNames(t).Select(n => (JsonNode?)n)]);
        }

        var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Instance)
            .Where(m => !m.IsSpecialName && m.DeclaringType != typeof(object) && m.DeclaringType?.Namespace?.StartsWith("System") != true)
            .Select(m => $"{m.Name}({m.GetParameters().Length})")
            .Distinct()
            .OrderBy(m => m)
            .Select(m => (JsonNode?)m);

        result["types"] = types;
        result["enums"] = enums;
        result["methods"] = new JsonArray([.. methods]);
    }

    private JsonObject Describe(int id)
    {
        var obj = _registry.Get(id);
        var type = obj.GetType();

        if (_observedObjects.Add(id) && obj is INotifyPropertyChanged npc)
            npc.PropertyChanged += OnPropertyChanged;

        var props = new JsonObject();
        var settable = new JsonArray();

        foreach (var prop in ValueCodec.ReadableProperties(type))
        {
            props[prop.Name] = ReadProperty(obj, prop);

            if (prop.SetMethod?.IsPublic == true)
                settable.Add(prop.Name);
        }

        var result = new JsonObject
        {
            ["obj"] = id,
            ["type"] = type.FullName,
            ["props"] = props,
            ["settable"] = settable,
        };

        AddTypeInfo(type, result);
        return result;
    }

    private JsonNode? ReadProperty(object obj, PropertyInfo prop)
    {
        try
        {
            return _codec.Encode(prop.GetValue(obj));
        }
        catch (Exception ex)
        {
            var actual = ex is TargetInvocationException { InnerException: { } inner } ? inner : ex;
            return new JsonObject { ["$error"] = actual.Message };
        }
    }

    private JsonObject List(int id)
    {
        var obj = _registry.Get(id);

        if (obj is not IEnumerable enumerable)
            throw new InvalidOperationException($"객체 {id}은(는) 컬렉션이 아닙니다.");

        if (_observedLists.Add(id) && obj is INotifyCollectionChanged ncc)
            ncc.CollectionChanged += OnCollectionChanged;

        return new JsonObject { ["obj"] = id, ["items"] = EncodeItems(enumerable) };
    }

    private JsonArray EncodeItems(IEnumerable enumerable)
    {
        var items = new JsonArray();

        foreach (var item in enumerable.Cast<object?>().ToList())
            items.Add(_codec.Encode(item));

        return items;
    }

    /// <summary>call·callStatic 공통: exclusive(연타 방지)와 cancelKey(취소 토큰)를 처리하고 메서드를 부른다.</summary>
    private async Task<JsonNode?> InvokeTrackedAsync(JsonObject p, object? target, Type type, BindingFlags flags, string owner)
    {
        string name = p["method"]!.ToString();
        var args = p["args"] as JsonArray ?? [];
        string? exclusiveKey = p["exclusive"]?.GetValue<bool>() == true ? $"{owner}|{name}" : null;
        string? cancelKey = p["cancelKey"]?.ToString();

        // 이 상태들은 UI 스레드에서만 다루므로 확인과 등록 사이에 끼어들 요청이 없다.
        if ((exclusiveKey != null && _exclusiveCalls.Contains(exclusiveKey)) || (cancelKey != null && _cancellations.ContainsKey(cancelKey)))
            throw new InvalidOperationException("이미 실행 중입니다.");

        using var cts = cancelKey != null ? new CancellationTokenSource() : null;

        if (exclusiveKey != null)
            _exclusiveCalls.Add(exclusiveKey);

        if (cancelKey != null)
            _cancellations[cancelKey] = cts!;

        try
        {
            return await InvokeAsync(target, type, name, args, flags, cts?.Token, p["background"]?.GetValue<bool>() == true);
        }
        finally
        {
            if (exclusiveKey != null)
                _exclusiveCalls.Remove(exclusiveKey);

            if (cancelKey != null)
                _cancellations.Remove(cancelKey);
        }
    }

    private async Task<JsonNode?> InvokeAsync(object? target, Type type, string name, JsonArray args, BindingFlags flags, CancellationToken? token = null, bool background = false)
    {
        var (method, values) = Bind(type.GetMethods(flags).Where(m => m.Name == name), args, token) is ({ } m, { } v)
            ? ((MethodInfo)m, v)
            : throw new MissingMethodException(type.Name, name);

        var result = background
            ? await Task.Run(() => method.Invoke(target, values))
            : method.Invoke(target, values);

        if (result is Task task)
        {
            await task;

            var returnType = method.ReturnType;
            result = returnType.IsGenericType ? returnType.GetProperty("Result")!.GetValue(task) : null;
        }

        return _codec.Encode(result);
    }

    /// <summary>
    /// 오버로드 고르기: 인자 수가 같은 것부터, 그다음 뒤쪽 인자가 모두 선택 인자(또는 CancellationToken)인 것.
    /// 인자를 그 매개변수 타입으로 바꿀 수 없으면 다음 후보를 본다.
    /// </summary>
    private (MethodBase Method, object?[] Values)? Bind(IEnumerable<MethodBase> candidates, JsonArray args, CancellationToken? token)
    {
        var ordered = candidates
            .Where(m => m.GetParameters().Length == args.Count ||
                (m.GetParameters().Length > args.Count &&
                 m.GetParameters().Skip(args.Count).All(x => x.IsOptional || x.ParameterType == typeof(CancellationToken))))
            .OrderBy(m => m.GetParameters().Length != args.Count);

        foreach (var method in ordered)
        {
            var parameters = method.GetParameters();
            var values = new object?[parameters.Length];
            bool ok = true;

            for (int i = 0; i < parameters.Length && ok; i++)
            {
                var parameter = parameters[i];

                if (i >= args.Count && parameter.HasDefaultValue && parameter.ParameterType != typeof(CancellationToken))
                {
                    values[i] = parameter.DefaultValue;
                    continue;
                }

                try
                {
                    values[i] = DecodeArgument(i < args.Count ? args[i] : null, parameter.ParameterType, token);
                    ok = values[i] == null || parameter.ParameterType.IsInstanceOfType(values[i]);
                }
                catch (Exception ex) when (ex is System.Text.Json.JsonException or FormatException or InvalidCastException or ArgumentException or InvalidOperationException or NotSupportedException)
                {
                    ok = false;
                }
            }

            if (ok)
                return (method, values);
        }

        return null;
    }

    /// <summary>
    /// 메서드·생성자 인자 변환. 콜백(Action) 자리에 null이 오면 아무것도 하지 않는 콜백을,
    /// CancellationToken 자리에는 call의 cancelKey 토큰(없으면 취소되지 않는 토큰)을 넘긴다.
    /// </summary>
    private object? DecodeArgument(JsonNode? node, Type type, CancellationToken? token = null)
    {
        if (type == typeof(CancellationToken))
            return token ?? CancellationToken.None;

        if (node == null)
        {
            if (type == typeof(Action))
                return new Action(() => { });

            if (type.IsGenericType && type.GetGenericTypeDefinition().FullName?.StartsWith("System.Action`") == true)
            {
                var parameters = type.GetGenericArguments().Select(t => System.Linq.Expressions.Expression.Parameter(t));
                return System.Linq.Expressions.Expression.Lambda(type, System.Linq.Expressions.Expression.Empty(), parameters).Compile();
            }

            return type.IsValueType ? Activator.CreateInstance(type) : null;
        }

        return _codec.Decode(node, type);
    }

    /// <summary>"RomForge.Controls.Switch.SwitchGameFileListOrganizer" 또는 짧은 이름으로 upstream 타입을 찾는다.</summary>
    private static Type ResolveType(string name)
    {
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            var exact = assembly.GetType(name);
            if (exact != null)
                return exact;
        }

        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies().Where(a => !a.IsDynamic))
        {
            Type[] types;
            try { types = assembly.GetTypes(); } catch (ReflectionTypeLoadException ex) { types = [.. ex.Types.OfType<Type>()]; }

            var match = types.FirstOrDefault(t => t.Name == name || t.FullName == name);
            if (match != null)
                return match;
        }

        throw new TypeLoadException($"타입을 찾을 수 없습니다: {name}");
    }

    private void Release(int id)
    {
        if (_registry.TryGet(id, out var obj))
        {
            if (_observedObjects.Remove(id) && obj is INotifyPropertyChanged npc)
                npc.PropertyChanged -= OnPropertyChanged;

            if (_observedLists.Remove(id) && obj is INotifyCollectionChanged ncc)
                ncc.CollectionChanged -= OnCollectionChanged;
        }

        _commandStates.Remove(id);
        _registry.Release(id);
    }

    private int TrackCommand(ICommand command)
    {
        int id = _registry.GetId(command);

        if (!_commandStates.ContainsKey(id))
        {
            _commandStates[id] = ValueCodec.SafeCanExecute(command);

            EventHandler handler = (_, _) => Interlocked.Exchange(ref _commandsDirty, 1);
            _commandHandlers.Add(handler);
            command.CanExecuteChanged += handler;
        }

        return id;
    }

    private void OnPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (sender == null)
            return;

        _pendingProps[(_registry.GetId(sender), string.IsNullOrEmpty(e.PropertyName) ? "*" : e.PropertyName)] = 0;
    }

    private void OnCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (sender != null)
            _pendingLists[_registry.GetId(sender)] = 0;
    }

    private void QueueFlush()
    {
        if (_pendingProps.IsEmpty && _pendingLists.IsEmpty && Volatile.Read(ref _commandsDirty) == 0)
            return;

        if (Interlocked.CompareExchange(ref _flushQueued, 1, 0) != 0)
            return;

        _app.Dispatcher.InvokeAsync(() =>
        {
            try
            {
                Flush();
            }
            finally
            {
                Interlocked.Exchange(ref _flushQueued, 0);
            }
        });
    }

    private void Flush()
    {
        var props = _pendingProps.Keys.ToList();
        foreach (var key in props)
            _pendingProps.TryRemove(key, out _);

        foreach (var group in props.GroupBy(k => k.Obj))
        {
            if (!_registry.TryGet(group.Key, out var obj) || obj == null)
                continue;

            var type = obj.GetType();
            var changed = new JsonObject();
            var names = group.Any(k => k.Prop == "*")
                ? ValueCodec.ReadableProperties(type).Select(p => p.Name)
                : group.Select(k => k.Prop);

            foreach (var name in names.Distinct())
            {
                var prop = type.GetProperty(name, BindingFlags.Public | BindingFlags.Instance);

                if (prop != null && prop.GetIndexParameters().Length == 0)
                    changed[name] = ReadProperty(obj, prop);
            }

            if (changed.Count > 0)
                _transport.Notify("changed", new JsonObject { ["obj"] = group.Key, ["props"] = changed });
        }

        var lists = _pendingLists.Keys.ToList();
        foreach (var id in lists)
        {
            _pendingLists.TryRemove(id, out _);

            if (_registry.TryGet(id, out var obj) && obj is IEnumerable enumerable)
                _transport.Notify("collection", new JsonObject { ["obj"] = id, ["items"] = EncodeItems(enumerable) });
        }

        // WPF는 입력이 있을 때마다 CanExecute를 다시 확인한다. 여기서는 변경이 있을 때마다 확인한다.
        if (Interlocked.Exchange(ref _commandsDirty, 0) == 1 || props.Count > 0 || lists.Count > 0)
            RefreshCommands();
    }

    private void RefreshCommands()
    {
        var updates = new JsonArray();

        foreach (var (id, last) in _commandStates.ToList())
        {
            if (!_registry.TryGet(id, out var obj) || obj is not ICommand command)
                continue;

            bool now = ValueCodec.SafeCanExecute(command);

            if (now != last)
            {
                _commandStates[id] = now;
                updates.Add(new JsonObject { ["cmd"] = id, ["canExecute"] = now });
            }
        }

        if (updates.Count > 0)
            _transport.Notify("commands", new JsonObject { ["updates"] = updates });
    }
}
