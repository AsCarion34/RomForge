import AppKit
import SwiftUI

/// upstream 값 변환기(엔진에서 실행)와 이미지 표시.
@MainActor
extension EngineClient {
    /// ViewModel 속성에 upstream 변환기를 적용한 결과. 처음에는 nil이고, 결과가 오면 화면이 다시 그려진다.
    /// 예: converted("LevelToColorConverter", vm, "SwitchCompressLevel") → {"$color": "#FF..."}
    func converted(_ converter: String, _ obj: RemoteObject?, _ path: String, parameter: String? = nil, targetType: String? = nil) -> JSONValue? {
        guard let obj else { return nil }
        let top = String(path.split(separator: ".").first ?? "")
        let current = obj.props[top] ?? .null
        let key = "\(converter)|\(obj.id)|\(path)|\(parameter ?? "")|\(targetType ?? "")|\(current)"

        if let value = converterCache[key] { return value }

        if !pendingConversions.contains(key) {
            pendingConversions.insert(key)
            var params: [String: JSONValue] = [
                "converter": .string(converter),
                "source": .object(["obj": .int(obj.id), "path": .string(path)]),
            ]
            if let parameter { params["parameter"] = .string(parameter) }
            if let targetType { params["targetType"] = .string(targetType) }

            Task {
                let result = (try? await request("convert", params)) ?? .null
                converterCache[key] = result
                pendingConversions.remove(key)
            }
        }
        return nil
    }

    /// 값 하나에 upstream 변환기를 적용한 결과(예: 언어 코드 → 국기 이미지). 처음에는 nil.
    func converted(_ converter: String, value: JSONValue, parameter: String? = nil, targetType: String? = nil) -> JSONValue? {
        let key = "\(converter)|value|\(value)|\(parameter ?? "")|\(targetType ?? "")"
        if let cached = converterCache[key] { return cached }

        if !pendingConversions.contains(key) {
            pendingConversions.insert(key)
            var params: [String: JSONValue] = ["converter": .string(converter), "value": value]
            if let parameter { params["parameter"] = .string(parameter) }
            if let targetType { params["targetType"] = .string(targetType) }

            Task {
                converterCache[key] = (try? await request("convert", params)) ?? .null
                pendingConversions.remove(key)
            }
        }
        return nil
    }

    /// 엔진 이미지 참조({"$image":id,"asset":…})를 NSImage로. upstream 리소스 경로면 앱 번들의 같은 파일을 쓴다.
    func image(_ value: JSONValue?) -> NSImage? {
        guard let value else { return nil }

        if let asset = value["asset"]?.string, let image = UpstreamAssets.nsImage(fromAsset: asset) {
            return image
        }

        guard let id = value["$image"]?.int else { return nil }
        if let cached = imageCache[id] { return cached }

        if !pendingImages.contains(id) {
            pendingImages.insert(id)
            Task {
                let (asset, data) = await imageData(id)
                if let data, let image = NSImage(data: data) {
                    imageCache[id] = image
                } else if let asset, let image = UpstreamAssets.nsImage(fromAsset: asset) {
                    imageCache[id] = image
                }
                pendingImages.remove(id)
            }
        }
        return nil
    }
}

/// 엔진 이미지 참조를 그린다(없으면 빈 칸).
struct RemoteImage: View {
    @Environment(EngineClient.self) private var engine
    let value: JSONValue?
    var size: CGFloat? = nil

    var body: some View {
        if let image = engine.image(value) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// upstream 아이콘(PNG) 하나를 그린다.
struct UpstreamIcon: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        UpstreamAssets.image(name)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

extension JSONValue {
    /// {"$color":"#AARRGGBB"} → Color
    var color: Color? {
        guard let hex = self["$color"]?.string else { return nil }
        return Color(hex: hex)
    }
}
