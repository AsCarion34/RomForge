using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace RomForge.Mac.Engine.Bridge;

/// <summary>
/// stdio 위의 줄 단위 JSON 메시지 전송.
///   요청:   {"id":1,"method":"describe","params":{...}}
///   응답:   {"id":1,"result":...} 또는 {"id":1,"error":{"message":"..."}}
///   알림:   {"method":"changed","params":{...}}  (id 없음)
/// 엔진 → 앱 방향 요청(대화상자 등)의 id는 "e1", "e2"처럼 문자열이다.
/// </summary>
internal sealed class Transport(Stream output)
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        TypeInfoResolver = new System.Text.Json.Serialization.Metadata.DefaultJsonTypeInfoResolver(),
    };

    private readonly StreamWriter _writer = new(output, new UTF8Encoding(false)) { AutoFlush = false };
    private readonly object _lock = new();

    public void Send(JsonObject message)
    {
        string line = message.ToJsonString(JsonOptions);

        lock (_lock)
        {
            _writer.Write(line);
            _writer.Write('\n');
            _writer.Flush();
        }
    }

    public void Notify(string method, JsonObject parameters) =>
        Send(new JsonObject { ["method"] = method, ["params"] = parameters });

    public void Respond(JsonNode? id, JsonNode? result) =>
        Send(new JsonObject { ["id"] = id?.DeepClone(), ["result"] = result });

    public void RespondError(JsonNode? id, Exception ex) =>
        Send(new JsonObject
        {
            ["id"] = id?.DeepClone(),
            ["error"] = new JsonObject
            {
                ["message"] = ex.Message,
                ["type"] = ex.GetType().Name,
            },
        });
}
