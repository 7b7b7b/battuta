using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Battuta.Core.Audio;
using Battuta.Core.Input;
using Battuta.Core.SoundPacks;
using Battuta.Windows.Diy.Audio;
using Battuta.Windows.Diy.ViewModels;
using Microsoft.Win32;

namespace Battuta.Windows.Views.Diy;

public partial class SoundPackInspector : UserControl
{
    private readonly IReadOnlyList<SlotChoice> recommendedSlots;
    private readonly IReadOnlyList<OverrideOption> overrideOptions;
    private DiySoundPackEditorViewModel? viewModel;
    private bool syncing;

    public SoundPackInspector()
    {
        InitializeComponent();
        recommendedSlots =
        [
            .. Enum.GetValues<KeyboardRowId>()
                .Select(row => new SlotChoice(DiyEditorSlot.ForRow(row).DisplayName, DiyEditorSlot.ForRow(row))),
            .. Enum.GetValues<KeyboardSpecialKeyId>()
                .Select(special => new SlotChoice(
                    DiyEditorSlot.ForSpecial(special).DisplayName,
                    DiyEditorSlot.ForSpecial(special))),
        ];
        overrideOptions =
        [
            new OverrideOption("继承", DiyKeyOverrideChoice.Inherit),
            new OverrideOption("静音", DiyKeyOverrideChoice.Silent),
            new OverrideOption("自定义", DiyKeyOverrideChoice.Asset),
        ];
        RecommendedSlotPicker.ItemsSource = recommendedSlots;
        PressOverridePicker.ItemsSource = overrideOptions;
        ReleaseOverridePicker.ItemsSource = overrideOptions;
        DataContextChanged += OnDataContextChanged;
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
        syncing = true;
        try
        {
            var manifest = viewModel?.Manifest;
            SetTextIfDifferent(PackNameBox, manifest?.Name);
            SetTextIfDifferent(PackAuthorBox, manifest?.Author);
            SetTextIfDifferent(PackNotesBox, manifest?.Notes);
            var hasDraft = manifest is not null;
            PackNameBox.IsEnabled = hasDraft;
            PackAuthorBox.IsEnabled = hasDraft;
            PackNotesBox.IsEnabled = hasDraft;

            if (manifest?.BaseProfileId is { } baseId &&
                SwitchProfileCatalog.TryGet(baseId, out var baseProfile))
            {
                BaseProfileText.Text = $"⑂  未设置处继承 {baseProfile.DisplayName}";
                BaseProfileText.Visibility = Visibility.Visible;
            }
            else
            {
                BaseProfileText.Visibility = Visibility.Collapsed;
            }

            if (viewModel is null)
            {
                return;
            }

            RecommendedSlotPicker.SelectedItem = recommendedSlots.FirstOrDefault(
                choice => choice.Slot == viewModel.RecommendedSlot);
            RecommendedSlotPicker.Visibility = viewModel.MappingMode == DiyEditorMappingMode.Recommended
                ? Visibility.Visible
                : Visibility.Collapsed;

            var slot = CurrentSlot();
            MappingHeading.Title = viewModel.MappingMode == DiyEditorMappingMode.PerKey
                ? $"{slot.DisplayName} · 单键覆盖"
                : slot.DisplayName;
            InspectorContextText.Text = viewModel.MappingMode switch
            {
                DiyEditorMappingMode.Generic => "通用",
                DiyEditorMappingMode.Recommended => "推荐分布",
                DiyEditorMappingMode.PerKey => $"当前按键：{slot.DisplayName}",
                _ => string.Empty,
            };

            RefreshPhase(KeySoundPhase.Press);
            RefreshPhase(KeySoundPhase.Release);
            StatusText.Text = viewModel.StatusMessage ?? "就绪";
            WorkingProgress.Visibility = viewModel.IsWorking ? Visibility.Visible : Visibility.Collapsed;
            DirtyIndicator.Visibility = viewModel.IsDirty ? Visibility.Visible : Visibility.Collapsed;
        }
        finally
        {
            syncing = false;
        }
    }

