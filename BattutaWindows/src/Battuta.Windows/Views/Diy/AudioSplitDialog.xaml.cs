using System.ComponentModel;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Media;
using Battuta.Core.Audio;
using Battuta.Windows.Diy.Audio;
using Battuta.Windows.Diy.ViewModels;

namespace Battuta.Windows.Views.Diy;

public partial class AudioSplitDialog : Window
{
    private const double MinimumSegmentSeconds = 0.012;
    private const double MinimumReleaseGapSeconds = 0.013;
    private const double ReservedTailSeconds = 0.020;

    private static readonly Color AccentStrong = Color.FromRgb(145, 201, 43);
    private static readonly Color Orange = Color.FromRgb(245, 162, 58);

    private DiySoundPackEditorViewModel? editor;
    private DiySplitDraft? draft;
    private bool stateInitialized;
    private bool allowClose;

    public AudioSplitDialog()
    {
        InitializeComponent();
        Closing += OnClosing;
        Closed += OnClosed;
        DataContextChanged += OnDataContextChanged;
        RefreshWorkingState();
    }

    public AudioSplitDialog(DiySoundPackEditorViewModel editor, DiySplitDraft draft)
        : this()
    {
        Initialize(editor, draft);
        DataContext = editor;
    }

    public double SplitTimeSeconds => SplitSlider.Value / 1_000;
    public double ReleaseEndTimeSeconds => ReleaseEndSlider.Value / 1_000;

