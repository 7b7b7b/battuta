using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Battuta.Windows.Controls;

public partial class StatusPill : UserControl
{
    private static readonly Color AccentStrong = Color.FromRgb(145, 201, 43);

    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(StatusPill), new PropertyMetadata("本地统计"));
    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(
        nameof(Glyph), typeof(string), typeof(StatusPill), new PropertyMetadata("\uE9D2"));
    public static readonly DependencyProperty TextBrushProperty = DependencyProperty.Register(
        nameof(TextBrush), typeof(Brush), typeof(StatusPill),
        new PropertyMetadata(new SolidColorBrush(AccentStrong)));
    public static readonly DependencyProperty PillBrushProperty = DependencyProperty.Register(
        nameof(PillBrush), typeof(Brush), typeof(StatusPill),
        new PropertyMetadata(new SolidColorBrush(Color.FromArgb(28, AccentStrong.R, AccentStrong.G, AccentStrong.B))));
    public static readonly DependencyProperty PillBorderBrushProperty = DependencyProperty.Register(
        nameof(PillBorderBrush), typeof(Brush), typeof(StatusPill),
        new PropertyMetadata(new SolidColorBrush(Color.FromArgb(41, AccentStrong.R, AccentStrong.G, AccentStrong.B))));

    public StatusPill() => InitializeComponent();

    public string Text { get => (string)GetValue(TextProperty); set => SetValue(TextProperty, value); }
    public string Glyph { get => (string)GetValue(GlyphProperty); set => SetValue(GlyphProperty, value); }
    public Brush TextBrush { get => (Brush)GetValue(TextBrushProperty); set => SetValue(TextBrushProperty, value); }
    public Brush PillBrush { get => (Brush)GetValue(PillBrushProperty); set => SetValue(PillBrushProperty, value); }
    public Brush PillBorderBrush { get => (Brush)GetValue(PillBorderBrushProperty); set => SetValue(PillBorderBrushProperty, value); }
}
