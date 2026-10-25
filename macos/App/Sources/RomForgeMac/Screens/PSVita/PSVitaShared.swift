// upstream: RomForge/Controls/PSVita/RepackTab.xaml(.cs), RomForge/Controls/PSVita/ConverterTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.PSVita.RepackMainViewModel · ConverterMainViewModel 공용 부분(SourceRowViewModel 셀, 목록 메뉴, 출력 폴더 줄)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 대화상자·Finder·실행

/// PS Vita 하위 탭(리팩 · 포맷 변환)이 같이 쓰는 code-behind 동작(이 폴더 전용).
@MainActor
enum PSVitaUI {
    /// VistaFolderBrowserDialog(Description을 제목으로)
    static func chooseFolder(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// OpenFileDialog. filter는 upstream WPF 필터 문자열 그대로 받고 UiHostHandler와 같은 규칙으로 쓴다
    /// ('*.*'가 있으면 형식을 제한하지 않음).
    static func chooseFile(title: String, filter: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let parts = filter.split(separator: "|", omittingEmptySubsequences: false)
        let patterns = stride(from: 1, to: parts.count, by: 2)
            .flatMap { parts[$0].split(separator: ";") }
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if !patterns.contains("*.*") {
            let types = patterns.compactMap { $0.hasPrefix("*.") ? UTType(filenameExtension: String($0.dropFirst(2))) : nil }
            if !types.isEmpty { panel.allowedContentTypes = types }
        }

        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// MenuItem_OpenFolder_Click: Path.GetDirectoryName(SelectedRow.Path)?.OpenFolder() — 폴더가 있을 때만 연다.
    static func openParentFolder(of path: String) {
        guard !path.isEmpty else { return }
        let dir = (path as NSString).deletingLastPathComponent
        guard !dir.isEmpty, isDirectory(dir) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    /// TxtOutputPath_PreviewDragOver / TxtOutputPath_Drop: 끌어다 놓은 첫 항목이 폴더일 때만 받는다.
    static func droppedFolder(_ urls: [URL]) -> String? {
        guard let path = urls.first?.path, isDirectory(path) else { return nil }
        return path
    }

    /// BtnStart_Click · RunAsync: 실행 중(IsLocked)이면 Cancel(), 아니면 await StartAsync(…).
    /// 단추를 연달아 눌러 StartAsync가 겹치지 않게 exclusive로 부른다(IsLocked가 화면에 오기 전 틈).
    static func startOrCancel(_ engine: EngineClient, _ vm: RemoteObject, _ args: [JSONValue] = []) {
        if vm["IsLocked"]?.bool == true {
            engine.invoke(vm, "Cancel")
            return
        }

        let id = vm.id
        Task {
            do {
                _ = try await engine.callThrowing(id, "StartAsync", args, options: CallOptions(exclusive: true))
            } catch let error as EngineError where error.isCancellation {
                // upstream도 취소는 StartAsync 안에서 로그만 남긴다.
            } catch {
                engine.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - 목록 셀(SourceRowViewModel)

/// 종류 열: CategoryBadgeColor 바탕의 Category 배지
struct PSVitaCategoryBadge: View {
    let row: RemoteObject

    var body: some View {
        Text(row.string("Category"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(row["CategoryBadgeColor"]?.color ?? .gray, in: RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: .infinity)
    }
}

/// 타이틀 열: IconImageSource(32) + DisplayTitle(툴팁) / TitleId.
/// RemoteImage가 엔진 환경을 읽으므로 셀에서는 .cellEnvironment(engine)을 붙인다.
struct PSVitaTitleCell: View {
    let row: RemoteObject

    var body: some View {
        HStack(spacing: 8) {
            RemoteImage(value: row["IconImageSource"], size: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.string("DisplayTitle"))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .help(row.string("DisplayTitle"))
                Text(row.string("TitleId"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 키 열: License TextBox(UpdateSourceTrigger=PropertyChanged) + License_Drop(첫 파일 경로를 License에).
/// 셀에서는 .cellEnvironment(engine)을 붙인다.
struct PSVitaLicenseCell: View {
    @Environment(EngineClient.self) private var engine
    let row: RemoteObject
    /// 리팩: IsEnabled="{Binding IsLicenseEditable}", 포맷 변환: 항상 입력 가능
    var editable = true
    let help: String

    var body: some View {
        TextField("", text: engine.string(row, "License"))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .disabled(!editable)
            .help(help)
            .dropDestination(for: URL.self) { urls, _ in
                guard editable, let url = urls.first else { return false }
                engine.string(row, "License").wrappedValue = url.path
                return true
            }
    }
}

/// 용량 열(오른쪽 정렬)
struct PSVitaSizeCell: View {
    let row: RemoteObject

    var body: some View {
        Text(row.string("Size"))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// 경로 열(툴팁 Path)
struct PSVitaPathCell: View {
    let row: RemoteObject

    var body: some View {
        Text(row.string("Path"))
            .lineLimit(1)
            .truncationMode(.middle)
            .help(row.string("Path"))
    }
}

// MARK: - 목록 주변

/// 메뉴 항목(MenuItem.Icon). 메뉴는 AppKit이 그려 크기를 정한 아이콘 사본을 쓴다.
struct PSVitaMenuLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            UpstreamAssets.menuImage(icon, size: 16)
        }
    }
}

/// ListView.ContextMenu(리팩 · 포맷 변환 같음): 폴더 열기 | 선택 삭제 · 전체 삭제.
/// LvPkg_ContextMenuOpening: 선택한 행이 없으면 메뉴를 열지 않는다. WPF처럼 오른쪽 클릭한 행을 SelectedRow로 맞춘 뒤 실행한다.
struct PSVitaRowMenu: View {
    let engine: EngineClient
    let vm: RemoteObject
    let ids: Set<Int>

    var body: some View {
        if let target = ids.first ?? vm.ref("SelectedRow") {
            Button {
                engine.selectedItem(vm, "SelectedRow").wrappedValue = target
                // MenuItem_OpenFolder_Click
                PSVitaUI.openParentFolder(of: engine.store.object(target)?.string("Path") ?? "")
            } label: {
                PSVitaMenuLabel(title: "폴더 열기", icon: "AddFolder.png")
            }

            Divider()

            // Command="{Binding RemoveSelectedCommand}"
            Button {
                let removeCommand = vm.ref("RemoveSelectedCommand")
                let vmId = vm.id
                Task {
                    await engine.set(vmId, "SelectedRow", EngineClient.ref(target))
                    await engine.execute(removeCommand)
                }
            } label: {
                PSVitaMenuLabel(title: "선택 삭제", icon: "Delete.png")
            }

            // Command="{Binding RemoveAllCommand}"
            Button {
                engine.run(vm, "RemoveAllCommand")
            } label: {
                PSVitaMenuLabel(title: "전체 삭제", icon: "Clear.png")
            }
            .disabled(!engine.canRun(vm, "RemoveAllCommand"))
        }
    }
}

/// 빈 목록 안내(EntriesHintVisibility). IsHitTestVisible=False라 클릭·드롭은 아래 목록으로 간다.
struct PSVitaHint: View {
    let title: String
    var details: [String] = []

    var body: some View {
        VStack(spacing: 6) {
            UpstreamIcon(name: "Info.png", size: 28)
            Text(title).font(.headline)
            ForEach(details, id: \.self) { detail in
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// 목록 오른쪽 버튼: 선택 삭제 · 모두 삭제
struct PSVitaSideButtons: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        VStack(spacing: 8) {
            ToolIconButton(icon: "Delete.png", help: "선택 삭제", enabled: engine.canRun(vm, "RemoveSelectedCommand")) {
                engine.run(vm, "RemoveSelectedCommand")
            }
            ToolIconButton(icon: "Clear.png", help: "모두 삭제", enabled: engine.canRun(vm, "RemoveAllCommand")) {
                engine.run(vm, "RemoveAllCommand")
            }
        }
        .frame(width: 40)
    }
}

// MARK: - 옵션

/// 같은 GroupName의 RadioButton 두 개(각각 bool 속성). 하나를 고르면 WPF가 다른 하나를 끄므로 둘 다 설정한다.
struct PSVitaRadioPair: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    let title: String
    let first: (label: String, prop: String)
    let second: (label: String, prop: String)

    var body: some View {
        HStack(spacing: 10) {
            Text(title).fontWeight(.semibold)
            Picker("", selection: selection) {
                Text(first.label).tag(0)
                Text(second.label).tag(1)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .fixedSize()
        }
    }

    private var selection: Binding<Int> {
        Binding(
            get: { vm[first.prop]?.bool == true ? 0 : (vm[second.prop]?.bool == true ? 1 : -1) },
            set: { index in
                let (on, off) = index == 0 ? (first.prop, second.prop) : (second.prop, first.prop)
                engine.bool(vm, on).wrappedValue = true
                engine.bool(vm, off).wrappedValue = false
            })
    }
}

/// 작업(출력) 폴더 줄: OutputPath TextBox(폴더 드롭) + 안내 문구(OutputHintVisibility 자리 = placeholder) + 폴더 선택(BrowseOutputCommand)
struct PSVitaOutputPathRow: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    let placeholder: String

    var body: some View {
        HStack(spacing: 5) {
            TextField(placeholder, text: engine.string(vm, "OutputPath"))
                .textFieldStyle(.roundedBorder)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let folder = PSVitaUI.droppedFolder(urls) else { return false }
                    engine.string(vm, "OutputPath").wrappedValue = folder
                    return true
                }
            ToolIconButton(icon: "AddFolder.png", enabled: engine.canRun(vm, "BrowseOutputCommand")) {
                engine.run(vm, "BrowseOutputCommand")
            }
        }
    }
}
