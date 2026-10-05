using System.Windows;
using RomForge.Mac.Compat;

namespace Ookii.Dialogs.Wpf;

// Ookii.Dialogs.Wpf(Windows 전용 NuGet) 대체. 실제 표시는 UiHost가 맡는다.
public sealed class VistaFolderBrowserDialog
{
    private string[] _selectedPaths = [];

    public string Description { get; set; } = string.Empty;

    public bool UseDescriptionForTitle { get; set; }

    public bool ShowNewFolderButton { get; set; } = true;

    public bool Multiselect { get; set; }

    public Environment.SpecialFolder RootFolder { get; set; }

    public string SelectedPath
    {
        get => _selectedPaths.Length > 0 ? _selectedPaths[0] : string.Empty;
        set => _selectedPaths = string.IsNullOrEmpty(value) ? [] : [value];
    }

    public string[] SelectedPaths => _selectedPaths;

    public bool? ShowDialog() => ShowDialog(null);

    public bool? ShowDialog(Window? owner)
    {
        var paths = UiHost.Current?.ShowFolderDialog(new FolderDialogRequest(Description, SelectedPath, Multiselect));

        if (paths == null || paths.Length == 0)
            return false;

        _selectedPaths = paths;
        return true;
    }
}
