using System.Windows;

namespace RomForge.Mac.Compat;

/// <summary>
/// 대화상자, 메시지 상자, 클립보드처럼 실제 화면이 필요한 요청을 받아 처리하는 쪽.
/// 엔진이 시작할 때 SwiftUI 앱과 통신하는 구현을 넣는다.
/// </summary>
public interface IUiHost
{
    MessageBoxResult ShowMessageBox(string text, string caption, MessageBoxButton button, MessageBoxImage icon);

    /// <returns>선택한 파일 경로들. 취소하면 null.</returns>
    string[]? ShowOpenFileDialog(FileDialogRequest request);

    /// <returns>저장할 파일 경로. 취소하면 null.</returns>
    string? ShowSaveFileDialog(FileDialogRequest request);

    /// <returns>선택한 폴더 경로들. 취소하면 null.</returns>
    string[]? ShowFolderDialog(FolderDialogRequest request);

    /// <returns>입력한 비밀번호. 취소하면 null.</returns>
    string? PromptPassword(string archivePath, bool wrongPassword);

    bool SetClipboardText(string text);
}

public sealed record FileDialogRequest(
    string? Title,
    string? Filter,
    string? InitialDirectory,
    string? FileName,
    string? DefaultExt,
    bool Multiselect);

public sealed record FolderDialogRequest(
    string? Title,
    string? InitialDirectory,
    bool Multiselect);

public static class UiHost
{
    public static IUiHost? Current { get; set; }
}
