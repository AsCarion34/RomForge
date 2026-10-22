namespace RomForge.ViewModels.PSVita;

public class PSVitaMainViewModel : MultiToolTabViewModel
{
    public RepackMainViewModel RepackVM { get; } = new();

    public PSVitaMainViewModel()
    {
        Tools.Add(RepackVM);
        InitializeMultiTools();
    }
}