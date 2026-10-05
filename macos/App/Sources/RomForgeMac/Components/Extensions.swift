import SwiftUI

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension Color {
    /// "#AARRGGBB" 배경이 밝은지(글자색을 검정으로 바꿀지)
    static func isLight(hex: String?) -> Bool {
        guard let hex, hex.hasPrefix("#"), let v = UInt64(hex.dropFirst(), radix: 16) else { return false }
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6
    }

    /// 엔진이 보내는 "#AARRGGBB"(또는 "#RRGGBB") 문자열
    init(hex: String?) {
        guard let hex, hex.hasPrefix("#"), let v = UInt64(hex.dropFirst(), radix: 16) else {
            self = .gray
            return
        }
        let hasAlpha = hex.count == 9
        let a = hasAlpha ? Double((v >> 24) & 0xFF) / 255 : 1
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255,
                     opacity: a)
    }
}

extension View {
    /// Table 셀에 엔진을 다시 넣는다. 행이 지워질 때 SwiftUI가 셀을 상위 환경 없이 한 번 더 갱신하는데,
    /// 그때 @Environment(EngineClient.self)를 읽는 뷰(엔진 바인딩 Picker, RemoteImage 등)가 "No Observable object"로 멈춘다.
    func cellEnvironment(_ engine: EngineClient) -> some View {
        environment(engine)
    }
}
