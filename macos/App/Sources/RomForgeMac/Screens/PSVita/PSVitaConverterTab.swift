// upstream: RomForge/Controls/PSVita/ConverterTab.xaml(.cs)
// ViewModel: RomForge.ViewModels.PSVita.ConverterMainViewModel (PSVitaMainViewModel.ConverterVM), 항목 SourceRowViewModel
import SwiftUI

/// PS Vita > 포맷 변환: PKG → NoNpDrm(ZIP / 폴더, 타이틀 ID별). 키는 같은 이름의 .txt나 NPS zRIF를 upstream이 채운다.
/// 목록(종류 · 타이틀 · 키 · 용량 · 경로)은 upstream CollectionViewSource가 TitleId로 묶고 정렬한다
/// (GroupStyle 머리글: 타이틀 ID · 첫 항목 DisplayTitle · PKG n 개).
struct PSVitaConverterTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        let idle = vm["IsIdle"]?.bool ?? true

        ToolLayout(vm: vm, lists: ["SourceRows", "LogEntries"]) {
            // Border IsEnabled="{Binding IsIdle}": 목록 + 오른쪽 버튼
            HStack(alignment: .top, spacing: 5) {
                rowsTable(idle: idle)
                PSVitaSideButtons(vm: vm)
            }
            .padding(5)
            .disabled(!idle)
        } options: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    PSVitaRadioPair(vm: vm, title: "출력 형식:",
                                    first: ("ZIP (타이틀 ID별)", "OutputZip"),
                                    second: ("폴더 (타이틀 ID별)", "OutputFolder"))

                    // 출력 폴더: OutputPath TextBox(폴더 드롭, OutputHintVisibility 안내) + 폴더 선택(BrowseOutputCommand)
                    FolderPathRow(vm: vm, placeholder: "출력 폴더를 드래그하거나 선택하세요")
                }
                .disabled(!idle)

                // IconButton IsRunning="{Binding IsLocked}" Click="BtnStart_Click"
                RunCancelButton(title: "변환", icon: "Convert.png", isRunning: vm["IsLocked"]?.bool ?? false) {
                    PSVitaUI.startOrCancel(engine, vm)
                }

                ToolProgressBar(vm: vm)
            }
        }
    }

    // MARK: - 목록

    private func rowsTable(idle: Bool) -> some View {
        let rows = engine.items(vm, "SourceRows")
        // 엔진이 기본 컬렉션 뷰 순서(TitleId · Category · ContentIdSuffix 정렬, TitleId 묶음)로 보내고 묶음 기준을 알려 준다.
        let groups = PSVitaRowGroup.make(rows, by: engine.store.groupBy(vm.ref("SourceRows")))

        return Table(of: RemoteObject.self, selection: engine.selectedItem(vm, "SelectedRow")) {
            TableColumn("종류") { row in
                PSVitaCategoryBadge(row: row)
            }
            .width(80)

            TableColumn("타이틀") { row in
                PSVitaTitleCell(row: row)
                    .cellEnvironment(engine)
            }
            .width(min: 160, ideal: 260)

            TableColumn("키") { row in
                PSVitaLicenseCell(row: row,
                                  help: "라이선스 파일 경로(work.bin, *.rif) / zRIF 문자열 (Patch는 비워두면 App의 키를 사용)")
                    .cellEnvironment(engine)
            }
            .width(150)

            TableColumn("용량") { row in
                PSVitaSizeCell(row: row)
            }
            .width(80)

            TableColumn("경로") { row in
                PSVitaPathCell(row: row)
            }
            .width(min: 120, ideal: 200)
        } rows: {
            if let groups {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            TableRow(row)
                        }
                    } header: {
                        PSVitaGroupHeader(group: group)
                    }
                }
            } else {
                ForEach(rows) { row in
                    TableRow(row)
                }
            }
        }
        .overlay {
            if vm.isVisible("EntriesHintVisibility") {
                PSVitaHint(title: "PS Vita PKG 파일/폴더를 여기에 드래그&드롭하세요",
                           details: ["같은 타이틀 ID의 App/Patch/AddCont는 하나로 묶여 NoNpDrm 포맷으로 변환됩니다",
                                     "키(work.bin, *.rif / zRIF 문자열)가 필요합니다 (Patch는 App의 키를 공유할 수 있습니다)"])
            }
        }
        // Root_Drop: await AddPathsAsync(files) — 폴더는 upstream이 *.pkg를 찾아 넣는다
        .dropDestination(for: URL.self) { urls, _ in
            guard idle, !urls.isEmpty else { return false }
            engine.invoke(vm, "AddPathsAsync", [.strings(urls.map(\.path))])
            return true
        }
        // LvPkg_KeyUp(Delete): RemoveSelectedCommand(CanExecute일 때)
        .onDeleteCommand {
            if engine.canRun(vm, "RemoveSelectedCommand") { engine.run(vm, "RemoveSelectedCommand") }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            PSVitaRowMenu(engine: engine, vm: vm, ids: ids)
        }
    }
}

/// 묶음 하나(CollectionViewGroup 자리): 묶음 기준 속성 값(Name)과 그 묶음의 항목(Items, ItemCount)
private struct PSVitaRowGroup: Identifiable {
    let name: String
    var rows: [RemoteObject]
    /// 항목은 한 묶음에만 들어가므로 첫 항목 번호로 구분한다.
    let id: Int

    /// 엔진은 같은 묶음 항목을 모아서 보내므로 연속한 항목을 첫 번째 묶음 기준 값으로 묶는다. 기준이 없으면 nil(묶지 않음).
    @MainActor
    static func make(_ rows: [RemoteObject], by keys: [String]) -> [PSVitaRowGroup]? {
        guard let key = keys.first else { return nil }
        var groups: [PSVitaRowGroup] = []

        for row in rows {
            let name = row[key]?.string ?? ""
            if let last = groups.indices.last, groups[last].name == name {
                groups[last].rows.append(row)
            } else {
                groups.append(PSVitaRowGroup(name: name, rows: [row], id: row.id))
            }
        }
        return groups
    }
}

/// GroupStyle.HeaderTemplate: Name(TitleId) · Items[0].DisplayTitle · "PKG {ItemCount} 개"
/// (XAML의 Run 세 개는 줄바꿈 공백 때문에 한 칸씩 띄어 그려진다)
private struct PSVitaGroupHeader: View {
    let group: PSVitaRowGroup

    var body: some View {
        HStack(spacing: 10) {
            Text(group.name)
                .fontWeight(.bold)
            Text(group.rows.first?.string("DisplayTitle") ?? "")
                .lineLimit(1)
            Text(verbatim: "PKG \(group.rows.count) 개")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}
