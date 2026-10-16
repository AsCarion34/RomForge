using System.Windows;
using System.Windows.Controls;

namespace RomForge.Controls.Settings;

public partial class GeneralSettingsTab : UserControl
{
    public GeneralSettingsTab() => InitializeComponent();

    private void SoundTextBox_PreviewDragOver(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
            e.Effects = DragDropEffects.Copy;
        else
            e.Effects = DragDropEffects.None;

        e.Handled = true;
    }

    private void CompleteSoundTextBox_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0)
                if (DataContext is ViewModels.Settings.GeneralSettingsMainViewModel vm)
                    vm.CompleteSoundPath = files[0];
    }

    private void CancelSoundTextBox_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0)
                if (DataContext is ViewModels.Settings.GeneralSettingsMainViewModel vm)
                    vm.CancelSoundPath = files[0];
    }

    private void ErrorSoundTextBox_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files && files.Length > 0)
                if (DataContext is ViewModels.Settings.GeneralSettingsMainViewModel vm)
                    vm.ErrorSoundPath = files[0];
    }
}