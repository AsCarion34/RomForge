using Patch.Core.Interfaces;
using Patch.Core.Services;
using RomForge.Mac.Compat;
using System.Windows;

namespace RomForge.Views;

// upstream RomForge/Views/PasswordPromptWindow.xaml.cs의 macOS 대체.
// ViewModel이 호출하는 OpenWithPasswordPromptAsync의 동작(비밀번호가 틀리면 다시 묻기)을 그대로 따르고,
// 입력 창만 UiHost(SwiftUI)로 넘긴다. upstream이 이 메서드를 바꾸면 여기도 맞춰야 한다.
public class PasswordPromptWindow : Window
{
    public static async Task<(IArchivePatchSource Archive, string? Password)?> OpenWithPasswordPromptAsync(string archivePath, Window? owner)
    {
        bool wrongPassword = false;
        string? password = null;

        while (true)
        {
            try
            {
                string? attemptedPassword = password;
                var archive = await Task.Run(() => ArchivePatchSourceFactory.Open(archivePath, attemptedPassword));

                return (archive, password);
            }
            catch (ArchivePasswordRequiredException)
            {
                string? entered = UiHost.Current?.PromptPassword(archivePath, wrongPassword);

                if (entered == null)
                    return null;

                password = entered;
                wrongPassword = true;
            }
        }
    }
}
