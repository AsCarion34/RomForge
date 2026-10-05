// upstream: RomForge/Controls/Util/HashTab.xaml(.cs)
// ViewModel: HashMainViewModel (UtilMainViewModel.HashVM)
import SwiftUI

/// Hash 계산: 알고리즘·대소문자 선택 / 파일 목록(결과·복사) / 버튼
struct UtilHashTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()

    /// IsEnabled="{Binding IsLocked, Converter=InverseBool}"
    private var isUnlocked: Bool { !(vm["IsLocked"]?.bool ?? false) }

    var body: some View {
        ToolLayout(vm: vm) {
            VStack(spacing: 0) {
                optionBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
                fileList
            }
        } options: {
            HStack(spacing: 6) {
                IconButton(title: "파일 추가", icon: "AddFile.png", enabled: isUnlocked) {
                    UtilFileActions.addFiles(engine, vm, filterType: "HashMainViewModel")
                }
                IconButton(title: "폴더 추가", icon: "AddFolder.png", enabled: isUnlocked) {
                    UtilFileActions.addFolder(engine, vm)
                }
                IconButton(title: "선택 삭제", icon: "Delete.png", enabled: isUnlocked) {
                    UtilFileActions.remove(engine, vm, selection)
                    selection.removeAll()
                }
                IconButton(title: "전체 삭제", icon: "Clear.png", enabled: isUnlocked) {
                    UtilFileActions.clear(engine, vm)
                    selection.removeAll()
                }

                Spacer()

                CommandIconButton(title: "시작", icon: "Run.png", vm: vm, command: "RunCommand", enabled: isUnlocked, prominent: true)
                CommandIconButton(title: "취소", icon: "Cancel.png", vm: vm, command: "CancelCommand", enabled: !isUnlocked)
            }
        }
    }

    /// 알고리즘 : CRC-32 / MD5 / SHA-1 / SHA-256 / BLAKE3 | 옵션 : 소문자 / 대문자
    /// (code-behind RadioButton_Checked가 Tag로 SelectedAlgorithm을 바꾸던 것을 enum 바인딩으로 옮김)
    private var optionBar: some View {
        HStack(spacing: 10) {
            UpstreamIcon(name: "Neural.png", size: 16)
            Text("알고리즘 :").fontWeight(.bold).foregroundStyle(.secondary)
            EnumPicker(vm: vm, prop: "SelectedAlgorithm",
                       labels: ["CRC32": "CRC-32", "MD5": "MD5", "SHA1": "SHA-1", "SHA256": "SHA-256", "BLAKE3": "BLAKE3"],
                       style: .radio)

            Divider().frame(height: 18).padding(.horizontal, 5)

            UpstreamIcon(name: "FontSize.png", size: 16)
            Text("옵션 :").fontWeight(.bold).foregroundStyle(.secondary)
            Picker("", selection: engine.bool(vm, "UseUpperCase")) {
                HStack(spacing: 3) {
                    UpstreamIcon(name: "LowerA.png", size: 16)
                    Text("소문자")
                }
                .tag(false)
                HStack(spacing: 3) {
                    UpstreamIcon(name: "UpperA.png", size: 16)
                    Text("대문자")
                }
                .tag(true)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()

            Spacer(minLength: 0)
        }
        .disabled(!isUnlocked)
    }

    private var fileList: some View {
        Table(engine.items(vm, "FileItems"), selection: $selection) {
            TableColumn("No.") { item in
                Text(item.string("No"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(min: 36, ideal: 50)

            TableColumn("파일명") { item in
                Text(item.string("FileName"))
                    .lineLimit(1)
                    .help(item.string("FilePath"))
            }
            .width(min: 140, ideal: 280)

            TableColumn("용량") { item in Text(item.string("FileSize")).monospacedDigit() }
                .width(min: 70, ideal: 90)

            TableColumn("진행률") { item in UtilProgressCell(item: item) }
                .width(min: 100, ideal: 120)

            TableColumn("결과") { item in
                HStack(spacing: 8) {
                    Text(item.string("HashResult"))
                        .font(.body.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if item["IsHashAvailable"]?.bool == true {
                        Button {
                            copyHash(item)
                        } label: {
                            UpstreamIcon(name: item["IsCopied"]?.bool == true ? "Check.png" : "Copy.png", size: 18)
                        }
                        .buttonStyle(.borderless)
                        .help("해시값 복사")
                    }
                }
            }
            .width(min: 200, ideal: 320)
        }
        .overlay {
            if vm.isVisible("HintVisibility") {
                UtilHint(title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                         detail: "파일 해시를 계산합니다",
                         badges: ["모든 형식"])
            }
        }
        .modifier(UtilFileListBehavior(engine: engine, vm: vm, selection: $selection, enabled: isUnlocked))
    }

    /// BtnCopyHash_Click: ClipboardHelper.CopyText(HashResult) 후 이 항목만 IsCopied = true
    private func copyHash(_ item: RemoteObject) {
        let hash = item.string("HashResult")
        guard !hash.isEmpty else { return }

        Task {
            await engine.callStatic("RomForge.Core.Services.Util.ClipboardHelper", "CopyText", [.string(hash)])

            for other in engine.items(vm, "FileItems") {
                await engine.set(other.id, "IsCopied", .bool(false))
            }
            await engine.set(item.id, "IsCopied", .bool(true))
        }
    }
}
