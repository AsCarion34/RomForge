using System.Collections.Concurrent;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Threading;
using RomForge.Mac.Compat;

namespace RomForge.Mac.Engine.Bridge;

/// <summary>
/// upstream 코드가 띄우는 대화상자·메시지 상자·클립보드 요청을 앱(SwiftUI)으로 보내고 결과를 기다린다.
/// UI 스레드에서 기다리는 동안에는 다른 UI 작업을 계속 처리해(WPF 모달처럼) 교착을 피한다.
/// </summary>
internal sealed class UiHostBridge(Transport transport) : IUiHost
{
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonNode?>> _pending = new();
    private int _next;

    /// <summary>앱이 보낸 응답이면 처리하고 true를 돌려준다.</summary>
    public bool TryCompleteResponse(JsonObject message)
    {
        if (message["method"] != null || message["id"] is not JsonValue idValue)
            return false;

        if (!idValue.TryGetValue<string>(out var id) || !_pending.TryRemove(id, out var tcs))
            return false;

        if (message["error"] is JsonObject error)
            tcs.TrySetException(new InvalidOperationException(error["message"]?.ToString() ?? "앱 오류"));
        else
            tcs.TrySetResult(message["result"]?.DeepClone());

        return true;
    }

    private JsonNode? Request(string method, JsonObject parameters)
    {
        var task = RequestAsync(method, parameters);
        var dispatcher = Application.Current?.Dispatcher;

        if (dispatcher != null && dispatcher.CheckAccess())
        {
            var frame = new DispatcherFrame();
            task.ContinueWith(_ => frame.Continue = false, TaskScheduler.Default);
            Dispatcher.PushFrame(frame);
        }

        return task.GetAwaiter().GetResult();
    }

    private Task<JsonNode?> RequestAsync(string method, JsonObject parameters)
    {
        string id = $"e{Interlocked.Increment(ref _next)}";
        var tcs = new TaskCompletionSource<JsonNode?>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[id] = tcs;

        transport.Send(new JsonObject { ["id"] = id, ["method"] = method, ["params"] = parameters });
        return tcs.Task;
    }

    /// <summary>bindCallback으로 건 대리자가 앱의 처리기에 묻는다(기다리는 동안에도 UI 작업은 계속 돈다).</summary>
    public JsonNode? Callback(string name, JsonArray args) =>
        Request("ui.callback", new JsonObject { ["name"] = name, ["args"] = args });

    /// <summary>Task를 돌려주는 대리자용. UI 스레드를 붙잡지 않는다.</summary>
    public Task<JsonNode?> CallbackAsync(string name, JsonArray args) =>
        RequestAsync("ui.callback", new JsonObject { ["name"] = name, ["args"] = args });

    public MessageBoxResult ShowMessageBox(string text, string caption, MessageBoxButton button, MessageBoxImage icon)
    {
        var result = Request("ui.messageBox", new JsonObject
        {
            ["text"] = text,
            ["caption"] = caption,
            ["button"] = button.ToString(),
            ["icon"] = icon.ToString(),
        });

        return Enum.TryParse<MessageBoxResult>(result?.ToString(), out var r) ? r : MessageBoxResult.None;
    }

    public string[]? ShowOpenFileDialog(FileDialogRequest request) =>
        ToPaths(Request("ui.openFile", FileRequest(request)));

    public string? ShowSaveFileDialog(FileDialogRequest request) =>
        Request("ui.saveFile", FileRequest(request))?.ToString();

    public string[]? ShowFolderDialog(FolderDialogRequest request) =>
        ToPaths(Request("ui.openFolder", new JsonObject
        {
            ["title"] = request.Title,
            ["initialDirectory"] = request.InitialDirectory,
            ["multiselect"] = request.Multiselect,
        }));

    public string? PromptPassword(string archivePath, bool wrongPassword) =>
        Request("ui.password", new JsonObject
        {
            ["archivePath"] = archivePath,
            ["wrongPassword"] = wrongPassword,
        })?.ToString();

    public bool SetClipboardText(string text) =>
        Request("ui.clipboard", new JsonObject { ["text"] = text })?.GetValue<bool>() ?? false;

    private static JsonObject FileRequest(FileDialogRequest r) => new()
    {
        ["title"] = r.Title,
        ["filter"] = r.Filter,
        ["initialDirectory"] = r.InitialDirectory,
        ["fileName"] = r.FileName,
        ["defaultExt"] = r.DefaultExt,
        ["multiselect"] = r.Multiselect,
    };

    private static string[]? ToPaths(JsonNode? node) =>
        node is JsonArray array ? [.. array.Select(n => n!.ToString())] : null;
}
