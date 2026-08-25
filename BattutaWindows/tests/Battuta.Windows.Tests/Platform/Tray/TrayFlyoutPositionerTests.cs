using Battuta.Windows.Tray;

namespace Battuta.Windows.Tests.Platform.Tray;

public sealed class TrayFlyoutPositionerTests
{
    [Fact]
    public void BottomTaskbarPlacesFlyoutAboveAndInsideWorkArea()
    {
        var workArea = new PixelRect(0, 0, 1920, 1040);
        var icon = new PixelRect(1800, 1040, 1824, 1064);

        var placement = TrayFlyoutPositioner.Calculate(icon, workArea, new PixelSize(360, 760));

        Assert.Equal(TaskbarEdge.Bottom, placement.Edge);
        Assert.Equal(1464, placement.X);
        Assert.Equal(272, placement.Y);
        Assert.Equal(360, placement.Width);
        Assert.Equal(760, placement.Height);
    }

    [Fact]
    public void LeftTaskbarOnNegativeMonitorPlacesFlyoutToRight()
    {
        var workArea = new PixelRect(-1880, 0, 0, 1080);
        var icon = new PixelRect(-1920, 900, -1880, 940);

        var placement = TrayFlyoutPositioner.Calculate(icon, workArea, new PixelSize(450, 700));

        Assert.Equal(TaskbarEdge.Left, placement.Edge);
        Assert.Equal(-1872, placement.X);
        Assert.Equal(240, placement.Y);
    }

    [Fact]
    public void OversizedFlyoutIsClampedToWorkArea()
    {
        var workArea = new PixelRect(100, 100, 900, 700);
        var icon = new PixelRect(840, 700, 864, 724);

        var placement = TrayFlyoutPositioner.Calculate(icon, workArea, new PixelSize(1200, 900));

        Assert.Equal(100, placement.X);
        Assert.Equal(100, placement.Y);
        Assert.Equal(800, placement.Width);
        Assert.Equal(600, placement.Height);
    }
}
