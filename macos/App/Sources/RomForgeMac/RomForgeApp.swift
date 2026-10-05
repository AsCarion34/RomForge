import AppKit
import SwiftUI

@main
struct RomForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine = EngineClient()
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("RomForge") {
            ContentView()
                .environment(engine)
                .environment(appState)
                .frame(minWidth: 960, minHeight: 620)
                .task { engine.start() }
        }
        // upstream MainWindow는 900×715이고 탭이 위에 있다. 여기는 왼쪽에 탭 목록(약 170)이 있어 그만큼 넓게 연다.
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("키 파일 폴더 열기") {
                    // upstream은 키 파일(prod.keys 등)을 실행 파일 옆에서 찾는다 → 엔진 폴더
                    let dir = EngineLocator.engineDirectory
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 앱 번들 없이(swift run) 실행해도 일반 앱처럼 Dock·메뉴가 보이게 한다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