    private void RefreshPhase(KeySoundPhase phase)
    {
        if (viewModel is null)
        {
            return;
        }

        var slot = CurrentSlot();
        var isPerKey = viewModel.MappingMode == DiyEditorMappingMode.PerKey;
        var choice = isPerKey && slot.Key is { } key
            ? viewModel.OverrideChoice(key, phase)
            : DiyKeyOverrideChoice.Asset;
        var assetId = viewModel.AssignmentAsset(slot, phase);
        var picker = phase == KeySoundPhase.Press ? PressOverridePicker : ReleaseOverridePicker;
        var assetLabel = phase == KeySoundPhase.Press ? PressAssetLabel : ReleaseAssetLabel;
        var help = phase == KeySoundPhase.Press ? PressOverrideHelp : ReleaseOverrideHelp;
        var actions = phase == KeySoundPhase.Press ? PressAssetActions : ReleaseAssetActions;
        var existing = phase == KeySoundPhase.Press ? PressExistingButton : ReleaseExistingButton;
        var clear = phase == KeySoundPhase.Press ? PressClearButton : ReleaseClearButton;

        picker.Visibility = isPerKey ? Visibility.Visible : Visibility.Collapsed;
        picker.SelectedItem = overrideOptions.First(option => option.Choice == choice);
        var showsAsset = !isPerKey || choice == DiyKeyOverrideChoice.Asset;
        assetLabel.Visibility = showsAsset ? Visibility.Visible : Visibility.Collapsed;
        actions.Visibility = showsAsset ? Visibility.Visible : Visibility.Collapsed;
        help.Visibility = showsAsset ? Visibility.Collapsed : Visibility.Visible;
        help.Text = choice == DiyKeyOverrideChoice.Silent
            ? "这个阶段不播放声音。"
            : "沿用特殊键、所在行、通用音或基础音色。";
        assetLabel.Text = viewModel.AssetLabel(assetId);
        existing.IsEnabled = viewModel.AssetChoices.Count > 0;
        clear.Visibility = !isPerKey && assetId.HasValue ? Visibility.Visible : Visibility.Collapsed;
    }

    private void MetadataTextChanged(object sender, TextChangedEventArgs e)
    {
        if (syncing || viewModel is null)
        {
            return;
        }

        if (ReferenceEquals(sender, PackNameBox))
        {
            viewModel.SetName(PackNameBox.Text);
        }
        else if (ReferenceEquals(sender, PackAuthorBox))
        {
            viewModel.SetAuthor(PackAuthorBox.Text);
        }
        else if (ReferenceEquals(sender, PackNotesBox))
        {
            viewModel.SetNotes(PackNotesBox.Text);
        }
    }

