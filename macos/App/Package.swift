// swift-tools-version: 6.0
import PackageDescription

// RomForge macOS 앱(SwiftUI). 로직은 upstream ViewModel을 돌리는 .NET 엔진(macos/Engine)이 맡고,
// 이 앱은 화면과 macOS 연동(대화상자, 드래그앤드롭, 클립보드)만 담당한다.
let package = Package(
    name: "RomForgeMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RomForgeMac",
            path: "Sources/RomForgeMac"
        ),
    ],
    swiftLanguageModes: [.v5]
)
