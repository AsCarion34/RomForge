// upstream: RomForge/Controls/Patch/NormalTab.xaml(.cs), RomForge.Core/Services/Patch/PatchVersionInfoExtractor.cs(DefaultNamingFormat)
// ViewModel: NormalPatchMainViewModel, PatchSlotViewModel, SourceHashViewModel
import AppKit
import SwiftUI

/// 패치 > 일반 탭.
/// Loaded에서 NormalVM.RequestSourceSelectionAsync(압축 안 원본 후보 선택 창)와
/// SourceHash.RequestGdRomLayoutAsync(GD-ROM CHD 해시 기준 선택 창)를 거는 부분은 PatchDialogs.bind가 한다.
struct PatchNormalTab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?

    @State private var namingHover = false

    /// NormalTab.xaml.cs의 PatchExtensions.AllowedExtensions(code-behind 전용 상수)
    private static let patchExtensions = [".ips", ".bps", ".ups", ".ppf", ".aps", ".xdelta", ".dcp"]
    /// NormalTab.xaml.cs의 PatchExtensions.FileFilter
    private static var patchFilter: String {
        "패치 파일|\(patchExtensions.map { "*" + $0 }.joined(separator: ";"))|모든 파일|*.*"
    }
    /// PatchVersionInfoExtractor.DefaultNamingFormat(const라 브리지로 읽을 수 없어 값을 옮겨 적는다)
    private static let defaultNamingFormat = "{fileName} (v{Version}_{Date:yyMMdd})"

    var body: some View {
        ChildVM(id: vmId) { vm in
            VStack(alignment: .leading, spacing: 5) {
                dropZones(vm)
                sourceSection(vm)
                if vm["HintsVisible"]?.bool == true {
                    formatsHint(icon: "Patch.png", title: "지원 패치 포맷:",
                                formats: ["IPS", "BPS", "UPS", "PPF", "APS", "Xdelta", "DCP"])
                }
                Spacer(minLength: 0)
                options(vm)
                PatchProgressFooter(label: vm.string("ProgressLabel"),
                                    percent: vm.string("ProgressPercent"),
                                    speed: vm.string("ProgressSpeed"),
                                    time: vm.string("ProgressTime"),
                                    value: vm["ProgressPct"]?.double ?? 0)
            }
            .padding(5)
            .observeLists(engine, vm, ["PatchSlots"])
            .task(id: vm.ref("SourceHash")) {
                // Loaded: 원본 후보 선택·GD-ROM 해시 기준 창을 ViewModel의 Func 속성에 건다.
                await PatchDialogs.bind(engine, normalVM: vm.id, sourceHash: vm.ref("SourceHash"))

                // 해시 상자는 원본을 고르는 즉시 나타나므로 미리 받아 둔다.
                guard let hashId = vm.ref("SourceHash"), let hash = await engine.describe(hashId) else { return }
                await engine.observeList(hash.ref("Entries"))
            }
        }
    }

    // MARK: - 원본 · 패치 DropZone

    private func dropZones(_ vm: RemoteObject) -> some View {
        let idle = PatchUI.rootIsIdle(engine)
        let isMulti = vm["IsMultiPatch"]?.bool ?? false

        return HStack(alignment: .top, spacing: 2) {
            PatchDropZone(enabled: idle, tooltip: vm.string("SourcePath"),
                          onDrop: { dropOnSource(vm, $0) }, onClick: { pickSource(vm) }) {
                PatchZoneLabel(icon: "AddFile.png", text: vm.string("SourceLabel"), caption: "원본")
            }
            .frame(minHeight: isMulti ? 38 : 50, maxHeight: isMulti ? .infinity : 50)

            patchColumn(vm, idle: idle, isMulti: isMulti)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func patchColumn(_ vm: RemoteObject, idle: Bool, isMulti: Bool) -> some View {
        let slots = engine.items(vm, "PatchSlots")

        return VStack(spacing: 3) {
            if vm["HintsVisible"]?.bool == true, let first = slots.first {
                PatchDropZone(enabled: idle, tooltip: first.string("FilePath"),
                              onDrop: { dropOnSlot(vm, first, $0) }, onClick: { pickPatch(first) }) {
                    PatchZoneLabel(icon: "Patch.png", text: first.string("Label"), caption: "패치")
                }
                .frame(height: 50)
            }

            if isMulti {
                ForEach(slots) { slot in
                    PatchDropZone(enabled: idle, tooltip: slot.string("FilePath"),
                                  onDrop: { dropOnSlot(vm, slot, $0) }, onClick: { pickPatch(slot) }) {
                        slotLabel(slot)
                    }
                    .frame(height: 38)
                }
            }
        }
        .overlay(alignment: isMulti ? .topTrailing : .bottomTrailing) {
            // AddPatch_Click
            ToolIconButton(icon: "Insert.png", help: "연속으로 적용할 패치 추가",
                           enabled: idle && (vm["CanAddPatch"]?.bool ?? false)) {
                engine.invoke(vm, "AddPatchSlot")
            }
            .padding(isMulti ? EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 6)
                             : EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 6))
        }
        .frame(maxWidth: .infinity)
    }

    /// 여러 패치 모드의 슬롯 한 줄: 가운데 [아이콘 + Label], 오른쪽 Title("패치 1"). 오른쪽 36pt는 추가 버튼 자리.
    private func slotLabel(_ slot: RemoteObject) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            UpstreamIcon(name: "Patch.png", size: 20)
            Text(slot.string("Label"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(slot.string("Title"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .padding(.leading, 10)
        .padding(.trailing, 36)
    }

    // MARK: - code-behind 동작

    /// NormalSourceDrop_Click
    private func pickSource(_ vm: RemoteObject) {
        if let path = PatchUI.choosePath(title: "원본 파일 선택") {
            engine.string(vm, "SourcePath").wrappedValue = path
        }
    }

    /// NormalPatchDrop_Click
    private func pickPatch(_ slot: RemoteObject) {
        if let path = PatchUI.choosePath(title: "패치 파일 선택", filter: Self.patchFilter) {
            engine.string(slot, "FilePath").wrappedValue = path
        }
    }

    /// NormalSourceDrop_Drop: 패치 확장자 파일은 첫 슬롯으로, 나머지는 원본으로
    private func dropOnSource(_ vm: RemoteObject, _ paths: [String]) {
        dropOnSlot(vm, engine.items(vm, "PatchSlots").first, paths)
    }

    /// NormalPatchDrop_Drop: 패치 확장자 파일은 그 슬롯으로, 나머지는 원본으로
    private func dropOnSlot(_ vm: RemoteObject, _ slot: RemoteObject?, _ paths: [String]) {
        let patches = paths.filter { Self.patchExtensions.contains("." + ($0 as NSString).pathExtension.lowercased()) }
        let sources = paths.filter { !patches.contains($0) }

        if let patch = patches.first, let slot {
            engine.string(slot, "FilePath").wrappedValue = patch
        }
        if let source = sources.first {
            engine.string(vm, "SourcePath").wrappedValue = source
        }
    }

    // MARK: - 원본 해시 · 안내

    @ViewBuilder
    private func sourceSection(_ vm: RemoteObject) -> some View {
        if vm["HasSource"]?.bool == true {
            if let hash = engine.store.object(vm.ref("SourceHash")) {
                PatchSourceHashBox(hash: hash)
            }
        } else if vm["SourceHintVisible"]?.bool == true {
            formatsHint(icon: "AddFile.png", title: "원본 자동 압축해제 지원 포맷:",
                        formats: ["ZIP", "RAR", "7Z", "CHD", "RVZ"])
        }
    }

    private func formatsHint(icon: String, title: String, formats: [String]) -> some View {
        HStack(spacing: 6) {
            UpstreamIcon(name: icon, size: 16)
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(formats, id: \.self) { PatchFormatBadge(text: $0) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
    }

    // MARK: - 옵션(자동 압축 · 파일명 표기)

    private func options(_ vm: RemoteObject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: engine.bool(vm, "AutoCompress")) {
                HStack(spacing: 16) {
                    Text("패치 후 자동 압축").bold()
                    compressMapping("BIN / IMG / ISO", "CHD")
                    compressMapping("3DS / CCI / CIA", "ZCCI")
                    compressMapping("GCM / Wii / WBFS", "RVZ")
                    compressMapping("이외 기타", "ZIP")
                }
            }

            namingSection(vm)
        }
    }

    private func compressMapping(_ from: String, _ to: String) -> some View {
        HStack(spacing: 4) {
            PatchFormatBadge(text: from)
            Text("➔").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            PatchFormatBadge(text: to)
        }
    }

    /// upstream은 이 묶음 위에 마우스가 있을 때(IsMouseOver)만 형식 입력·예상 파일명을 보여 준다.
    private func namingSection(_ vm: RemoteObject) -> some View {
        let enabled = vm["NamingEnabled"]?.bool ?? false

        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: engine.bool(vm, "NamingEnabled")) {
                HStack(spacing: 12) {
                    Text("결과 파일명에 버전/날짜 자동 표기").bold()
                    Text("패치 파일명에서 버전과 날짜를 읽어와 결과 파일명에 표시합니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if namingHover {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        TextField("", text: engine.string(vm, "NamingFormat"))
                            .textFieldStyle(.roundedBorder)
                            .help("사용 가능한 값: {fileName}, {Version}, {Date:yyMMdd}")
                            .disabled(!enabled)
                        // ResetNamingFormat_Click
                        IconButton(title: "초기화", icon: "Clear.png", enabled: enabled) {
                            engine.string(vm, "NamingFormat").wrappedValue = Self.defaultNamingFormat
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Text("{fileName}, {Version}, {Date:yyMMdd} 형식이 올바르지 않으면 기본값으로 대체됩니다")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 0) {
                    Text("예상 파일명: ")
                    Text(vm.string("NamingPreview"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .font(.caption.weight(.semibold))
                .help(vm.string("NamingPreview"))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .contentShape(Rectangle())
        .onHover { namingHover = $0 }
    }
}

/// 원본 해시 상자(DataContext="{Binding PatchVM.NormalVM.SourceHash}")
private struct PatchSourceHashBox: View {
    @Environment(EngineClient.self) private var engine
    let hash: RemoteObject

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if hash["IsCalculating"]?.bool == true {
                Text(hash.string("CalculatingText")).foregroundStyle(.secondary)
            }
            if hash["IsCancelled"]?.bool == true {
                Text("패치 시작으로 해시 계산이 취소되었습니다").foregroundStyle(.secondary)
            }
            if hash["HasError"]?.bool == true {
                Text("해시 계산 실패").foregroundStyle(.red)
            }
            if hash["HasEntries"]?.bool == true {
                ScrollView {
                    entriesGrid
                }
                .frame(maxHeight: 130)
                .fixedSize(horizontal: false, vertical: true)
            }
            if hash["HasSkipped"]?.bool == true {
                Text(hash.string("SkippedText"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
    }

    private var entriesGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
            GridRow {
                Text("파일명")
                Text("CRC32")
                Text("MD5")
                Text("SHA-1")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)

            Divider()

            ForEach(engine.items(hash, "Entries")) { entry in
                GridRow {
                    Text(entry.string("Name"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(entry.string("Name"))
                        .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                    Text(entry.string("Crc32")).font(.system(.caption, design: .monospaced))
                    Text(entry.string("Md5")).font(.system(.caption, design: .monospaced))
                    Text(entry.string("Sha1")).font(.system(.caption, design: .monospaced))
                }
                .textSelection(.enabled)
            }
        }
    }
}
