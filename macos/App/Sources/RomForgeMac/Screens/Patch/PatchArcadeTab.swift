// upstream: RomForge/Controls/Patch/ArcadeTab.xaml(.cs)
// ViewModel: ArcadePatchMainViewModel, ArcadeMatchItem, PatchEntry, PatchPackage
import AppKit
import SwiftUI

/// 패치 > 아케이드 탭: 원본 ZIP · 패치(IPS/폴더/ZIP) 드롭 → 패치 패키지 선택 → 항목별 매칭 카드.
struct PatchArcadeTab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?

    var body: some View {
        ChildVM(id: vmId) { vm in
            let idle = PatchUI.rootIsIdle(engine)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    // ArcadeSourceDrop_Drop
                    PatchDropZone(enabled: idle, tooltip: vm.string("SourcePath"),
                                  onDrop: { engine.string(vm, "SourcePath").wrappedValue = $0[0] }) {
                        PatchZoneLabel(icon: "ZipFile.png", text: vm.string("SourceLabel"), caption: "원본 ZIP")
                    }
                    // ArcadePatchDrop_Drop
                    PatchDropZone(enabled: idle, tooltip: vm.string("PatchPath"),
                                  onDrop: { engine.string(vm, "PatchPath").wrappedValue = $0[0] }) {
                        PatchZoneLabel(icon: "ZipFolder.png", text: vm.string("PatchLabel"), caption: "패치(IPS/폴더/ZIP)")
                    }
                }
                .frame(height: 50)

                HStack(spacing: 8) {
                    Text("패치 선택:").font(.caption)
                    packagePicker(vm)
                        .help("다른 패치 패키지로 변경")
                }
                .padding(.leading, 4)
                .padding(.top, 4)

                ZStack {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(engine.items(vm, "MatchItems")) { item in
                                PatchArcadeMatchCard(arcade: vm, item: item)
                            }
                        }
                        .padding(2)
                    }

                    if vm.isVisible("HintVisibility") {
                        PatchHintOverlay(icon: "Info.png",
                                         title: "원본 ZIP, 패치(IPS, 폴더, ZIP)를 위에 드래그&드롭하세요",
                                         details: ["확장자 기준으로 자동 매칭됩니다"])
                    }
                }
                .frame(maxHeight: .infinity)

                PatchProgressFooter(label: vm.string("ProgressSummary"),
                                    percent: vm.string("TotalProgressText"),
                                    value: vm["TotalProgress"]?.double ?? 0)
            }
            .padding(5)
            .observeLists(engine, vm, ["MatchItems", "AllPatchEntries", "AvailablePatchPackages"])
        }
    }

    /// ComboBox ItemsSource=AvailablePatchPackages, DisplayMemberPath=DisplayName, SelectedItem=SelectedPatchPackage(양방향)
    private func packagePicker(_ vm: RemoteObject) -> some View {
        let selection = engine.selectedItem(vm, "SelectedPatchPackage")

        return Picker("", selection: selection) {
            if selection.wrappedValue == nil {
                Text("").tag(Int?.none)
            }
            ForEach(engine.items(vm, "AvailablePatchPackages")) { package in
                Text(package.string("DisplayName")).tag(Int?.some(package.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// MatchItems 카드 한 장: 원본 파일 → 패치(드롭 가능) · 패치 바꾸기 · 매칭 여부 · 사유 · 진행률
private struct PatchArcadeMatchCard: View {
    @Environment(EngineClient.self) private var engine
    let arcade: RemoteObject
    let item: RemoteObject

    @State private var targeted = false

    var body: some View {
        let patchName = item["PatchFileName"]?.string
        let matched = item["IsMatched"]?.bool ?? false
        let reason = item["MismatchReason"]?.string ?? ""
        let progress = item["Progress"]?.int ?? 0

        HStack(spacing: 0) {
            nameBox(item.string("SourceFileName"), placeholder: false, border: Color(nsColor: .separatorColor))
                .help(item.string("SourceFileName"))

            Text("→")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(width: 30)

            // MatchCard_PatchDrop: 끌어다 놓은 파일로 PatchEntry를 만들어 ManualMatch
            nameBox(patchName ?? "패치 파일을 드래그&드롭하세요", placeholder: patchName == nil,
                    border: targeted ? Color.accentColor : (patchName == nil ? Color.red.opacity(0.7) : Color(nsColor: .separatorColor)))
                .help(patchName ?? "")
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    manualMatch(path: url.path)
                    return true
                } isTargeted: { targeted = $0 }

            entryPicker
                .frame(width: 140)
                .padding(.leading, 4)
                .help("다른 패치 파일로 변경")

            Text(matched ? "매칭" : "미매칭")
                .font(.caption.weight(.bold))
                .foregroundStyle(matched ? Color.green : Color.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((matched ? Color.green : Color.red).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 80)

            Text(reason)
                .font(.caption2)
                .foregroundStyle(reason == "CRC 일치" ? Color.green : Color.red.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(reason)
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 5)

            HStack(spacing: 4) {
                ProgressView(value: min(max(Double(progress) / 100, 0), 1))
                Text(String(progress) + "%")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }
            .frame(width: 100)
            .padding(.leading, 6)
        }
        .font(.callout)
        .padding(5)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
    }

    private func nameBox(_ text: String, placeholder: Bool, border: Color) -> some View {
        Text(text)
            .foregroundStyle(placeholder ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(border))
    }

    /// ComboBox ItemsSource=AllPatchEntries, SelectedItem=PatchEntry(OneWay) + PatchPicker_SelectionChanged → ManualMatch
    private var entryPicker: some View {
        let current = item.ref("PatchEntry")
        let selection = Binding<Int?>(
            get: { current },
            set: { id in
                // code-behind: 선택이 없거나 지금 항목과 같으면 무시
                guard let id, id != item.ref("PatchEntry") else { return }
                engine.invoke(arcade, "ManualMatch", [EngineClient.ref(item.id), EngineClient.ref(id)])
            })

        return Picker("", selection: selection) {
            if current == nil {
                Text("").tag(Int?.none)
            }
            ForEach(engine.items(arcade, "AllPatchEntries")) { entry in
                Text(entry.string("DisplayName")).tag(Int?.some(entry.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    /// new PatchEntry { DisplayName = Path.GetFileName(path), EntryPath = path } → ArcadeVM.ManualMatch(item, entry)
    private func manualMatch(path: String) {
        let arcadeId = arcade.id
        let itemId = item.id

        Task {
            guard let entry = await engine.create("RomForge.Core.Models.Patch.PatchEntry") else { return }
            await engine.set(entry, "DisplayName", .string((path as NSString).lastPathComponent))
            await engine.set(entry, "EntryPath", .string(path))
            await engine.call(arcadeId, "ManualMatch", [EngineClient.ref(itemId), EngineClient.ref(entry)])
        }
    }
}
