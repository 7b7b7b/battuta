using System.Collections.Specialized;
using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Battuta.Core.SoundPacks;
using Battuta.Windows.Diy.ViewModels;
using Microsoft.Win32;

namespace Battuta.Windows.Views.Diy;

public partial class SoundPackSidebar : UserControl
{
    private DiySoundPackEditorViewModel? _viewModel;
    private bool _selecting;

    public SoundPackSidebar()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (_viewModel is not null)
        {
            _viewModel.CustomPacks.CollectionChanged -= PacksChanged;
            _viewModel.PropertyChanged -= ViewModelPropertyChanged;
        }

        _viewModel = e.NewValue as DiySoundPackEditorViewModel;
        if (_viewModel is not null)
        {
            _viewModel.CustomPacks.CollectionChanged += PacksChanged;
            _viewModel.PropertyChanged += ViewModelPropertyChanged;
        }

        UpdateEmptyState();
        SyncSelection();
    }

    private void PacksChanged(object? sender, NotifyCollectionChangedEventArgs e) =>
        RefreshPackList();

    private void RefreshPackList()
    {
        UpdateEmptyState();
        SyncSelection();
    }

    private void ViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(DiySoundPackEditorViewModel.SelectedPackId))
        {
            SyncSelection();
        }
    }

    private void SyncSelection()
    {
        if (_selecting || _viewModel is null)
        {
            return;
        }

        _selecting = true;
        try
        {
            PacksList.SelectedItem = _viewModel.CustomPacks.FirstOrDefault(
                pack => pack.CustomPackId == _viewModel.SelectedPackId);
        }
        finally
        {
            _selecting = false;
        }
    }

    private void UpdateEmptyState()
    {
        var hasPacks = _viewModel?.CustomPacks.Count > 0;
        PacksList.Visibility = hasPacks ? Visibility.Visible : Visibility.Collapsed;
        EmptyPlaceholder.Visibility = hasPacks ? Visibility.Collapsed : Visibility.Visible;
    }

    private void NewPackMenuClick(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.ContextMenu is null)
        {
            return;
        }

        button.ContextMenu.PlacementTarget = button;
        button.ContextMenu.Placement = PlacementMode.Bottom;
        button.ContextMenu.IsOpen = true;
    }

    private async void PackSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_selecting
            || _viewModel is null
            || PacksList.SelectedItem is not SoundPackDescriptor { CustomPackId: { } id })
        {
            return;
        }

        _selecting = true;
        try
        {
            if (Window.GetWindow(this) is SoundPackEditorWindow window)
            {
                _ = await window.RunDraftReplacingActionAsync(() => _viewModel.SelectPackAsync(id));
            }
            else
            {
                await _viewModel.SelectPackAsync(id);
            }
        }
        finally
        {
            _selecting = false;
            SyncSelection();
        }
    }

    private async void NewBlankClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is null)
        {
            return;
        }
        await RunReplacingDraftActionAsync(_viewModel.CreateBlankAsync);
    }

    private async void CreateBasedOnCurrentClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is null)
        {
            return;
        }
        await RunReplacingDraftActionAsync(_viewModel.CreateBasedOnInitialSelectionAsync);
    }

    private async void ImportPackClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is null)
        {
            return;
        }

        var dialog = new OpenFolderDialog
        {
            Title = "选择 .simuboardpack 音色包目录",
            Multiselect = false,
        };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true)
        {
            await RunReplacingDraftActionAsync(() => _viewModel.ImportPackAsync(dialog.FolderName));
        }
    }

    private async void ExportPackClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel?.SelectedPackId is not { } || _viewModel.Manifest is not { } manifest)
        {
            return;
        }

        var dialog = new OpenFolderDialog
        {
            Title = "选择导出位置",
            Multiselect = false,
        };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true)
        {
            var destination = Path.Combine(dialog.FolderName, SafeFileName(manifest.Name) + ".simuboardpack");
            var overwrite = false;
            if (Directory.Exists(destination))
            {
                var answer = MessageBox.Show(
                    Window.GetWindow(this),
                    $"“{Path.GetFileName(destination)}”已经存在。要替换它吗？",
                    "导出 Battuta 音色包",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Warning);
                if (answer != MessageBoxResult.Yes)
                {
                    return;
                }
                overwrite = true;
            }
            await _viewModel.ExportSelectedPackAsync(destination, overwrite);
        }
    }

    private async void DeletePackClick(object sender, RoutedEventArgs e)
    {
        if (_viewModel is null)
        {
            return;
        }

        await RunReplacingDraftActionAsync(async () =>
        {
            var answer = MessageBox.Show(
                Window.GetWindow(this),
                "音色包不会被永久删除，可从 Battuta 音色目录的 .Trash 中恢复。",
                "移除这个自定义音色包？",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (answer == MessageBoxResult.Yes)
            {
                await _viewModel.DeleteSelectedPackAsync();
            }
        });
    }

    private async Task RunReplacingDraftActionAsync(Func<Task> action)
    {
        if (Window.GetWindow(this) is SoundPackEditorWindow window)
        {
            _ = await window.RunDraftReplacingActionAsync(action);
        }
        else
        {
            await action();
        }
    }

    private static string SafeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var cleaned = new string(value.Select(character => invalid.Contains(character) ? '-' : character).ToArray()).Trim();
        return cleaned.Length == 0 ? "Battuta-Sound-Pack" : cleaned;
    }
}
