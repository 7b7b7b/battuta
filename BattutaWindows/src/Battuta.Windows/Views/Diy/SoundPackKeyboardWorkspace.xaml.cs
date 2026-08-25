using System.ComponentModel;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Battuta.Core.Input;
using Battuta.Windows.Controls.Keyboard;
using Battuta.Windows.Diy.Audio;
using Battuta.Windows.Diy.ViewModels;

namespace Battuta.Windows.Views.Diy;

public partial class SoundPackKeyboardWorkspace : UserControl
{
    private static readonly Dictionary<string, PhysicalKeyId> ExtendedKeys =
        BuildExtendedKeyMap();
    private DiySoundPackEditorViewModel? viewModel;
    private bool syncing;

    public SoundPackKeyboardWorkspace()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
        Loaded += OnLoaded;
        Keyboard.KeyPressed += KeyboardKeyPressed;
        Keyboard.KeyReleased += KeyboardKeyReleased;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        foreach (var button in FindVisualChildren<Button>(ExtendedKeysPanel))
        {
            if (button.Tag is PhysicalKeyId)
            {
                continue;
            }

            var label = button.Content?.ToString() ?? string.Empty;
            if (!ExtendedKeys.TryGetValue(label, out var key))
            {
                continue;
            }

            button.Tag = key;
            var accessibleLabel = WindowsKeyDisplayCatalog.LabelFor(key);
            AutomationProperties.SetName(button, accessibleLabel);
            button.ToolTip ??= accessibleLabel;
            button.PreviewMouseLeftButtonDown += ExtendedKeyMouseDown;
            button.PreviewMouseLeftButtonUp += ExtendedKeyMouseUp;
        }
        RefreshFromViewModel();
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
        RefreshFromViewModel();
    }

    private void ViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e) =>
        RefreshFromViewModel();

    private void RefreshFromViewModel()
    {
        if (viewModel is null)
        {
            return;
        }

        syncing = true;
        try
        {
            GenericModeButton.IsChecked = viewModel.MappingMode == DiyEditorMappingMode.Generic;
            RecommendedModeButton.IsChecked = viewModel.MappingMode == DiyEditorMappingMode.Recommended;
            PerKeyModeButton.IsChecked = viewModel.MappingMode == DiyEditorMappingMode.PerKey;
            MappingHeading.Subtitle = viewModel.MappingMode switch
            {
                DiyEditorMappingMode.Generic => "上传一组按下/回弹音，快速应用到整把键盘。",
                DiyEditorMappingMode.Recommended => "按 R1–R4、功能/其他键与空格、回车、退格分配，声音更自然。",
                DiyEditorMappingMode.PerKey => "点击一个键，再在右侧设置继承、静音或独立音频。",
                _ => string.Empty,
            };

            if (PhysicalKeyCatalog.TryGet(viewModel.SelectedKey, out var definition))
            {
                Keyboard.SelectedKey = definition.Id;
                SelectionSummary.Text = $"已选：{WindowsLabel(definition)} · {RowLabel(definition.Row)}";
            }
            Keyboard.IsInteractive = !viewModel.IsWorking;
            Keyboard.InvalidateVisual();

            foreach (var button in FindVisualChildren<Button>(ExtendedKeysPanel))
            {
                button.Opacity = button.Tag is PhysicalKeyId key && key == viewModel.SelectedKey ? 1 : 0.82;
            }
        }
        finally
        {
            syncing = false;
        }
    }

    private void MappingModeChecked(object sender, RoutedEventArgs e)
    {
        if (syncing || viewModel is null || sender is not FrameworkElement { Tag: string tag } ||
            !Enum.TryParse(tag, ignoreCase: true, out DiyEditorMappingMode mode))
        {
            return;
        }
        viewModel.MappingMode = mode;
    }

    private async void KeyboardKeyPressed(object? sender, KeyboardCanvasKeyEventArgs e)
    {
        if (viewModel is null)
        {
            return;
        }
        viewModel.SelectedKey = e.Key;
        await PreviewAsync(e.Key, Battuta.Core.Audio.KeySoundPhase.Press);
    }

    private async void KeyboardKeyReleased(object? sender, KeyboardCanvasKeyEventArgs e)
    {
        if (viewModel is not null)
        {
            await PreviewAsync(e.Key, Battuta.Core.Audio.KeySoundPhase.Release);
        }
    }

    private async void ExtendedKeyMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (viewModel is not null && sender is Button { Tag: PhysicalKeyId key })
        {
            viewModel.SelectedKey = key;
            await PreviewAsync(key, Battuta.Core.Audio.KeySoundPhase.Press);
        }
    }

    private async void ExtendedKeyMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (viewModel is not null && sender is Button { Tag: PhysicalKeyId key })
        {
            await PreviewAsync(key, Battuta.Core.Audio.KeySoundPhase.Release);
        }
    }

    private async Task PreviewAsync(PhysicalKeyId key, Battuta.Core.Audio.KeySoundPhase phase)
    {
        try
        {
            await viewModel!.PreviewAsync(key, phase);
        }
        catch (Exception error) when (
            error is IOException or InvalidOperationException or UnauthorizedAccessException or DiyAudioException)
        {
            viewModel?.ReportError(error, "无法试听音频");
        }
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject root)
        where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match)
            {
                yield return match;
            }
            foreach (var descendant in FindVisualChildren<T>(child))
            {
                yield return descendant;
            }
        }
    }

    private static string WindowsLabel(KeyboardKeyDefinition definition) =>
        WindowsKeyDisplayCatalog.LabelFor(definition.Id);

    private static string RowLabel(KeyboardRowId row) => row switch
    {
        KeyboardRowId.R0 => "R1 · 数字行",
        KeyboardRowId.R1 => "R2 · Q 行",
        KeyboardRowId.R2 => "R3 · A 行",
        KeyboardRowId.R3 => "R4 · Z 行",
        KeyboardRowId.R4 => "功能 / 其他键",
        _ => row.ToString(),
    };

    private static Dictionary<string, PhysicalKeyId> BuildExtendedKeyMap() =>
        new Dictionary<string, PhysicalKeyId>(StringComparer.OrdinalIgnoreCase)
        {
            ["Insert"] = PhysicalKeys.Insert,
            ["Home"] = PhysicalKeys.Home,
            ["Page Up"] = PhysicalKeys.PageUp,
            ["Delete"] = PhysicalKeys.Delete,
            ["End"] = PhysicalKeys.End,
            ["Page Down"] = PhysicalKeys.PageDown,
            ["F13"] = PhysicalKeys.F13,
            ["F14"] = PhysicalKeys.F14,
            ["F15"] = PhysicalKeys.F15,
            ["F16"] = PhysicalKeys.F16,
            ["F17"] = PhysicalKeys.F17,
            ["F18"] = PhysicalKeys.F18,
            ["F19"] = PhysicalKeys.F19,
            ["F20"] = PhysicalKeys.F20,
            ["Intl \\"] = PhysicalKeys.IntlBackslash,
            ["Yen (¥)"] = PhysicalKeys.IntlYen,
            ["Intl Ro"] = PhysicalKeys.IntlRo,
            ["Num ,"] = PhysicalKeys.NumpadComma,
            ["Eisu"] = PhysicalKeys.Eisu,
            ["Kana"] = PhysicalKeys.Kana,
            ["Volume Up"] = PhysicalKeys.AudioVolumeUp,
            ["Volume Down"] = PhysicalKeys.AudioVolumeDown,
            ["Mute"] = PhysicalKeys.AudioVolumeMute,
            ["Num"] = PhysicalKeys.NumLock,
            ["="] = PhysicalKeys.NumpadEqual,
            ["/"] = PhysicalKeys.NumpadDivide,
            ["*"] = PhysicalKeys.NumpadMultiply,
            ["-"] = PhysicalKeys.NumpadSubtract,
            ["7"] = PhysicalKeys.Numpad7,
            ["8"] = PhysicalKeys.Numpad8,
            ["9"] = PhysicalKeys.Numpad9,
            ["+"] = PhysicalKeys.NumpadAdd,
            ["4"] = PhysicalKeys.Numpad4,
            ["5"] = PhysicalKeys.Numpad5,
            ["6"] = PhysicalKeys.Numpad6,
            ["1"] = PhysicalKeys.Numpad1,
            ["2"] = PhysicalKeys.Numpad2,
            ["3"] = PhysicalKeys.Numpad3,
            ["Enter"] = PhysicalKeys.NumpadEnter,
            ["0"] = PhysicalKeys.Numpad0,
            ["."] = PhysicalKeys.NumpadDecimal,
        };
}
