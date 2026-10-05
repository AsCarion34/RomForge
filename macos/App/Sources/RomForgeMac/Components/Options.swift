import SwiftUI

/// upstream OptionBorder 스타일 상자.
struct OptionCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 6) {
                    if let icon { UpstreamIcon(name: icon, size: 16) }
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 출력 폴더 줄: [사용자 지정 토글] [경로] [찾아보기…]
struct OutputPathRow: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject?
    var toggleProp: String? = "UseCustomOutputPath"
    var pathProp = "OutputPath"
    var browseCommand = "BrowseOutputCommand"
    var toggleTitle = "출력 폴더 변경"
    var placeholder = "원본 파일과 같은 폴더"

    var body: some View {
        // upstream: 경로 TextBox(직접 입력 가능)와 찾아보기 버튼은 IsEnabled="{Binding UseCustomOutputPath}"
        let enabled = toggleProp.map { vm?[$0]?.bool ?? false } ?? true

        HStack(spacing: 10) {
            if let toggleProp {
                Toggle(toggleTitle, isOn: engine.bool(vm, toggleProp))
            } else {
                Text(toggleTitle).foregroundStyle(.secondary)
            }
            TextField(placeholder, text: engine.string(vm, pathProp))
                .textFieldStyle(.roundedBorder)
                .disabled(!enabled)
                .help(vm?.string(pathProp) ?? "")
            Button("찾아보기…") { engine.run(vm, browseCommand) }
                .disabled(!enabled || vm?.ref(browseCommand) == nil || !engine.canRun(vm, browseCommand))
        }
    }
}

/// 숫자 슬라이더 + 값 표시(값 표시는 upstream 변환기를 쓸 수 있다)
struct LevelSlider: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject?
    let prop: String
    let range: ClosedRange<Double>
    var textConverter: String? = nil
    var colorConverter: String? = "LevelToColorConverter"

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: engine.double(vm, prop), in: range, step: 1)
            let text = textConverter.flatMap { engine.converted($0, vm, prop)?.string } ?? vm?[prop]?.string ?? ""
            let color = colorConverter.flatMap { engine.converted($0, vm, prop)?.color } ?? .primary
            // upstream 색(밝은 노랑·청록 등)은 어두운 배경 기준이라, 밝은 모드에서도 보이게 어두운 바탕에 얹는다.
            Text(text)
                .font(.body.monospacedDigit().weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.75), in: Capsule())
                .frame(minWidth: 52)
        }
    }
}

/// enum 속성 선택(라디오/세그먼트). labels가 없으면 enum 이름을 그대로 쓴다.
struct EnumPicker: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject?
    let prop: String
    var labels: [String: String] = [:]
    var style: Style = .segmented

    enum Style { case segmented, radio, menu }

    var body: some View {
        let picker = Picker("", selection: engine.choice(vm, prop)) {
            ForEach(vm?.options(prop) ?? [], id: \.self) { option in
                Text(labels[option] ?? option).tag(option)
            }
        }
        .labelsHidden()

        switch style {
        case .segmented: picker.pickerStyle(.segmented)
        case .radio: picker.pickerStyle(.radioGroup).horizontalRadioGroupLayout()
        case .menu: picker.pickerStyle(.menu)
        }
    }
}

/// 실행·취소 같은 커맨드 버튼(CanExecute를 따른다)
struct CommandButton: View {
    @Environment(EngineClient.self) private var engine
    let title: String
    var systemImage: String? = nil
    let vm: RemoteObject?
    let command: String
    var arg: JSONValue? = nil
    var prominent = false

    var body: some View {
        let button = Button {
            engine.run(vm, command, arg)
        } label: {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .disabled(!engine.canRun(vm, command))

        if prominent { button.buttonStyle(.borderedProminent) } else { button }
    }
}
