using NSW.WPF.ViewModels;
using RomForge.Core.Services.Switch;
using RomForge.ViewModels.Switch;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace RomForge.Controls.Switch;

public partial class RenameTab : UserControl
{
    private readonly DispatcherTimer _refreshTimer;

    private RenameMainViewModel? ViewModel => DataContext as RenameMainViewModel;

    public RenameTab()
    {
        InitializeComponent();

        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
        _refreshTimer.Tick += RefreshTimer_Tick;

        fileMgr.GameFiles.CollectionChanged += GameFiles_CollectionChanged;
        DataContextChanged += (_, _) => ScheduleRefresh();
    }

    protected override void OnVisualParentChanged(DependencyObject oldParent)
    {
        base.OnVisualParentChanged(oldParent);

        if (VisualParent == null)
            ViewModel?.Cancel();
    }

    private void ScheduleRefresh()
    {
        _refreshTimer.Stop();
        _refreshTimer.Start();
    }

    private void RefreshTimer_Tick(object? sender, EventArgs e)
    {
        _refreshTimer.Stop();
        ViewModel?.RefreshPreview(fileMgr.GameFiles);
    }

    private void GameFiles_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.OldItems != null)
        {
            foreach (GameFile item in e.OldItems)
                item.PropertyChanged -= GameFile_PropertyChanged;
        }

        if (e.NewItems != null)
        {
            foreach (GameFile item in e.NewItems)
                item.PropertyChanged += GameFile_PropertyChanged;
        }

        ScheduleRefresh();
    }

    private void GameFile_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(GameFile.TitleName) or nameof(GameFile.TitleID) or nameof(GameFile.Version) or nameof(GameFile.FileType))
            ScheduleRefresh();
    }

    private void TxtFormat_TextChanged(object sender, TextChangedEventArgs e) => ScheduleRefresh();

    private void BtnResetFormat_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel != null)
            ViewModel.FormatText = SwitchRenameService.DefaultFormat;
    }

    private async void BtnStartWork_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel == null)
            return;

        if (ViewModel.IsLocked)
            ViewModel.Cancel();
        else
            await ViewModel.ExecuteStartWorkAsync(fileMgr.GameFiles);
    }
}
