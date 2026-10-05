import AppKit
import Foundation
import Observation

struct EngineError: LocalizedError {
    let message: String
    /// .NET 예외 이름(예: "OperationCanceledException")
    var type: String? = nil
    var errorDescription: String? { message }

    /// upstream이 catch (OperationCanceledException)로 조용히 넘기는 취소
    var isCancellation: Bool { type == "OperationCanceledException" || type == "TaskCanceledException" }
}

/// call·callStatic 선택 항목. 엔진 쪽은 BridgeHost.InvokeTrackedAsync.
struct CallOptions {
    /// 같은 호출이 끝나기 전에 또 오면 엔진이 거절한다(연타 방지)
    var exclusive = false
    /// CancellationToken 인자 자리에 넣을 토큰 이름. EngineClient.cancel(key)로 취소한다(code-behind의 _cts 자리)
    var cancelKey: String? = nil
    /// 엔진 스레드 풀에서 실행한다(code-behind가 Task.Run으로 돌리던 무거운 계산). 그동안에도 화면 알림이 멈추지 않는다.
    var background = false

    static let none = CallOptions()
    static let background = CallOptions(background: true)

    fileprivate func apply(to params: inout [String: JSONValue]) {
        if exclusive { params["exclusive"] = .bool(true) }
        if let cancelKey { params["cancelKey"] = .string(cancelKey) }
        if background { params["background"] = .bool(true) }
    }
}

/// .NET 엔진 프로세스를 띄우고 stdio(줄 단위 JSON)로 통신한다.
/// 프로토콜은 macos/Engine/BridgeHost.cs 주석 참고.
@MainActor
@Observable
final class EngineClient {
    private(set) var isReady = false
    private(set) var rootId: Int?
    var lastError: String?
    let store = RemoteStore()

    // 변환기 결과·이미지 캐시(Components/Converted.swift)
    var converterCache: [String: JSONValue] = [:]
    var pendingConversions: Set<String> = []
    var imageCache: [Int: NSImage] = [:]
    var pendingImages: Set<Int> = []

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var describing: Set<Int> = []

    func start() {
        guard process == nil else { return }

        do {
            let engine = try EngineLocator.prepare()
            let process = Process()
            process.executableURL = engine.executable
            process.currentDirectoryURL = engine.executable.deletingLastPathComponent()

            var env = ProcessInfo.processInfo.environment
            if let dotnetRoot = engine.dotnetRoot { env["DOTNET_ROOT"] = dotnetRoot }
            process.environment = env

            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                Task { @MainActor in self?.receive(data) }
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { FileHandle.standardError.write(data) }
            }
            process.terminationHandler = { [weak self] proc in
                Task { @MainActor in
                    self?.isReady = false
                    self?.lastError = "엔진이 종료되었습니다(코드 \(proc.terminationStatus))."
                }
            }

            try process.run()
            self.process = process
            self.input = stdin.fileHandleForWriting
        } catch {
            lastError = "엔진을 시작하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func stop() {
        try? input?.close()
        process = nil
    }

    // MARK: - 요청

