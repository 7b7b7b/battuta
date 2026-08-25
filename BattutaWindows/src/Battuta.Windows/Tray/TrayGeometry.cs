namespace Battuta.Windows.Tray;

public readonly record struct PixelRect(int Left, int Top, int Right, int Bottom)
{
    public int Width => Math.Max(0, Right - Left);

    public int Height => Math.Max(0, Bottom - Top);

    public int CenterX => Left + Width / 2;

    public int CenterY => Top + Height / 2;
}

public readonly record struct PixelSize(int Width, int Height);

public readonly record struct PixelPoint(int X, int Y);

public enum TaskbarEdge
{
    Left,
    Top,
    Right,
    Bottom,
}

public readonly record struct TrayFlyoutPlacement(
    int X,
    int Y,
    int Width,
    int Height,
    TaskbarEdge Edge);