    public void Initialize(DiySoundPackEditorViewModel editor, DiySplitDraft draft)
    {
        ArgumentNullException.ThrowIfNull(editor);
        ArgumentNullException.ThrowIfNull(draft);

        if (this.editor is not null)
        {
            this.editor.PropertyChanged -= EditorPropertyChanged;
        }

        this.editor = editor;
        this.draft = draft;
        this.editor.PropertyChanged += EditorPropertyChanged;

        var duration = FiniteOrDefault(draft.Analysis.DurationSeconds, MinimumSegmentSeconds * 2.5);
        var maximumSplit = Math.Max(MinimumSegmentSeconds, duration - ReservedTailSeconds);
        var suggestedSplit = FiniteOrDefault(
            draft.Analysis.Suggestion.SplitTimeSeconds,
            MinimumSegmentSeconds);
        var initialSplit = Math.Clamp(suggestedSplit, MinimumSegmentSeconds, maximumSplit);
        var suggestedReleaseEnd = FiniteOrDefault(
            draft.Analysis.Suggestion.SuggestedReleaseEndTimeSeconds ?? duration,
            duration);
        var initialReleaseEnd = Math.Max(
            initialSplit + MinimumReleaseGapSeconds,
            Math.Min(duration, suggestedReleaseEnd));

        stateInitialized = false;
        SplitSlider.Minimum = ToMilliseconds(MinimumSegmentSeconds);
        SplitSlider.Maximum = ToMilliseconds(maximumSplit);
        SplitSlider.Value = ToMilliseconds(initialSplit);
        ReleaseEndSlider.Maximum = ToMilliseconds(duration);
        ReleaseEndSlider.Minimum = ToMilliseconds(Math.Min(
            duration,
            initialSplit + MinimumReleaseGapSeconds));
        ReleaseEndSlider.Value = ToMilliseconds(Math.Min(duration, initialReleaseEnd));
        stateInitialized = true;

        Waveform.Analysis = draft.Analysis;
        SuggestionLabel.Text = string.Format(
            CultureInfo.CurrentCulture,
            "建议：{0} · 回弹瞬态约在 {1}",
            FormatTime(draft.Analysis.Suggestion.SplitTimeSeconds),
            FormatTime(draft.Analysis.Suggestion.ReleaseTransientTimeSeconds));
        TargetLabel.Text = $"将设置到：{draft.Target.DisplayName}";
        PopulateConfidence(draft.Analysis.Suggestion.Confidence);
        PopulateWarnings(draft.Analysis.Warnings);
        RefreshTimePresentation();
        RefreshWorkingState();
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.NewValue is DiySoundPackEditorViewModel candidate &&
            candidate.SplitDraft is { } candidateDraft &&
            (editor != candidate || draft?.Id != candidateDraft.Id))
        {
            Initialize(candidate, candidateDraft);
        }
    }

    private void EditorPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(DiySoundPackEditorViewModel.IsWorking))
        {
            return;
        }

        if (Dispatcher.CheckAccess())
        {
            RefreshWorkingState();
        }
        else
        {
            _ = Dispatcher.BeginInvoke(RefreshWorkingState);
        }
    }

    private void RefreshWorkingState()
    {
        var hasContext = editor is not null && draft is not null;
        var isWorking = editor?.IsWorking == true;
        PreviewButtonsPanel.IsEnabled = hasContext && !isWorking;
        ConfirmButton.IsEnabled = hasContext && !isWorking;
        CancelButton.IsEnabled = !isWorking;
        BusyIndicator.Visibility = isWorking ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void PreviewPressClick(object sender, RoutedEventArgs e) =>
        await PreviewAsync(KeySoundPhase.Press);

    private async void PreviewReleaseClick(object sender, RoutedEventArgs e) =>
        await PreviewAsync(KeySoundPhase.Release);

    private async Task PreviewAsync(KeySoundPhase phase)
    {
        if (editor is null || draft is null || editor.IsWorking)
        {
            return;
        }

        await editor.PreviewSplitAsync(
            draft,
            SplitTimeSeconds,
            ReleaseEndTimeSeconds,
            phase);
    }

    private void SplitSliderValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!stateInitialized)
        {
            return;
        }

        var duration = ToMilliseconds(draft?.Analysis.DurationSeconds ?? 0);
        var releaseMinimum = Math.Min(
            duration,
            SplitSlider.Value + ToMilliseconds(MinimumReleaseGapSeconds));
        ReleaseEndSlider.Minimum = releaseMinimum;
        if (ReleaseEndSlider.Value < releaseMinimum)
        {
            ReleaseEndSlider.Value = releaseMinimum;
        }

        RefreshTimePresentation();
    }

    private void ReleaseEndSliderValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (stateInitialized)
        {
            RefreshTimePresentation();
        }
    }

    private void RefreshTimePresentation()
    {
        SplitTimeLabel.Text = FormatMilliseconds(SplitSlider.Value);
        ReleaseEndTimeLabel.Text = FormatMilliseconds(ReleaseEndSlider.Value);
        Waveform.SplitTimeSeconds = SplitTimeSeconds;
        Waveform.ReleaseEndTimeSeconds = ReleaseEndTimeSeconds;
        AutomationProperties.SetHelpText(
            Waveform,
            $"切点 {TruncateMilliseconds(SplitTimeSeconds)} 毫秒");
        AutomationProperties.SetHelpText(SplitSlider, SplitTimeLabel.Text);
        AutomationProperties.SetHelpText(ReleaseEndSlider, ReleaseEndTimeLabel.Text);
    }

    private async void ConfirmClick(object sender, RoutedEventArgs e)
    {
        if (editor is null || draft is null || editor.IsWorking)
        {
            return;
        }

        var succeeded = await editor.ConfirmSplitAsync(
            draft,
            SplitTimeSeconds,
            ReleaseEndTimeSeconds);
        if (succeeded)
        {
            CompleteDialog(true);
        }
    }

    private void CancelClick(object sender, RoutedEventArgs e)
    {
        if (editor?.IsWorking == true)
        {
            return;
        }

        CancelDraftIfCurrent();
        CompleteDialog(false);
    }

    private void OnWindowKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        if (editor?.IsWorking == true)
        {
            return;
        }

        CancelDraftIfCurrent();
        CompleteDialog(false);
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (!allowClose && editor?.IsWorking == true)
        {
            e.Cancel = true;
        }
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        if (editor is not null)
        {
            editor.PropertyChanged -= EditorPropertyChanged;
        }

        CancelDraftIfCurrent();
    }

    private void CompleteDialog(bool result)
    {
        allowClose = true;
        DialogResult = result;
    }

    private void CancelDraftIfCurrent()
    {
        if (editor is { } currentEditor &&
            draft is { } currentDraft &&
            currentEditor.SplitDraft?.Id == currentDraft.Id)
        {
            currentEditor.CancelSplit();
        }
    }

    private void PopulateConfidence(float rawConfidence)
    {
        var confidence = float.IsFinite(rawConfidence)
            ? Math.Clamp(rawConfidence, 0, 1)
            : 0;
        ConfidencePill.Text = string.Format(
            CultureInfo.CurrentCulture,
            "置信度 {0:P0}",
            confidence);

        var color = confidence >= 0.7f ? AccentStrong : Orange;
        ConfidencePill.Glyph = confidence >= 0.7f ? "\uE73E" : "\uE7BA";
        ConfidencePill.TextBrush = MakeBrush(color);
        ConfidencePill.PillBrush = MakeBrush(Color.FromArgb(28, color.R, color.G, color.B));
        ConfidencePill.PillBorderBrush = MakeBrush(Color.FromArgb(41, color.R, color.G, color.B));
    }

    private void PopulateWarnings(IReadOnlySet<AudioSplitWarning> warnings)
    {
        var messages = warnings
            .OrderBy(WarningSortOrder)
            .Select(WarningMessage)
            .ToArray();
        WarningsItems.ItemsSource = messages;
        WarningsScroller.Visibility = messages.Length == 0
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private static int WarningSortOrder(AudioSplitWarning warning) => warning switch
    {
        AudioSplitWarning.FallbackValleyUsed => 0,
        AudioSplitWarning.LowConfidence => 1,
        AudioSplitWarning.PossibleAdditionalKeystroke => 2,
        AudioSplitWarning.SourceMayBeClipped => 3,
        _ => int.MaxValue,
    };

    private static string WarningMessage(AudioSplitWarning warning) => warning switch
    {
        AudioSplitWarning.LowConfidence => "自动切点置信度较低，请仔细检查波形。",
        AudioSplitWarning.FallbackValleyUsed => "未找到明显回弹瞬态，当前切点使用能量谷值。",
        AudioSplitWarning.PossibleAdditionalKeystroke => "检测到可能的下一次击键，已建议提前结束。",
        AudioSplitWarning.SourceMayBeClipped => "源录音可能削波，建议降低录音增益后重试。",
        _ => warning.ToString(),
    };

    private static double FiniteOrDefault(double value, double fallback) =>
        double.IsFinite(value) ? value : fallback;

    private static double ToMilliseconds(double seconds) => seconds * 1_000;

    private static int TruncateMilliseconds(double seconds) => (int)ToMilliseconds(seconds);

    private static string FormatTime(double seconds) => FormatMilliseconds(ToMilliseconds(seconds));

    private static string FormatMilliseconds(double milliseconds) => string.Format(
        CultureInfo.CurrentCulture,
        "{0:N0} ms",
        milliseconds);

    private static SolidColorBrush MakeBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}

