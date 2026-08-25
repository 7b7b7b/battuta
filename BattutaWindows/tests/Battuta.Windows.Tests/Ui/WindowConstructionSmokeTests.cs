using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;
using Battuta.TestSupport;
using Battuta.TestSupport.IO;
using Battuta.TestSupport.Threading;
using Battuta.Core.Input;
using Battuta.Windows.Diy.Audio;
using Battuta.Windows.Diy.Packages;
using Battuta.Windows.Diy.ViewModels;
using Battuta.Windows.Controls.Keyboard;
using Battuta.Windows.Views.Diy;
using Battuta.Windows.Views.Stats;
using Battuta.Windows.Views.Tray;

namespace Battuta.Windows.Tests.Ui;

public sealed class WindowConstructionSmokeTests
{
    [Theory]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    [InlineData(Surface.Tray, 360, 760, 0, 560)]
    [InlineData(Surface.Statistics, 1100, 760, 1100, 600)]
    [InlineData(Surface.DiyEditor, 1240, 760, 1120, 660)]
    [InlineData(Surface.AudioSplit, 760, 630, 760, 630)]
    public void TopLevelSurfaceConstructsOnStaWithoutRuntimeXamlErrors(
        Surface surface,
        double expectedWidth,
        double expectedHeight,
        double expectedMinimumWidth,
        double expectedMinimumHeight)
    {
        StaTestHost.Run(() =>
        {
            var window = CreateSurface(surface);

            Assert.NotNull(window.Content);
            Assert.NotEmpty(window.Resources.MergedDictionaries);
            Assert.Equal(expectedWidth, window.Width);
            Assert.Equal(expectedHeight, window.Height);
            Assert.Equal(expectedMinimumWidth, window.MinWidth);
            Assert.Equal(expectedMinimumHeight, window.MinHeight);

            // These windows are deliberately never shown or closed. Showing would
            // touch Explorer/user focus; closing the editor may display its dirty-state
            // confirmation. Exiting the isolated background STA releases the objects.
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public async Task InitializedAudioSplitDialogUsesDraftDataAndMacCompatibleBounds()
    {
        await StaTestHost.RunAsync(async () =>
        {
            using var directory = new TempDirectory("battuta-split-ui");
            using var library = new DiySoundPackLibrary(
                directory.CreateSubdirectory("library"),
                builtInDescriptors: []);
            await using var editor = new DiySoundPackEditorViewModel(
                library,
                "holypanda",
                temporaryCacheParent: directory.CreateSubdirectory("cache"));

            var analysis = CreateSplitAnalysis(directory.GetPath("source.wav"));
            var draft = new DiySplitDraft(
                Guid.NewGuid(),
                DiyEditorSlot.ForRow(KeyboardRowId.R2),
                analysis);
            var dialog = new AudioSplitDialog(editor, draft);

            var content = Assert.IsAssignableFrom<FrameworkElement>(dialog.Content);
            content.Measure(new Size(760, 630));
            content.Arrange(new Rect(0, 0, 760, 630));
            content.UpdateLayout();

            Assert.InRange(dialog.SplitTimeSeconds, 0.4795, 0.4805);
            Assert.InRange(dialog.ReleaseEndTimeSeconds, 0.4925, 0.4935);

            var waveform = Assert.IsType<AudioSplitWaveform>(dialog.FindName("Waveform"));
            Assert.Same(analysis, waveform.Analysis);
            Assert.Equal("击键音频波形", AutomationProperties.GetName(waveform));
            Assert.InRange(waveform.ActualHeight, 189, 191);

            var visibleText = VisualDescendants<TextBlock>(content)
                .Select(text => text.Text)
                .Where(text => !string.IsNullOrWhiteSpace(text))
                .ToHashSet(StringComparer.Ordinal);
            Assert.Contains("置信度 42%", visibleText);
            Assert.Contains("未找到明显回弹瞬态，当前切点使用能量谷值。", visibleText);
            Assert.Contains("自动切点置信度较低，请仔细检查波形。", visibleText);
            Assert.Contains("检测到可能的下一次击键，已建议提前结束。", visibleText);
            Assert.Contains("源录音可能削波，建议降低录音增益后重试。", visibleText);

            dialog.Close();
        });
    }

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void KeyboardCanvasExposesEveryVisibleKeyToUiAutomation()
    {
        StaTestHost.Run(() =>
        {
            var canvas = new KeyboardCanvas
            {
                Mode = KeyboardCanvasMode.Editor,
                Width = 691,
                Height = 282,
            };
            canvas.Measure(new Size(691, 282));
            canvas.Arrange(new Rect(0, 0, 691, 282));

            var peer = Assert.IsAssignableFrom<AutomationPeer>(
                UIElementAutomationPeer.CreatePeerForElement(canvas));
            var children = peer.GetChildren();

            Assert.NotNull(children);
            Assert.Equal(WindowsAnsiVisualLayoutCatalog.MainKeys.Count, children.Count);
            Assert.All(children, child =>
            {
                Assert.False(string.IsNullOrWhiteSpace(child.GetName()));
                Assert.Equal(AutomationControlType.Button, child.GetAutomationControlType());
            });
        });
    }

    private static Window CreateSurface(Surface surface) => surface switch
    {
        Surface.Tray => new TrayFlyoutWindow(),
        Surface.Statistics => new TypingStatsWindow(),
        Surface.DiyEditor => new SoundPackEditorWindow(),
        Surface.AudioSplit => new AudioSplitDialog(),
        _ => throw new ArgumentOutOfRangeException(nameof(surface), surface, null),
    };

    private static AudioSplitAnalysis CreateSplitAnalysis(string sourcePath) => new(
        sourcePath,
        SourceByteCount: 48_044,
        DurationSeconds: 0.5,
        SampleRate: 48_000,
        FrameCount: 24_000,
        Suggestion: new AudioSplitSuggestion(
            SplitTimeSeconds: 0.499,
            PressTransientTimeSeconds: 0.012,
            ValleyTimeSeconds: 0.48,
            ReleaseTransientTimeSeconds: 0.493,
            SuggestedReleaseEndTimeSeconds: 0.1,
            Confidence: 0.42f,
            UsedFallback: true),
        PressPreview: new AudioSplitSegmentPreview(0, 0.48, 0.48, 0.012, 0.7f, 0.1f, -3, -20),
        ReleasePreview: new AudioSplitSegmentPreview(0.48, 0.5, 0.02, 0.013, 0.5f, 0.08f, -6, -22),
        Waveform:
        [
            new AudioWaveformPoint(0, -0.1f, 0.2f, 0.05f),
            new AudioWaveformPoint(0.25, -0.6f, 0.7f, 0.2f),
            new AudioWaveformPoint(0.5, -0.2f, 0.3f, 0.08f),
        ],
        EnergyEnvelope: [],
        Warnings: new HashSet<AudioSplitWarning>
        {
            AudioSplitWarning.LowConfidence,
            AudioSplitWarning.FallbackValleyUsed,
            AudioSplitWarning.PossibleAdditionalKeystroke,
            AudioSplitWarning.SourceMayBeClipped,
        });

    private static IEnumerable<T> VisualDescendants<T>(DependencyObject root)
        where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match)
            {
                yield return match;
            }

            foreach (var descendant in VisualDescendants<T>(child))
            {
                yield return descendant;
            }
        }
    }

    public enum Surface
    {
        Tray,
        Statistics,
        DiyEditor,
        AudioSplit,
    }
}
