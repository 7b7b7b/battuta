using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace Battuta.Windows.Controls;

public partial class BattutaWindowChrome : UserControl
{
    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(BattutaWindowChrome), new PropertyMetadata("Battuta"));

    public BattutaWindowChrome() => InitializeComponent();

    public string Title { get => (string)GetValue(TitleProperty); set => SetValue(TitleProperty, value); }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left && e.ClickCount == 2)
        {
            ToggleMaximize();
            return;
        }
        Window.GetWindow(this)?.DragMove();
    }

    private void CloseClick(object sender, RoutedEventArgs e) => Window.GetWindow(this)?.Close();
    private void MinimizeClick(object sender, RoutedEventArgs e)
    {
        if (Window.GetWindow(this) is { } window) window.WindowState = WindowState.Minimized;
    }
    private void MaximizeClick(object sender, RoutedEventArgs e) => ToggleMaximize();

    private void ToggleMaximize()
    {
        if (Window.GetWindow(this) is not { } window) return;
        window.WindowState = window.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    }
}
