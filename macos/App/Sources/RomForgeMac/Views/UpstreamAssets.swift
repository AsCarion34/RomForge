import AppKit
import SwiftUI

/// upstream WPF 앱의 PNG 아이콘을 그대로 쓴다(앱 번들을 만들 때 Resources/UpstreamAssets로 복사한다).
/// upstream이 아이콘을 바꾸면 다음 빌드에 자동으로 반영된다.
enum UpstreamAssets {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> Image {
        if let image = nsImage(name) { return Image(nsImage: image) }
        return Image(systemName: "square.dashed")
    }

    static func nsImage(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }

        for dir in searchDirectories {
            if let image = NSImage(contentsOf: dir.appendingPathComponent(name)) {
                cache[name] = image
                return image
            }
        }
        return nil
    }

    private static var sizedCache: [String: NSImage] = [:]

    /// 메뉴·메뉴 버튼 라벨처럼 AppKit이 그리는 자리용. 그 자리는 SwiftUI 크기 지정(.frame)을 무시하고
    /// 원본 PNG 크기(수백 px)로 그려 화면을 밀어내므로, 크기를 정한 사본을 쓴다.
    static func menuImage(_ name: String, size: CGFloat = 16) -> Image {
        let key = "\(name)@\(size)"
        if let cached = sizedCache[key] { return Image(nsImage: cached) }
        guard let copy = nsImage(name)?.copy() as? NSImage else { return Image(systemName: "square.dashed") }
        copy.size = NSSize(width: size, height: size)
        sizedCache[key] = copy
        return Image(nsImage: copy)
    }

    /// WPF 리소스 경로("/Assets/Images/X.png", "pack://application:,,,/Common.WPF;component/Assets/Images/X.png")에서 파일 이름만 쓴다.
    static func nsImage(fromAsset asset: String) -> NSImage? {
        guard let name = asset.split(separator: "/").last.map(String.init), name.contains(".") else { return nil }
        return nsImage(name)
    }

    private static var searchDirectories: [URL] {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("UpstreamAssets"))
        }
        // 개발 실행(swift run): ROMFORGE_REPO=저장소 루트
        if let repo = ProcessInfo.processInfo.environment["ROMFORGE_REPO"] {
            let root = URL(fileURLWithPath: repo)
            dirs.append(root.appendingPathComponent("RomForge/Assets/Images"))
            dirs.append(root.appendingPathComponent("Common.WPF/Assets/Images"))
            dirs.append(root.appendingPathComponent("NSW.WPF/Assets/Images"))
        }
        return dirs
    }
}
