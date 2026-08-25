using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Battuta.Windows.Controls;

public partial class IconTile : UserControl
{
    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(
        nameof(Glyph), typeof(string), typeof(IconTile), new PropertyMetadata("\uE9D2"));

    public static readonly DependencyProperty GlyphSizeProperty = DependencyProperty.Register(
        nameof(GlyphSize), typeof(double), typeof(IconTile), new PropertyMetadata(16d));

    public static readonly DependencyProperty GlyphBrushProperty = DependencyProperty.Register(
        nameof(GlyphBrush), typeof(Brush), typeof(IconTile),
        new PropertyMetadata(new SolidColorBrush(Color.FromRgb(145, 201, 43))));

    public static readonly DependencyProperty TileBrushProperty = DependencyProperty.Register(
        nameof(TileBrush), typeof(Brush), typeof(IconTile),
        new PropertyMetadata(new SolidColorBrush(Color.FromArgb(36, 184, 232, 77))));

    public static readonly DependencyProperty TileBorderBrushProperty = DependencyProperty.Register(
        nameof(TileBorderBrush), typeof(Brush), typeof(IconTile),
        new PropertyMetadata(new SolidColorBrush(Color.FromArgb(46, 184, 232, 77))));

    public IconTile() => InitializeComponent();

    public string Glyph { get => (string)GetValue(GlyphProperty); set => SetValue(GlyphProperty, value); }
    public double GlyphSize { get => (double)GetValue(GlyphSizeProperty); set => SetValue(GlyphSizeProperty, value); }
    public Brush GlyphBrush { get => (Brush)GetValue(GlyphBrushProperty); set => SetValue(GlyphBrushProperty, value); }
    public Brush TileBrush { get => (Brush)GetValue(TileBrushProperty); set => SetValue(TileBrushProperty, value); }
    public Brush TileBorderBrush { get => (Brush)GetValue(TileBorderBrushProperty); set => SetValue(TileBorderBrushProperty, value); }
}
