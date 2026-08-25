namespace Battuta.Windows.Tray;

/// <summary>
/// Pure physical-pixel placement logic for deterministic DPI and multi-monitor
/// tests. The caller is responsible for obtaining the target monitor work area.
/// </summary>
public static class TrayFlyoutPositioner
{
    public static TrayFlyoutPlacement Calculate(
        PixelRect iconBounds,
        PixelRect workArea,
        PixelSize requestedSize,
        int gap = 8)
    {
        if (workArea.Width <= 0 || workArea.Height <= 0)
        {
            throw new ArgumentException("The monitor work area must be non-empty.", nameof(workArea));
        }

        if (requestedSize.Width <= 0 || requestedSize.Height <= 0)
        {
            throw new ArgumentException("The flyout size must be positive.", nameof(requestedSize));
        }

        gap = Math.Max(0, gap);
        var width = Math.Min(requestedSize.Width, workArea.Width);
        var height = Math.Min(requestedSize.Height, workArea.Height);
        var edge = FindNearestEdge(iconBounds, workArea);

        var x = edge switch
        {
            TaskbarEdge.Left => iconBounds.Right + gap,
            TaskbarEdge.Right => iconBounds.Left - gap - width,
            TaskbarEdge.Top => iconBounds.Left,
            _ => iconBounds.Right - width,
        };
        var y = edge switch
        {
            TaskbarEdge.Top => iconBounds.Bottom + gap,
            TaskbarEdge.Bottom => iconBounds.Top - gap - height,
            _ => iconBounds.Bottom - height,
        };

        x = ClampPosition(x, workArea.Left, workArea.Right - width);
        y = ClampPosition(y, workArea.Top, workArea.Bottom - height);
        return new TrayFlyoutPlacement(x, y, width, height, edge);
    }

    public static TaskbarEdge FindNearestEdge(PixelRect iconBounds, PixelRect workArea)
    {
        var distances = new (TaskbarEdge Edge, long Distance)[]
        {
            (TaskbarEdge.Left, Math.Abs((long)iconBounds.CenterX - workArea.Left)),
            (TaskbarEdge.Top, Math.Abs((long)iconBounds.CenterY - workArea.Top)),
            (TaskbarEdge.Right, Math.Abs((long)workArea.Right - iconBounds.CenterX)),
            (TaskbarEdge.Bottom, Math.Abs((long)workArea.Bottom - iconBounds.CenterY)),
        };
        return distances.MinBy(value => value.Distance).Edge;
    }

    private static int ClampPosition(int value, int minimum, int maximum)
    {
        if (maximum < minimum)
        {
            return minimum;
        }

        return Math.Clamp(value, minimum, maximum);
    }
}
