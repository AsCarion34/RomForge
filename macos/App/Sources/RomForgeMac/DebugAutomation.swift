import AppKit

/// 개발·CI용 자동 점검. 환경 변수가 있을 때만 동작한다.
///   ROMFORGE_DEBUG_ADD=경로1:경로2   압축 탭에 파일 추가
///   ROMFORGE_DEBUG_RUN=1             추가 후 시작 커맨드 실행, 끝날 때까지 대기
///   ROMFORGE_DEBUG_SNAPSHOT=접두사    단계마다 앱 창을 PNG로 저장(화면 녹화 권한 불필요)
///   ROMFORGE_DEBUG_QUIT=1            끝나면 종료
///   ROMFORGE_DEBUG_TOUR=접두사        모든 탭(하위 탭 포함)을 차례로 열어 PNG로 저장한 뒤 종료
@MainActor
enum DebugAutomation {
    private static let env = ProcessInfo.processInfo.environment
    private static var started = false

    static func runCompressScenario(engine: EngineClient, vmId: Int) async {
        guard !started, env["ROMFORGE_DEBUG_ADD"] != nil || env["ROMFORGE_DEBUG_SNAPSHOT"] != nil else { return }
        started = true

        try? await Task.sleep(for: .seconds(1.5))

        if let add = env["ROMFORGE_DEBUG_ADD"] {
            await engine.call(vmId, "AddPaths", [.strings(add.split(separator: ":").map(String.init))])
            try? await Task.sleep(for: .seconds(1.5))
        }
        snapshot("1-added")

        if env["ROMFORGE_DEBUG_RUN"] == "1", let vm = engine.store.object(vmId) {
            await engine.execute(vm.ref("RunCommand"))

            for _ in 0..<240 {
                try? await Task.sleep(for: .milliseconds(500))
                let statuses = engine.store.items(vm.ref("FileItems")).compactMap { engine.store.object($0.refId)?.string("Status") }
                if !statuses.isEmpty, statuses.allSatisfy({ ["완료", "실패", "미지원", "취소"].contains($0) }) { break }
            }
            try? await Task.sleep(for: .seconds(1))
            snapshot("2-done")
        }

        if env["ROMFORGE_DEBUG_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private static func snapshot(_ name: String) {
        guard let prefix = env["ROMFORGE_DEBUG_SNAPSHOT"] else { return }
        save(to: "\(prefix)-\(name).png")
    }

    static func runTour(appState: AppState, engine: EngineClient) async {
        guard let prefix = env["ROMFORGE_DEBUG_TOUR"], !started else { return }
        started = true
        try? await Task.sleep(for: .seconds(2))

        for tab in AppTab.allCases {
            appState.selectedTab = tab
            try? await Task.sleep(for: .seconds(2.5))
            let name = "\(prefix)-\(String(format: "%02d", tab.rawValue))-\(tab.title)"
            save(to: "\(name).png")

            // 하위 탭: upstream MultiToolTabViewModel.SubTabIndex를 바꾸면 화면이 따라간다.
            guard let root = engine.rootId.flatMap(engine.store.object),
                  let vmId = root.ref(tab.viewModelProperty),
                  let vm = engine.store.object(vmId), vm.props["SubTabIndex"] != nil
            else { continue }

            await engine.observeList(vm.ref("Tools"))
            let count = engine.store.items(vm.ref("Tools")).count
            guard count > 1 else { continue }

            for index in 1..<count {
                await engine.set(vmId, "SubTabIndex", .int(index))
                try? await Task.sleep(for: .seconds(2))
                save(to: "\(name)-\(index).png")
            }
            await engine.set(vmId, "SubTabIndex", .int(0))
        }
        NSApp.terminate(nil)
    }

    private static func save(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }

        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
