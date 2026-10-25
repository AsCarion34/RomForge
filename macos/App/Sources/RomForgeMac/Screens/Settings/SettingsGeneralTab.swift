// upstream: RomForge/Controls/Settings/GeneralSettingsTab.xaml(.cs)
// ViewModel: GeneralSettingsMainViewModel (SettingsMainViewModel.General)
import SwiftUI

/// 일반 설정: 항상 다른 창 위에 표시 / 업데이트 확인 / 효과음(완료·취소·에러 소리 파일).
/// 소리 파일을 바꾸면 ViewModel이 미리 듣기를 재생한다(엔진 쪽).
struct SettingsGeneralTab: View {
    @Environment(EngineClient.self) private var engine
    let vm: RemoteObject

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            slideToggle("항상 다른 창 위에 표시", icon: "Pin.png", isOn: engine.bool(vm, "Topmost"))
            slideToggle("업데이트 확인", icon: "Refresh.png", isOn: engine.bool(vm, "AutoCheckUpdate"))

            VStack(alignment: .leading, spacing: 2) {
                // IsChecked="{Binding IsMuted, Converter=InverseBool}"
                slideToggle("효과음", icon: "Sound.png", isOn: engine.inverseBool(vm, "IsMuted"))

                // Visibility="{Binding IsMuted, Converter=InverseBooleanToVisibilityConverter}"
                if !(vm["IsMuted"]?.bool ?? false) {
                    soundRow(prop: "CompleteSoundPath", hint: "완료 (.mp3, .wav 파일을 드래그&드롭하세요)",
                             browse: "BrowseCompleteSoundCommand")
                    soundRow(prop: "CancelSoundPath", hint: "취소 (.mp3, .wav 파일을 드래그&드롭하세요)",
                             browse: "BrowseCancelSoundCommand")
                    soundRow(prop: "ErrorSoundPath", hint: "에러 (.mp3, .wav 파일을 드래그&드롭하세요)",
                             browse: "BrowseErrorSoundCommand")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// SlideToggleStyle ToggleButton: 아이콘 + SettingTextStyle 문구(굵게, 꺼져 있으면 흐리게)
    private func slideToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                UpstreamIcon(name: icon, size: 18)
                Text(title)
                    .fontWeight(.bold)
                    .foregroundStyle(isOn.wrappedValue ? .primary : .secondary)
            }
        }
        .toggleStyle(SettingsSlideToggleStyle())
    }

    /// 소리 파일 줄: 경로 입력란(드롭하면 첫 파일 — SoundTextBox_PreviewDragOver / XxxSoundTextBox_Drop) + BrowseXxxSoundCommand
    private func soundRow(prop: String, hint: String, browse: String) -> some View {
        SettingsPathField(vm: vm, prop: prop, placeholder: hint, browseCommand: browse,
                          dropValue: SettingsPathField.firstFile)
    }
}