    func request(_ method: String, _ params: [String: JSONValue] = [:]) async throws -> JSONValue {
        let id = nextId
        nextId += 1

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            send(.object(["id": .int(id), "method": .string(method), "params": .object(params)]))
        }
    }

    @discardableResult
    func describe(_ id: Int) async -> RemoteObject? {
        guard let result = try? await request("describe", ["obj": .int(id)]) else { return nil }
        return store.applyDescribe(result)
    }

    /// 컬렉션 항목을 받고 변경을 구독한다. 객체 항목은 속성까지 받아 둔다.
    func observeList(_ id: Int?) async {
        guard let id, let result = try? await request("list", ["obj": .int(id)]) else { return }
        store.applyCollection(result)
        await describeItems(result["items"]?.array ?? [])
    }

    @discardableResult
    func call(_ obj: Int?, _ method: String, _ args: [JSONValue] = []) async -> JSONValue? {
        guard let obj else { return nil }
        do {
            return try await request("call", ["obj": .int(obj), "method": .string(method), "args": .array(args)])
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// 공개 메서드 호출. 실패는 EngineError로 던진다(code-behind의 try/catch 자리).
    func callThrowing(_ obj: Int, _ method: String, _ args: [JSONValue] = [], options: CallOptions = .none) async throws -> JSONValue {
        var params: [String: JSONValue] = ["obj": .int(obj), "method": .string(method), "args": .array(args)]
        options.apply(to: &params)
        return try await request("call", params)
    }

    /// 정적 메서드 호출. 실패는 EngineError로 던진다.
    func callStaticThrowing(_ type: String, _ method: String, _ args: [JSONValue] = [], options: CallOptions = .none) async throws -> JSONValue {
        var params: [String: JSONValue] = ["type": .string(type), "method": .string(method), "args": .array(args)]
        options.apply(to: &params)
        return try await request("callStatic", params)
    }

    /// CallOptions.cancelKey로 시작한 호출을 취소한다. 진행 중인 호출이 없으면 아무 일도 없다.
    func cancel(_ key: String) async {
        _ = try? await request("cancel", ["key": .string(key)])
    }

    func execute(_ cmd: Int?, arg: JSONValue? = nil) async {
        guard let cmd else { return }
        do {
            var params: [String: JSONValue] = ["cmd": .int(cmd)]
            if let arg { params["arg"] = arg }
            _ = try await request("execute", params)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func set(_ obj: Int?, _ prop: String, _ value: JSONValue) async {
        guard let obj else { return }
        do {
            _ = try await request("set", ["obj": .int(obj), "prop": .string(prop), "value": value])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func imageData(_ id: Int) async -> (asset: String?, data: Data?) {
        guard let result = try? await request("image", ["img": .int(id)]) else { return (nil, nil) }
        let data = result["data"]?.string.flatMap { Data(base64Encoded: $0) }
        return (result["asset"]?.string, data)
    }

    private func describeItems(_ items: [JSONValue]) async {
        for item in items {
            guard let id = item["$obj"]?.int, store.objects[id] == nil, !describing.contains(id) else { continue }
            describing.insert(id)
            await describe(id)
            describing.remove(id)
        }
    }

    // MARK: - 수신

    private func send(_ value: JSONValue) {
        guard var data = try? JSONEncoder().encode(value) else { return }
        data.append(0x0A)
        input?.write(data)
    }

    private func receive(_ data: Data) {
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)

            guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line)) else { continue }
            handle(message)
        }
    }

    private func handle(_ message: JSONValue) {
        if let method = message["method"]?.string {
            let params = message["params"] ?? .null

            if let id = message["id"] {
                // 엔진 → 앱 요청: upstream 코드가 띄우는 대화상자 등
                let result = UiHostHandler.handle(method, params)
                send(.object(["id": id, "result": result]))
            } else {
                handleNotification(method, params)
            }
            return
        }

        guard let id = message["id"]?.int, let continuation = pending.removeValue(forKey: id) else { return }

        if let error = message["error"] {
            continuation.resume(throwing: EngineError(message: error["message"]?.string ?? "엔진 오류", type: error["type"]?.string))
        } else {
            continuation.resume(returning: message["result"] ?? .null)
        }
    }

    private func handleNotification(_ method: String, _ params: JSONValue) {
        switch method {
        case "ready":
            rootId = params["root"]?.refId
            isReady = true
        case "changed":
            store.applyChanged(params)
        case "collection":
            store.applyCollection(params)
            let items = params["items"]?.array ?? []
            Task { await describeItems(items) }
        case "commands":
            store.applyCommands(params)
        case "engineError":
            lastError = params["message"]?.string
        default:
            break
        }
    }
}
