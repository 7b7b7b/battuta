using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using Battuta.Windows.Diy.ViewModels;

namespace Battuta.Windows.Views.Diy;

public partial class SoundPackEditorWindow : Window
{
    private DiySoundPackEditorViewModel? viewModel;
    private bool allowClose;
    private bool preparingClose;
    private bool showingError;

    public SoundPackEditorWindow()
    {
        InitializeComponent();
        Closing += OnClosing;
        DataContextChanged += OnDataContextChanged;
        KeyDown += OnWindowKeyDown;
    }

    public async Task<bool> RunDraftReplacingActionAsync(Func<Task> action)
    {
        ArgumentNullException.ThrowIfNull(action);
        if (viewModel is null || viewModel.IsWorking)
        {
            return false;
        }

        if (viewModel.IsDirty)
        {
            var answer = MessageBox.Show(
                this,
                "继续将替换当前草稿。\n\n选择“是”保存后继续，选择“否”放弃更改并继续。",
                "当前音色有未保存的更改",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Warning);
            if (answer == MessageBoxResult.Cancel)
            {
                return false;
            }

            if (answer == MessageBoxResult.Yes)
            {
                await viewModel.SaveAsync(enableAfterSaving: false);
                if (viewModel.IsDirty)
                {
                    return false;
                }
            }
        }

        await action();
        return true;
    }

    /// <summary>
    /// Imports an externally activated package without bypassing the editor's
    /// unsaved-draft decision flow. Used by --open-sound-pack activation.
    /// </summary>
    public Task<bool> RequestImportPackAsync(string packagePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packagePath);
        return viewModel is null
            ? Task.FromResult(false)
            : RunDraftReplacingActionAsync(() => viewModel.ImportPackAsync(packagePath));
    }

    /// <summary>
    /// Runs the same busy, unsaved-change, and temporary-audio checks used by
    /// window closing before the application terminates.
    /// </summary>
    public async Task<bool> PrepareForApplicationExitAsync()
    {
        if (preparingClose)
        {
            return false;
        }

        preparingClose = true;
        try
        {
            var prepared = await PrepareToLeaveAsync(applicationExit: true);
            if (prepared)
            {
                allowClose = true;
            }
            return prepared;
        }
        finally
        {
            preparingClose = false;
        }
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (viewModel is not null)
        {
            viewModel.PropertyChanged -= ViewModelPropertyChanged;
        }

        viewModel = e.NewValue as DiySoundPackEditorViewModel;
        if (viewModel is not null)
        {
            viewModel.PropertyChanged += ViewModelPropertyChanged;
        }
        RefreshWorkingState();
    }

    private void ViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(DiySoundPackEditorViewModel.IsWorking))
        {
            RefreshWorkingState();
        }
        else if (e.PropertyName == nameof(DiySoundPackEditorViewModel.Error))
        {
            ShowPendingError();
        }
    }

    private void RefreshWorkingState()
    {
        EditorContent.IsEnabled = viewModel?.IsWorking != true;
    }

    private void ShowPendingError()
    {
        if (showingError || viewModel?.Error is not { } error)
        {
            return;
        }

        showingError = true;
        try
        {
            MessageBox.Show(this, error.Message, error.Title, MessageBoxButton.OK, MessageBoxImage.Error);
            viewModel.ClearError();
        }
        finally
        {
            showingError = false;
        }
    }

    private async void OnClosing(object? sender, CancelEventArgs e)
    {
        if (allowClose || viewModel is null)
        {
            return;
        }

        e.Cancel = true;
        if (preparingClose)
        {
            return;
        }

        preparingClose = true;
        try
        {
            if (!await PrepareToLeaveAsync(applicationExit: false))
            {
                return;
            }

            allowClose = true;
            Close();
        }
        finally
        {
            preparingClose = false;
        }
    }

    private async Task<bool> PrepareToLeaveAsync(bool applicationExit)
    {
        if (viewModel is null)
        {
            return true;
        }

        if (viewModel.IsWorking)
        {
            MessageBox.Show(
                this,
                applicationExit
                    ? "当前音频操作完成后才能退出 Battuta。"
                    : "当前音频操作完成后才能关闭 DIY 编辑器。",
                "正在处理音频",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return false;
        }

        if (viewModel.IsDirty)
        {
            var answer = MessageBox.Show(
                this,
                applicationExit
                    ? "退出 Battuta 会丢失尚未保存的音频映射。\n\n选择“是”保存，选择“否”放弃更改。"
                    : "关闭窗口会丢失尚未保存的音频映射。\n\n选择“是”保存，选择“否”放弃更改。",
                "保存 DIY 音色的更改吗？",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Warning);
            if (answer == MessageBoxResult.Cancel)
            {
                return false;
            }

            if (answer == MessageBoxResult.Yes)
            {
                await viewModel.SaveAsync(enableAfterSaving: false);
                if (viewModel.IsDirty)
                {
                    return false;
                }
            }
        }

        return await viewModel.PrepareForClosingAsync();
    }

    private void OnWindowKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape && !preparingClose)
        {
            Close();
            e.Handled = true;
        }
    }
}
