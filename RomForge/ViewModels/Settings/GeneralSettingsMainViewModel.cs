using Common.WPF.ViewModels;
using RomForge.Core;

namespace RomForge.ViewModels.Settings;

public class GeneralSettingsMainViewModel : ToolTabViewModel
{
    public GeneralSettingsMainViewModel()
    {
        AppConfig.Instance.Common.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(CommonConfig.Topmost))
                OnPropertyChanged(nameof(Topmost));
            else if (e.PropertyName == nameof(CommonConfig.AutoCheckUpdate))
                OnPropertyChanged(nameof(AutoCheckUpdate));
            else if (e.PropertyName == nameof(CommonConfig.IsMuted))
                OnPropertyChanged(nameof(IsMuted));
        };
    }

    public bool Topmost
    {
        get => AppConfig.Instance.Common.Topmost;
        set
        {
            AppConfig.Instance.Common.Topmost = value;
            OnPropertyChanged();
        }
    }

    public bool AutoCheckUpdate
    {
        get => AppConfig.Instance.Common.AutoCheckUpdate;
        set
        {
            AppConfig.Instance.Common.AutoCheckUpdate = value;
            OnPropertyChanged();
        }
    }

    public bool IsMuted
    {
        get => AppConfig.Instance.Common.IsMuted;
        set
        {
            AppConfig.Instance.Common.IsMuted = value;
            OnPropertyChanged();
        }
    }
}