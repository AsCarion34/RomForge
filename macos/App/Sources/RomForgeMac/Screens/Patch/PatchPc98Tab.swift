// upstream: RomForge/Controls/Patch/Pc98Tab.xaml(.cs)
// ViewModel: Pc98PatchMainViewModel
import AppKit
import SwiftUI

/// 패치 > PC98 탭: 원본 HDI · 한글패치(폴더/ZIP) + 안내 + 이 탭의 로그 + 진행률.
struct PatchPc98Tab: View {
    @Environment(EngineClient.self) private var engine
    let vmId: Int?

    var body: some View {
        ChildVM(id: vmId) { vm in
            let idle = PatchUI.rootIsIdle(engine)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) {
                    PatchDropZone(enabled: idle, tooltip: vm.string("SourcePath"),
                                  onDrop: { engine.string(vm, "SourcePath").wrappedValue = $0[0] },  // SourceDrop_Drop
                                  onClick: { pickSource(vm) }) {
                        PatchZoneLabel(icon: "AddFile.png", text: vm.string("SourceLabel"), caption: "원본 HDI")
                    }
                    PatchDropZone(enabled: idle, tooltip: vm.string("PatchPath"),
                                  onDrop: { dropPatch(vm, $0[0]) },
                                  onClick: { pickPatch(vm) }) {
                        PatchZoneLabel(icon: "Patch.png", text: vm.string("PatchLabel"), caption: "한글패치 (폴더/ZIP)")
                    }
                }
                .frame(height: 50)

                HStack(spacing: 8) {
                    UpstreamIcon(name: "Patch.png", size: 16)
                    Text("HDI(FAT12/16) 내부 파일을 논리 경로로 찾아 교체합니다. 마운트 경로는 자동으로 감지됩니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                .padding(.top, 5)

                // 이 탭 안의 ListBox ItemsSource="{Binding PatchVM.Pc98VM.LogEntries}"(메시지만)
                List(engine.items(vm, "LogEntries")) { entry in
                    Text(entry.string("Message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)

                PatchProgressFooter(label: vm.string("ProgressLabel"),
                                    percent: vm.string("ProgressPercent"),
                                    value: vm["ProgressPct"]?.double ?? 0)
            }
            .padding(5)
            .observeLists(engine, vm, ["LogEntries"])
        }
    }

    /// SourceDrop_Click
    private func pickSource(_ vm: RemoteObject) {
        if let path = PatchUI.choosePath(title: "원본 HDI 선택", filter: "PC98 디스크 이미지|*.hdi;*.nhd;*.thd|모든 파일|*.*") {
            engine.string(vm, "SourcePath").wrappedValue = path
        }
    }

    /// PatchDrop_Click
    private func pickPatch(_ vm: RemoteObject) {
        if let path = PatchUI.choosePath(title: "한글패치 ZIP 선택", filter: "ZIP 파일|*.zip|모든 파일|*.*") {
            engine.string(vm, "PatchPath").wrappedValue = path
        }
    }

    /// PatchDrop_Drop: 폴더나 .zip이면 그대로, 아니면 그 파일이 있는 폴더
    private func dropPatch(_ vm: RemoteObject, _ path: String) {
        let isZip = (path as NSString).pathExtension.lowercased() == "zip"
        let value = PatchUI.isDirectory(path) || isZip ? path : (path as NSString).deletingLastPathComponent
        engine.string(vm, "PatchPath").wrappedValue = value
    }
}
