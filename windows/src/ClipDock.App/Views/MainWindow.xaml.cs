using ClipDock.App.ViewModels;
using Microsoft.UI.Xaml;

namespace ClipDock.App;

public sealed partial class MainWindow : Window
{
    public ClipboardViewModel ViewModel { get; }

    public MainWindow(ClipboardViewModel viewModel)
    {
        ViewModel = viewModel;
        InitializeComponent();
        _ = ViewModel.RefreshAsync();
        Activated += async (_, _) => await ViewModel.RefreshAsync();
    }
}
