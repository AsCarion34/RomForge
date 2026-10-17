using NSW.WPF.UI;
using RomForge.ViewModels.Switch;
using System.Windows;
using System.Windows.Controls;
using Res = NSW.Core.Properties.Resources;

namespace RomForge.Controls.Switch;

public partial class SplitTab : UserControl
{
    private SplitMainViewModel ViewModel => (SplitMainViewModel)DataContext;

    public SplitTab()
    {
        InitializeComponent();
    }

    private void BtnSettings_Click(object sender, RoutedEventArgs e)
    {
        ViewModel.NavigateSettings();
    }

    private void BtnHelp_Click(object sender, RoutedEventArgs e)
    {
        var psi = new System.Diagnostics.ProcessStartInfo
        {
            FileName = "https://sinjunyoung.github.io/RomForge/switch-merge/",
            UseShellExecute = true
        };

        System.Diagnostics.Process.Start(psi);
    }

    protected override void OnVisualParentChanged(DependencyObject oldParent)
    {
        base.OnVisualParentChanged(oldParent);

        if (VisualParent == null)
            ViewModel?.Cancel();
    }

    private void BtnBrowseOutput_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new Ookii.Dialogs.Wpf.VistaFolderBrowserDialog
        {
            Description = Res.Hint_SelectOutput,
            UseDescriptionForTitle = true
        };

        if (dlg.ShowDialog() == true)
            ViewModel.OutputPath = dlg.SelectedPath;
    }

    private async void BtnSplitStart_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.IsLocked)
        {
            ViewModel.Cancel();
            return;
        }

        if (!fileMgr.GameFiles.Any())
        {
            ViewModel.Log(Res.Main_Err_NoFiles, Common.LogLevel.Error);
            return;
        }

        if (!FileManagerControl.KeyExists())
        {
            ViewModel.Log(Res.Main_Err_NoKeys, Common.LogLevel.Error);
            return;
        }

        if (fileMgr.GameFiles.Any(f => f.IsKeyMissing))
            await RecalcKeyMissingAsync();

        await ViewModel.SplitAsync(fileMgr.GameFiles);
    }

    private Task RecalcKeyMissingAsync()
    {
        var tcs = new TaskCompletionSource();
        fileMgr.RecalcKeyMissingFiles(() => tcs.SetResult());

        return tcs.Task;
    }
}