public sealed class AudioSplitWaveform : FrameworkElement
{
    private const double CornerRadius = 10;
    private const double CanvasPadding = 8;

    private static readonly Brush FallbackSurface = FrozenBrush(Color.FromArgb(242, 37, 41, 37));
    private static readonly Brush PressRegion = FrozenBrush(Color.FromArgb(26, 184, 232, 77));
    private static readonly Brush ReleaseRegion = FrozenBrush(Color.FromArgb(20, 64, 184, 209));
    private static readonly Brush IgnoredRegion = FrozenBrush(Color.FromArgb(20, 255, 255, 255));
    private static readonly Brush WaveformBrush = FrozenBrush(Color.FromArgb(230, 145, 201, 43));
    private static readonly Brush CenterLineBrush = FrozenBrush(Color.FromArgb(46, 255, 255, 255));
    private static readonly Brush SplitMarkerBrush = FrozenBrush(Color.FromRgb(145, 201, 43));
    private static readonly Brush EndMarkerBrush = FrozenBrush(Color.FromArgb(166, 255, 255, 255));
    private static readonly Brush LabelBackground = FrozenBrush(Color.FromArgb(204, 37, 41, 37));
    private static readonly Brush LabelText = FrozenBrush(Color.FromArgb(148, 255, 255, 255));

    private AudioSplitAnalysis? analysis;
    private double splitTimeSeconds;
    private double releaseEndTimeSeconds;

    public AudioSplitAnalysis? Analysis
    {
        get => analysis;
        set
        {
            analysis = value;
            InvalidateVisual();
        }
    }

    public double SplitTimeSeconds
    {
        get => splitTimeSeconds;
        set
        {
            splitTimeSeconds = value;
            InvalidateVisual();
        }
    }

