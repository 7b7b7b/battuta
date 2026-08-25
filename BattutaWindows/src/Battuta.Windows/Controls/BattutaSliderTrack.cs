using System.Windows;
using System.Windows.Media;

namespace Battuta.Windows.Controls;

/// <summary>
/// Draws a slider rail independently from WPF Track's repeat-button layout.
/// Keeping the rail geometry explicit makes the visible endpoints coincide
/// with the thumb centre at minimum and maximum values.
/// </summary>
public sealed class BattutaSliderTrack : FrameworkElement
{
    public static readonly DependencyProperty MinimumProperty = DependencyProperty.Register(
        nameof(Minimum),
        typeof(double),
        typeof(BattutaSliderTrack),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty MaximumProperty = DependencyProperty.Register(
        nameof(Maximum),
        typeof(double),
        typeof(BattutaSliderTrack),
        new FrameworkPropertyMetadata(1d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(
        nameof(Value),
        typeof(double),
        typeof(BattutaSliderTrack),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CompletedBrushProperty = DependencyProperty.Register(
        nameof(CompletedBrush),
        typeof(Brush),
        typeof(BattutaSliderTrack),
        new FrameworkPropertyMetadata(Brushes.YellowGreen, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RemainingBrushProperty = DependencyProperty.Register(
        nameof(RemainingBrush),
        typeof(Brush),
        typeof(BattutaSliderTrack),
        new FrameworkPropertyMetadata(
            new SolidColorBrush(Color.FromArgb(74, 255, 255, 255)),
            FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty RailThicknessProperty = DependencyProperty.Register(
        nameof(RailThickness),
        typeof(double),
        typeof(BattutaSliderTrack),
        new FrameworkPropertyMetadata(4d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ThumbRadiusProperty = DependencyProperty.Register(
        nameof(ThumbRadius),
        typeof(double),
        typeof(BattutaSliderTrack),
        new FrameworkPropertyMetadata(7d, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Minimum
    {
        get => (double)GetValue(MinimumProperty);
        set => SetValue(MinimumProperty, value);
    }

    public double Maximum
    {
        get => (double)GetValue(MaximumProperty);
        set => SetValue(MaximumProperty, value);
    }

    public double Value
    {
        get => (double)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    public Brush CompletedBrush
    {
        get => (Brush)GetValue(CompletedBrushProperty);
        set => SetValue(CompletedBrushProperty, value);
    }

    public Brush RemainingBrush
    {
        get => (Brush)GetValue(RemainingBrushProperty);
        set => SetValue(RemainingBrushProperty, value);
    }

    public double RailThickness
    {
        get => (double)GetValue(RailThicknessProperty);
        set => SetValue(RailThicknessProperty, value);
    }

    public double ThumbRadius
    {
        get => (double)GetValue(ThumbRadiusProperty);
        set => SetValue(ThumbRadiusProperty, value);
    }

    // Public read-only geometry is intentionally exposed for STA layout tests.
    public double TrackStartX => Math.Min(Math.Max(0, ThumbRadius), ActualWidth / 2d);

    public double TrackEndX => Math.Max(TrackStartX, ActualWidth - TrackStartX);

    public double TrackCenterY => ActualHeight / 2d;

    public double ProgressEndX
    {
        get
        {
            var range = Maximum - Minimum;
            var ratio = range > 0 && double.IsFinite(range)
                ? Math.Clamp((Value - Minimum) / range, 0, 1)
                : 0;
            return TrackStartX + ratio * (TrackEndX - TrackStartX);
        }
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        if (ActualWidth <= 0 || ActualHeight <= 0)
        {
            return;
        }

        var thickness = Math.Clamp(RailThickness, 1, ActualHeight);
        var remainingPen = MakeRailPen(RemainingBrush, thickness);
        drawingContext.DrawLine(
            remainingPen,
            new Point(TrackStartX, TrackCenterY),
            new Point(TrackEndX, TrackCenterY));

        if (ProgressEndX > TrackStartX)
        {
            var completedPen = MakeRailPen(CompletedBrush, thickness);
            drawingContext.DrawLine(
                completedPen,
                new Point(TrackStartX, TrackCenterY),
                new Point(ProgressEndX, TrackCenterY));
        }
    }

    private static Pen MakeRailPen(Brush brush, double thickness) => new(brush, thickness)
    {
        StartLineCap = PenLineCap.Round,
        EndLineCap = PenLineCap.Round,
    };
}