    private void RecommendedSlotChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!syncing && viewModel is not null && RecommendedSlotPicker.SelectedItem is SlotChoice choice)
        {
            viewModel.RecommendedSlot = choice.Slot;
        }
    }

    private async void OverrideChoiceChanged(object sender, SelectionChangedEventArgs e)
    {
        if (syncing || viewModel is null || sender is not ComboBox picker ||
            picker.SelectedItem is not OverrideOption option || CurrentSlot().Key is not { } key)
        {
            return;
        }

        var phase = ReferenceEquals(picker, PressOverridePicker)
            ? KeySoundPhase.Press
            : KeySoundPhase.Release;
        var previous = viewModel.OverrideChoice(key, phase);
        if (option.Choice == DiyKeyOverrideChoice.Asset && previous != DiyKeyOverrideChoice.Asset)
        {
            RefreshFromViewModel();
            await ChooseAndImportAudioAsync(phase);
            return;
        }

        viewModel.SetOverrideChoice(option.Choice, key, phase);
    }

    private async void ImportAudioClick(object sender, RoutedEventArgs e)
    {
        if (TryPhase(sender, out var phase))
        {
            await ChooseAndImportAudioAsync(phase);
        }
    }

    private async Task ChooseAndImportAudioAsync(KeySoundPhase phase)
    {
        if (viewModel is null)
        {
            return;
        }

        var dialog = CreateAudioOpenDialog("选择按键声音");
        if (dialog.ShowDialog(Window.GetWindow(this)) == true)
        {
            await RunAsync(
                () => viewModel.ImportAudioAsync(
                    dialog.FileName,
                    new DiyEditorAudioTarget(CurrentSlot(), phase)),
                "无法导入音频");
        }
    }

    private async void PreviewPhaseClick(object sender, RoutedEventArgs e)
    {
        if (viewModel is not null && TryPhase(sender, out var phase))
        {
            await RunAsync(() => viewModel.PreviewAsync(CurrentSlot(), phase), "无法试听音频");
        }
    }

    private void ExistingAudioClick(object sender, RoutedEventArgs e)
    {
        if (viewModel is null || sender is not Button button || !TryPhase(sender, out var phase))
        {
            return;
        }

        var menu = new ContextMenu
        {
            PlacementTarget = button,
            Placement = PlacementMode.Bottom,
        };
        if (viewModel.AssetChoices.Count == 0)
        {
            menu.Items.Add(new MenuItem { Header = "暂无已导入音频", IsEnabled = false });
        }
        else
        {
            var slot = CurrentSlot();
            foreach (var asset in viewModel.AssetChoices)
            {
                var assetId = asset.Id;
                var item = new MenuItem
                {
                    Header = asset.OriginalFilename ?? asset.Id.Value[..Math.Min(10, asset.Id.Value.Length)],
                };
                item.Click += (_, _) => viewModel.SetExistingAsset(assetId, slot, phase);
                menu.Items.Add(item);
            }
        }
        button.ContextMenu = menu;
        menu.IsOpen = true;
    }

    private void ClearAudioClick(object sender, RoutedEventArgs e)
    {
        if (viewModel is not null && TryPhase(sender, out var phase))
        {
            viewModel.SetExistingAsset(null, CurrentSlot(), phase);
        }
    }

    private async void OpenSplitClick(object sender, RoutedEventArgs e)
    {
        if (viewModel is null)
        {
            return;
        }

        var dialog = CreateAudioOpenDialog("选择包含按下与回弹的完整击键录音");
        if (dialog.ShowDialog(Window.GetWindow(this)) != true)
        {
            return;
        }

        await RunAsync(
            () => viewModel.AnalyzeFullKeystrokeAsync(dialog.FileName, CurrentSlot()),
            "无法分析完整击键");
        if (viewModel.SplitDraft is { } draft)
        {
            _ = new AudioSplitDialog(viewModel, draft)
            {
                Owner = Window.GetWindow(this),
            }.ShowDialog();
        }
    }

    private DiyEditorSlot CurrentSlot()
    {
        if (viewModel is null)
        {
            return DiyEditorSlot.Generic;
        }

        return viewModel.MappingMode switch
        {
            DiyEditorMappingMode.Generic => DiyEditorSlot.Generic,
            DiyEditorMappingMode.Recommended => viewModel.RecommendedSlot,
            DiyEditorMappingMode.PerKey => DiyEditorSlot.ForKey(viewModel.SelectedKey),
            _ => DiyEditorSlot.Generic,
        };
    }

    private static OpenFileDialog CreateAudioOpenDialog(string title) => new()
    {
        Title = title,
        CheckFileExists = true,
        Multiselect = false,
        Filter = "音频文件|*.wav;*.wave;*.mp3;*.aif;*.aiff;*.m4a;*.aac;*.wma;*.caf|所有文件|*.*",
    };

    private static bool TryPhase(object sender, out KeySoundPhase phase)
    {
        if (sender is FrameworkElement { Tag: string tag } &&
            Enum.TryParse(tag, ignoreCase: true, out phase))
        {
            return true;
        }
        phase = default;
        return false;
    }

    private static void SetTextIfDifferent(TextBox textBox, string? value)
    {
        var resolved = value ?? string.Empty;
        if (!string.Equals(textBox.Text, resolved, StringComparison.Ordinal))
        {
            textBox.Text = resolved;
        }
    }

    private async Task RunAsync(Func<Task> action, string title)
    {
        try
        {
            await action();
        }
        catch (Exception error) when (
            error is IOException or UnauthorizedAccessException or InvalidOperationException or
            DiyAudioException or SoundPackException)
        {
            viewModel?.ReportError(error, title);
        }
    }

    private sealed record SlotChoice(string Name, DiyEditorSlot Slot)
    {
        public override string ToString() => Name;
    }

    private sealed record OverrideOption(string Name, DiyKeyOverrideChoice Choice)
    {
        public override string ToString() => Name;
    }
}
