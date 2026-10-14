namespace RomForge.Core.Services;

public static class SoundPlayer
{
    public static async Task PlayAsync(string soundFileName)
    {

        if (!AppConfig.Instance.Common.IsMuted)
        {
            string packUriString = $"pack://application:,,,/Assets/Sounds/{soundFileName}";
            await Common.WPF.SoundManager.PlayFromWpfResourceAsync(packUriString);
        }
    }

    public static async Task Play(string soundFileName) => await PlayAsync(soundFileName);
}