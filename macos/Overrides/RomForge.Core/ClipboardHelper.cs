using RomForge.Mac.Compat;

namespace RomForge.Core.Services.Util;

// upstream RomForge.Core/Services/Util/ClipboardHelper.cs(user32 P/Invoke)의 macOS 대체.
// 공개 API(CopyText)를 upstream과 같게 유지해야 한다.
public static class ClipboardHelper
{
    public static bool CopyText(string text)
    {
        if (string.IsNullOrEmpty(text))
            return false;

        return UiHost.Current?.SetClipboardText(text) ?? false;
    }
}
