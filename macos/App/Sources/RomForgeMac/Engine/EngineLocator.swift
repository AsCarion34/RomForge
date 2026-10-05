import Foundation

/// 엔진 실행 파일 위치를 정한다.
///   - 개발: 환경 변수 ROMFORGE_ENGINE(엔진 실행 파일 경로), DOTNET_ROOT 사용
///   - 앱 번들: Resources/Engine-<아키텍처>(없으면 Resources/Engine)를 ~/Library/Application Support/RomForge/Engine 으로
///     복사해 거기서 실행한다. upstream 코드는 키 파일(prod.keys 등)·config.json·output 폴더를 실행 파일 옆에서 찾으므로,
///     사용자가 쓸 수 있는 폴더에서 실행해야 Windows 포터블 구조 그대로 동작한다.
enum EngineLocator {
    struct Engine {
        let executable: URL
        let dotnetRoot: String?
    }

    static var engineDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RomForge/Engine", isDirectory: true)
    }

    /// 지금 실행 중인 아키텍처용 엔진(유니버설 앱은 arm64·x86_64 엔진을 함께 담는다)
    private static var bundledEngineName: String {
        #if arch(arm64)
        "Engine-arm64"
        #else
        "Engine-x86_64"
        #endif
    }

    static func prepare() throws -> Engine {
        let env = ProcessInfo.processInfo.environment

        if let path = env["ROMFORGE_ENGINE"] {
            return Engine(executable: URL(fileURLWithPath: path),
                          dotnetRoot: env["DOTNET_ROOT"] ?? NSHomeDirectory() + "/.dotnet")
        }

        guard let resources = Bundle.main.resourceURL else {
            throw EngineError(message: "앱 번들 리소스를 찾을 수 없습니다.")
        }

        let candidates = [bundledEngineName, "Engine"].map { resources.appendingPathComponent($0, isDirectory: true) }
        guard let bundled = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("RomForge").path) }) else {
            throw EngineError(message: "엔진을 찾을 수 없습니다. ROMFORGE_ENGINE 환경 변수를 지정하거나 앱 번들로 실행하세요.")
        }

        try syncEngine(from: bundled, to: engineDirectory)
        return Engine(executable: engineDirectory.appendingPathComponent("RomForge"), dotnetRoot: nil)
    }

    /// 번들의 엔진 파일을 복사한다. 사용자가 넣은 파일(키, 설정, 출력)은 건드리지 않는다.
    private static func syncEngine(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let stamp = destination.appendingPathComponent(".bundle-version")
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev") + "-" + source.lastPathComponent

        if let current = try? String(contentsOf: stamp, encoding: .utf8), current == version {
            return
        }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey])
        while let item = enumerator?.nextObject() as? URL {
            let relative = item.path.dropFirst(source.path.count + 1)
            let target = destination.appendingPathComponent(String(relative))

            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: item, to: target)
                // 인터넷에서 받은 앱은 격리 속성이 붙어 있다. 사용자가 이미 앱 실행을 허용했으므로
                // 엔진 복사본에서는 지워서 엔진 실행이 Gatekeeper에 막히지 않게 한다(가입 없이 배포).
                removexattr(target.path, "com.apple.quarantine", XATTR_NOFOLLOW)
            }
        }

        try version.write(to: stamp, atomically: true, encoding: .utf8)
    }
}
