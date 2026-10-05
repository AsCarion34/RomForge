// upstream: RomForge/Controls/3DS/InstallTab.xaml(.cs)
// ViewModel: InstallerMainViewModel (Main3DsVM.InstallerVM), InstallMainViewModel (InstallerVM.Install), TitleViewModel
import AppKit
import Observation
import SwiftUI

/// 3DS 신규 게임 설치: 설치할 파일 목록(언어 고정 포함)과 파일 추가·삭제, 설치 / 취소.
/// DataContext는 InstallerMainViewModel(vm)이고 목록은 vm.Install.Items다.
struct ThreeDSInstallTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject
    @State private var selection = Set<Int>()

    var body: some View {
        ChildVM(id: vm.ref("Install")) { install in
            VStack(spacing: 0) {
                list(install)
                Divider()
                footer(install)
            }
            .observeLists(engine, install, ["Items"])
        }
    }

    // MARK: 목록

    private func list(_ install: RemoteObject) -> some View {
        let rows = engine.items(install, "Items")

        return Table(rows, selection: $selection) {
            TableColumn("타이틀") { item in ThreeDSTitleCell(item: item).cellEnvironment(engine) }
                .width(min: 160, ideal: 220)
            TableColumn("종류") { item in ThreeDSTypeBadge(item: item) }
                .width(90)
            TableColumn("제품 코드") { item in ThreeDSCodeCell(item: item) }
                .width(140)
            TableColumn("") { item in ThreeDSRegionCell(item: item).cellEnvironment(engine) }
                .width(60)
            TableColumn("언어 고정") { item in ThreeDSLanguageCell(item: item).cellEnvironment(engine) }
                .width(100)
            TableColumn("") { item in ThreeDSLockCell(item: item).cellEnvironment(engine) }
                .width(60)
            TableColumn("용량") { item in
                Text(item.string("SizeText"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
            TableColumn("진행률") { item in ThreeDSProgressCell(item: item, textProp: "ProgressText") }
                .width(100)
        }
        .overlay {
            if install.isVisible("HintVisibility") {
                ThreeDSHint(icon: "drag.png", iconSize: 40,
                            title: "파일 또는 폴더를 여기에 드래그&드롭하세요",
                            detail: "3DS 실기에 게임을 설치합니다",
                            badges: ["3DS", "CCI", "CIA", "ZCCI"])
            }
        }
        // ListView IsEnabled="{Binding Install.IsNotInstalling}"
        .modifier(ThreeDSListBehavior(
            selection: $selection,
            enabled: install["IsNotInstalling"]?.bool ?? true,
            rows: rows,
            drop: { paths in addFiles(install, paths.flatMap(ThreeDSFiles.expand)) },
            remove: { ids in remove(install, ids) },
            clear: { engine.invoke(install, "Clear") }
        ))
    }

    // MARK: 하단

    private func footer(_ install: RemoteObject) -> some View {
        let canInstall = vm["CanInstall"]?.bool ?? false

        return HStack(spacing: 6) {
            Group {
                Button { addFilesDialog(install) } label: { IconLabel(title: "파일 추가", icon: "AddFile.png") }
                Button { addFolderDialog(install) } label: { IconLabel(title: "폴더 추가", icon: "AddFolder.png") }
                Button {
                    remove(install, selection)
                    selection.removeAll()
                } label: { IconLabel(title: "선택 삭제", icon: "Delete.png") }
                Button {
                    engine.invoke(install, "Clear")
                    selection.removeAll()
                } label: { IconLabel(title: "전체 삭제", icon: "Clear.png") }
            }
            .disabled(!canInstall)

            Spacer()

            Button { startInstall(install) } label: { IconLabel(title: "설치", icon: "Run.png") }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall)
            Button { cancelInstall() } label: { IconLabel(title: "취소", icon: "Cancel.png") }
                .disabled(!(install["IsInstalling"]?.bool ?? false))
        }
        .padding(8)
    }

    // MARK: code-behind 처리기

    /// Install.AddFiles(paths). 실패하면 Vm.AppendLog("오류: …", Error)
    private func addFiles(_ install: RemoteObject, _ paths: [String]) {
        guard !paths.isEmpty else { return }
        Task {
            if case .failure(let error) = await ThreeDSBridge.call(engine, install.id, "AddFiles", [.strings(paths)]) {
                ThreeDSBridge.log(engine, vm, "오류: \(error.localizedDescription)", "Error")
            }
        }
    }

    /// InstallAddFiles_Click: OpenFileDialog(Title "설치할 파일 선택", Filter InstallMainViewModel.GetFileDialogFilter(), Multiselect)
    private func addFilesDialog(_ install: RemoteObject) {
        Task {
            let filter = await engine.callStatic("RomForge.ViewModels._3DS.InstallMainViewModel", "GetFileDialogFilter")?.string
            let paths = ThreeDSDialogs.openFiles(title: "설치할 파일 선택", filter: filter, multiple: true)
            addFiles(install, paths)
        }
    }

    /// InstallAddFolder_Click: 폴더 선택("추가할 폴더를 선택하세요") → GetFilesSafe(폴더) → AddFiles
    private func addFolderDialog(_ install: RemoteObject) {
        guard let folder = ThreeDSDialogs.openFolder(title: "추가할 폴더를 선택하세요") else { return }
        addFiles(install, ThreeDSFiles.expand(folder))
    }

    /// InstallRemove_Click / Delete 키: Install.RemoveItems(선택 항목)
    private func remove(_ install: RemoteObject, _ ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        engine.invoke(install, "RemoveItems", [EngineClient.refs(ids)])
    }

    /// Install_Click: IsInstalling = true → 목록 순서대로 InstallAsync(항목, _installCts.Token) → IsInstalling = false.
    /// 오류가 나면 "오류: …"를 남기고 멈춘다. 취소(OperationCanceledException)는 조용히 끝낸다.
    private func startInstall(_ install: RemoteObject) {
        let installer = vm
        guard threeDSInstallRuns[installer.id] == nil else { return }   // 이미 설치 중

        let run = ThreeDSInstallRun(key: "3ds.install.\(installer.id)")
        threeDSInstallRuns[installer.id] = run
        let ids = engine.items(install, "Items").map(\.id)

        // Vm.Install.IsInstalling = true (화면에도 바로 반영해 설치 단추를 막는다)
        engine.bool(install, "IsInstalling").wrappedValue = true

        Task {
            do {
                for id in ids where !run.cancelled {
                    _ = try await engine.callThrowing(installer.id, "InstallAsync", [EngineClient.ref(id)],
                                                      options: CallOptions(cancelKey: run.key))
                }
            } catch let error as EngineError where error.isCancellation {
                // catch (OperationCanceledException) { }
            } catch {
                ThreeDSBridge.log(engine, installer, "오류: \(error.localizedDescription)", "Error")
            }

            engine.bool(install, "IsInstalling").wrappedValue = false
            threeDSInstallRuns[installer.id] = nil
        }
    }

    /// InstallCancel_Click: _installCts?.Cancel() — 지금 항목을 멈추고 남은 항목은 건너뛴다.
    private func cancelInstall() {
        guard let run = threeDSInstallRuns[vm.id] else { return }
        run.cancelled = true
        Task { await engine.cancel(run.key) }
    }
}

/// code-behind의 _installCts 자리. 화면이 다시 만들어져도 취소할 수 있게 InstallerMainViewModel 번호로 둔다.
@MainActor
private final class ThreeDSInstallRun {
    let key: String
    var cancelled = false

    init(key: String) { self.key = key }
}

@MainActor private var threeDSInstallRuns: [Int: ThreeDSInstallRun] = [:]

// MARK: - 언어 고정

/// "언어 고정" 열: ComboBox ItemsSource=LanguageCandidates, SelectedItem=ForcedLanguage, 항목 문구는 LanguageLabelConverter
private struct ThreeDSLanguageCell: View {
    @Environment(EngineClient.self) private var engine
    let item: RemoteObject

    var body: some View {
        let listId = item.ref("LanguageCandidates")
        let candidates = engine.store.items(listId).compactMap(\.string)
        let labels = ThreeDSLanguageLabels.shared

        Picker("", selection: engine.choice(item, "ForcedLanguage")) {
            ForEach(candidates, id: \.self) { name in
                Text(labels.label(name)).tag(name)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .help("설치 시 이 언어로 로케일을 고정합니다 (locale.txt 자동 생성). SMDH에 실제로 존재하는 언어만 표시됩니다.")
        .task(id: listId) { await engine.observeList(listId) }
        .task { await labels.load(engine, names: item.options("ForcedLanguage")) }
    }
}

/// upstream LanguageLabelConverter(Locale3dsLanguageToLabelConverter) 결과.
/// 목록 원소(LanguageCandidates의 값)는 이름 문자열로 오므로 valueType으로 열거형 값을 만들어 같은 변환기를 한 번씩 돌려 받아 둔다.
@MainActor
@Observable
private final class ThreeDSLanguageLabels {
    static let shared = ThreeDSLanguageLabels()

    private(set) var labels: [String: String] = [:]
    @ObservationIgnored private var loading = false

    func label(_ name: String) -> String { labels[name] ?? name }

    func load(_ engine: EngineClient, names: [String]) async {
        guard labels.isEmpty, !loading, !names.isEmpty else { return }
        loading = true
        defer { loading = false }

        var result: [String: String] = [:]
        for name in names {
            let params: [String: JSONValue] = [
                "converter": .string("Locale3dsLanguageToLabelConverter"),
                "value": .string(name),
                "valueType": .string("_3DS.Core.Enums.Locale3dsLanguage"),
            ]
            if let text = (try? await engine.request("convert", params))?.string {
                result[name] = text
            }
        }

        labels = result
    }
}
