// upstream: RomForge/Controls/Patch/VitaTab.xaml(.cs)
// ViewModel: VitaPatchMainViewModel, VitaSourceRowViewModel
import AppKit
import SwiftUI

/// 패치 > PS Vita 탭: pkg·zip·폴더 목록(종류·타이틀·키·패치·용량·경로) + 출력 포맷 · 병합 · 작업 폴더.
struct PatchVitaTab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?
    /// XAML의 {Binding PatchVM.IsIdle}
    let patchIdle: Bool

    var body: some View {
        ChildVM(id: vmId) { vm in
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 5) {
                    rowsTable(vm)
                    sideButtons(vm)
                }
                .padding(5)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .disabled(!patchIdle)
                .frame(maxHeight: .infinity)

                outputOptions(vm)

                PatchProgressFooter(label: vm.string("ProgressLabel"),
                                    percent: vm.string("ProgressPercent"),
                                    speed: vm.string("ProgressSpeed"),
                                    time: vm.string("ProgressTime"),
                                    value: vm["ProgressPct"]?.double ?? 0)
            }
            .padding(5)
            .observeLists(engine, vm, ["SourceRows"])
        }
    }

    // MARK: - 목록

    private func rowsTable(_ vm: RemoteObject) -> some View {
        Table(engine.items(vm, "SourceRows"), selection: engine.selectedItem(vm, "SelectedRow")) {
            TableColumn("종류") { row in
                Text(row.string("Category"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(row["CategoryBadgeColor"]?.color ?? .gray, in: RoundedRectangle(cornerRadius: 4))
                    .frame(maxWidth: .infinity)
            }
            .width(80)

            TableColumn("타이틀") { row in
                HStack(spacing: 8) {
                    RemoteImage(value: row["IconImageSource"], size: 32)
                        // Table 셀은 행이 지워질 때 상위 환경 없이 한 번 더 갱신된다. 엔진을 다시 넣어 두지 않으면
                        // @Environment(EngineClient.self)를 읽는 RemoteImage가 "No Observable object"로 멈춘다.
                        .environment(engine)
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
            .width(min: 160, ideal: 260)

            TableColumn("키") { row in
                licenseCell(row)
            }
            .width(100)

            TableColumn("패치") { row in
                patchCell(row)
            }
            .width(75)

            TableColumn("용량") { row in
                Text(row.string("Size"))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)

            TableColumn("경로") { row in
                Text(row.string("Path"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.string("Path"))
            }
            .width(min: 120, ideal: 210)
        }
        .overlay {
            if vm.isVisible("EntriesHintVisibility") {
                PatchHintOverlay(icon: "drag.png",
                                 title: "PS Vita 파일(pkg, zip)/폴더를 여기에 드래그&드롭하세요",
                                 details: ["App/Patch/AddCont는 자동으로 분류됩니다",
                                           "pkg의 경우 키(work.bin, *.rif / zRIF 문자열)가 필요합니다"])
            }
        }
        // Root_Drop: 파일마다 AddSourceFile(순서대로)
        .dropDestination(for: URL.self) { urls, _ in
            guard patchIdle, !urls.isEmpty else { return false }
            let paths = urls.map(\.path)
            Task {
                for path in paths {
                    await engine.call(vm.id, "AddSourceFile", [.string(path)])
                }
            }
            return true
        }
        // LvPkg_KeyUp(Delete)
        .onDeleteCommand { engine.run(vm, "RemoveSelectedCommand") }
        .contextMenu(forSelectionType: Int.self) { ids in
            rowMenu(vm, ids)
        }
    }

    /// ListView.ContextMenu. LvPkg_ContextMenuOpening: 선택한 행이 없으면 메뉴를 열지 않는다.
    /// WPF처럼 오른쪽 클릭한 행을 SelectedRow로 맞춘 뒤 실행한다.
    @ViewBuilder
    private func rowMenu(_ vm: RemoteObject, _ ids: Set<Int>) -> some View {
        if let target = ids.first ?? vm.ref("SelectedRow") {
            Button {
                select(vm, target)
                // MenuItem_OpenFolder_Click
                if let path = engine.store.object(target)?.string("Path"), !path.isEmpty {
                    NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).deletingLastPathComponent))
                }
            } label: {
                menuLabel("폴더 열기", icon: "AddFolder.png")
            }

            Divider()

            Button {
                select(vm, target)
                // MenuItem_RemovePatch_Click
                if let row = engine.store.object(target) {
                    engine.string(row, "PatchPath").wrappedValue = ""
                }
            } label: {
                menuLabel("한글패치 취소", icon: "Cancel.png")
            }

            Divider()

            Button {
                let removeCommand = vm.ref("RemoveSelectedCommand")
                Task {
                    await engine.set(vm.id, "SelectedRow", EngineClient.ref(target))
                    await engine.execute(removeCommand)
                }
            } label: {
                menuLabel("선택 삭제", icon: "Delete.png")
            }

            Button {
                engine.run(vm, "RemoveAllCommand")
            } label: {
                menuLabel("전체 삭제", icon: "Clear.png")
            }
            .disabled(!engine.canRun(vm, "RemoveAllCommand"))
        }
    }

    private func select(_ vm: RemoteObject, _ rowId: Int) {
        engine.selectedItem(vm, "SelectedRow").wrappedValue = rowId
    }

    private func menuLabel(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
        } icon: {
            UpstreamAssets.menuImage(icon, size: 16)
        }
    }

    /// 키 열: License TextBox(IsLicenseEditable) + License_Drop
    private func licenseCell(_ row: RemoteObject) -> some View {
        let editable = row["IsLicenseEditable"]?.bool ?? true

        return TextField("", text: engine.string(row, "License"))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .disabled(!editable)
            .help("라이선스 파일 경로(work.bin, *.rif) / zRIF 문자열")
            .dropDestination(for: URL.self) { urls, _ in
                guard editable, let url = urls.first else { return false }
                engine.string(row, "License").wrappedValue = url.path
                return true
            }
    }

    /// 패치 열: PatchIconSource 아이콘. 클릭하면 [폴더 선택... | 압축파일 선택(zip/7z)...] 메뉴(PatchDropTarget_Click), 폴더·zip·7z 드롭.
    private func patchCell(_ row: RemoteObject) -> some View {
        Menu {
            Button {
                // PatchMenu_SelectFolder_Click
                if let path = PatchUI.choosePath(title: "한글 패치 폴더 선택", folder: true) {
                    engine.string(row, "PatchPath").wrappedValue = path
                }
            } label: {
                menuLabel("폴더 선택...", icon: "AddFolder.png")
            }
            Button {
                // PatchMenu_SelectArchive_Click
                if let path = PatchUI.choosePath(title: "한글 패치 압축파일 선택",
                                                 filter: "Archive Files (*.zip;*.7z)|*.zip;*.7z|All Files (*.*)|*.*") {
                    engine.string(row, "PatchPath").wrappedValue = path
                }
            } label: {
                menuLabel("압축파일 선택(zip/7z)...", icon: "ZipFolder.png")
            }
        } label: {
            UpstreamAssets.menuImage(PatchUI.assetName(row.string("PatchIconSource")), size: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 32, height: 32)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        .help(row.string("PatchPath"))
        .frame(maxWidth: .infinity)
        // PatchDropTarget_Drop: 폴더 · .zip · .7z만 받는다
        .dropDestination(for: URL.self) { urls, _ in
            guard let path = urls.first?.path else { return false }
            let ext = (path as NSString).pathExtension.lowercased()
            guard PatchUI.isDirectory(path) || ext == "zip" || ext == "7z" else { return false }
            engine.string(row, "PatchPath").wrappedValue = path
            return true
        }
    }

    /// 오른쪽 버튼: 선택 삭제 · 모두 삭제
    private func sideButtons(_ vm: RemoteObject) -> some View {
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

    // MARK: - 출력 옵션

    private func outputOptions(_ vm: RemoteObject) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text("출력 포맷:").fontWeight(.semibold)
                Picker("", selection: outputTarget(vm)) {
                    Text("에뮬 (app, addcont)").tag(0)
                    Text("실기 (rePatch, reAddcont)").tag(1)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }

            Toggle(isOn: engine.bool(vm, "MergePatchIntoGame")) {
                HStack(spacing: 12) {
                    Text("게임에 패치 병합").bold()
                    Text("에뮬: 복호화 후 app/addcont 덮어씌우기 / 실기: rePatch/reAddcont 추가")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 5) {
                TextField("작업 폴더를 선택하세요", text: engine.string(vm, "OutputPath"))
                    .textFieldStyle(.roundedBorder)
                ToolIconButton(icon: "AddFolder.png", enabled: engine.canRun(vm, "BrowseOutputCommand")) {
                    engine.run(vm, "BrowseOutputCommand")
                }
            }
        }
        .disabled(!patchIdle)
    }

    /// RadioButton GroupName="VitaOutputTargetGroup": 하나를 고르면 다른 하나는 꺼진다(BuildEmu / BuildRetail).
    private func outputTarget(_ vm: RemoteObject) -> Binding<Int> {
        Binding(
            get: { vm["BuildEmu"]?.bool == true ? 0 : (vm["BuildRetail"]?.bool == true ? 1 : -1) },
            set: { index in
                let (on, off) = index == 0 ? ("BuildEmu", "BuildRetail") : ("BuildRetail", "BuildEmu")
                engine.bool(vm, on).wrappedValue = true
                engine.bool(vm, off).wrappedValue = false
            })
    }
}
