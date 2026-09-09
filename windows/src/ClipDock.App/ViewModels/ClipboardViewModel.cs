using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using ClipDock.Core.Interfaces;

namespace ClipDock.App.ViewModels;

public sealed class ClipboardViewModel : INotifyPropertyChanged
{
    private readonly IClipboardRepository _repository;
    private readonly IClipboardWriter _writer;
    private string _searchText = string.Empty;
    private ClipboardItemViewModel? _selectedItem;

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<ClipboardItemViewModel> Items { get; } = [];

    public ICommand CopySelectedCommand { get; }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetField(ref _searchText, value))
            {
                _ = RefreshAsync();
            }
        }
    }

    public ClipboardItemViewModel? SelectedItem
    {
        get => _selectedItem;
        set
        {
            if (SetField(ref _selectedItem, value))
            {
                OnPropertyChanged(nameof(SelectedPreview));
                ((RelayCommand)CopySelectedCommand).RaiseCanExecuteChanged();
            }
        }
    }

    public string SelectedPreview => SelectedItem?.Model.TextContent ?? string.Empty;

    public ClipboardViewModel(IClipboardRepository repository, IClipboardWriter writer)
    {
        _repository = repository;
        _writer = writer;
        CopySelectedCommand = new RelayCommand(CopySelectedAsync, () => SelectedItem is not null);
    }

    public async Task RefreshAsync()
    {
        var items = string.IsNullOrWhiteSpace(SearchText)
            ? await _repository.GetRecentAsync(200, CancellationToken.None)
            : await _repository.SearchAsync(SearchText, CancellationToken.None);

        Items.Clear();
        foreach (var item in items)
        {
            Items.Add(new ClipboardItemViewModel(item));
        }
    }

    private async Task CopySelectedAsync()
    {
        if (SelectedItem is null)
        {
            return;
        }

        await _writer.WriteAsync(SelectedItem.Model, CancellationToken.None);
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
