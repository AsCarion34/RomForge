namespace RomForge.Core.Services;

public static class SoundPlayer
{
    public static async Task PlayCompleteAsync()
    {
        await PlayAsync("complete.mp3");
    }

    public static async Task PlayCancelAsync()
    {
        await PlayAsync("cancel.mp3");
    }

    public static async Task PlayErrorAsync()
    {
        await PlayAsync("error.mp3");
    }

    private static async Task PlayAsync(string soundFileName)
    {
        if (!AppConfig.Instance.Common.IsMuted)
        {
            string packUriString = $"pack://application:,,,/Assets/Sounds/{soundFileName}";
            await Common.WPF.SoundManager.PlayFromWpfResourceAsync(packUriString);
        }
    }
}