    public double ReleaseEndTimeSeconds
    {
        get => releaseEndTimeSeconds;
        set
        {
            releaseEndTimeSeconds = value;
            InvalidateVisual();
        }
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        if (bounds.Width <= 0 || bounds.Height <= 0)
        {
            return;
        }

        var surface = TryFindResource("Battuta.SurfaceBrush") as Brush ?? FallbackSurface;
        drawingContext.DrawRoundedRectangle(surface, null, bounds, CornerRadius, CornerRadius);

        drawingContext.PushClip(new RectangleGeometry(bounds, CornerRadius, CornerRadius));
        var splitX = XPosition(SplitTimeSeconds, bounds.Width);
        var releaseX = XPosition(ReleaseEndTimeSeconds, bounds.Width);
        drawingContext.DrawRectangle(PressRegion, null, new Rect(0, 0, splitX, bounds.Height));
        drawingContext.DrawRectangle(
            ReleaseRegion,
            null,
            new Rect(splitX, 0, Math.Max(0, releaseX - splitX), bounds.Height));
        drawingContext.DrawRectangle(
            IgnoredRegion,
            null,
            new Rect(releaseX, 0, Math.Max(0, bounds.Width - releaseX), bounds.Height));

        DrawWaveform(drawingContext, bounds);
        drawingContext.DrawLine(
            new Pen(SplitMarkerBrush, 2),
            new Point(splitX, 0),
            new Point(splitX, bounds.Height));
        drawingContext.DrawLine(
            new Pen(EndMarkerBrush, 1),
            new Point(releaseX, 0),
            new Point(releaseX, bounds.Height));
        DrawRegionLabel(drawingContext, "按下", splitX / 2, bounds.Width);
        DrawRegionLabel(
            drawingContext,
            "回弹",
            splitX + ((releaseX - splitX) / 2),
            bounds.Width);
        DrawRegionLabel(
            drawingContext,
            "忽略",
            releaseX + ((bounds.Width - releaseX) / 2),
            bounds.Width);
        DrawScissors(drawingContext, splitX);
        drawingContext.Pop();
    }

    private void DrawWaveform(DrawingContext drawingContext, Rect bounds)
    {
        if (Analysis is not { DurationSeconds: > 0 } current || current.Waveform.Count == 0)
        {
            return;
        }

        var innerWidth = Math.Max(0, bounds.Width - (CanvasPadding * 2));
        var innerHeight = Math.Max(0, bounds.Height - (CanvasPadding * 2));
        var midpoint = CanvasPadding + (innerHeight / 2);
        var amplitude = Math.Max(1, innerHeight * 0.43);
        var waveformPen = new Pen(WaveformBrush, 1);

        foreach (var point in current.Waveform)
        {
            var x = CanvasPadding + Math.Clamp(
                point.TimeSeconds / current.DurationSeconds,
                0,
                1) * innerWidth;
            var upper = midpoint - (point.Maximum * amplitude);
            var lower = midpoint - (point.Minimum * amplitude);
            drawingContext.DrawLine(waveformPen, new Point(x, upper), new Point(x, lower));
        }

        drawingContext.DrawLine(
            new Pen(CenterLineBrush, 1),
            new Point(CanvasPadding, midpoint),
            new Point(bounds.Width - CanvasPadding, midpoint));
    }

    private void DrawRegionLabel(
        DrawingContext drawingContext,
        string title,
        double desiredX,
        double width)
    {
        var text = MakeText(title, 10, FontWeights.SemiBold, LabelText, "Segoe UI Variable");
        var labelWidth = text.WidthIncludingTrailingWhitespace + 10;
        var labelHeight = text.Height + 6;
        var centerX = Math.Clamp(desiredX, 24, Math.Max(24, width - 24));
        var rect = new Rect(
            centerX - (labelWidth / 2),
            18 - (labelHeight / 2),
            labelWidth,
            labelHeight);
        drawingContext.DrawRoundedRectangle(
            LabelBackground,
            null,
            rect,
            labelHeight / 2,
            labelHeight / 2);
        drawingContext.DrawText(
            text,
            new Point(centerX - (text.WidthIncludingTrailingWhitespace / 2), 18 - (text.Height / 2)));
    }

    private void DrawScissors(DrawingContext drawingContext, double splitX)
    {
        const double diameter = 24;
        var circle = new Rect(splitX - (diameter / 2), 7, diameter, diameter);
        drawingContext.DrawEllipse(
            LabelBackground,
            null,
            new Point(splitX, 7 + (diameter / 2)),
            diameter / 2,
            diameter / 2);
        var glyph = MakeText("\uE8C6", 11, FontWeights.Normal, LabelText, "Segoe Fluent Icons");
        drawingContext.DrawText(
            glyph,
            new Point(
                circle.X + ((diameter - glyph.WidthIncludingTrailingWhitespace) / 2),
                circle.Y + ((diameter - glyph.Height) / 2)));
    }

    private double XPosition(double timeSeconds, double width)
    {
        if (Analysis is not { DurationSeconds: > 0 } current)
        {
            return 0;
        }

        return Math.Clamp(timeSeconds / current.DurationSeconds * width, 0, width);
    }

    private FormattedText MakeText(
        string text,
        double size,
        FontWeight weight,
        Brush brush,
        string fontFamily) => new(
            text,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily(fontFamily), FontStyles.Normal, weight, FontStretches.Normal),
            size,
            brush,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);

    private static SolidColorBrush FrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
