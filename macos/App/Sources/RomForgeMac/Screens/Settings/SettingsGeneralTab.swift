// upstream: RomForge/Controls/Settings/GeneralSettingsTab.xaml(.cs)
// ViewModel: GeneralSettingsMainViewModel (SettingsMainViewModel.General)
import SwiftUI

/// 일반 설정: 항상 다른 창 위에 표시(Topmost)
struct SettingsGeneralTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: engine.bool(vm, "Topmost")) {
                Text("항상 다른 창 위에 표시").fontWeight(.bold)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
