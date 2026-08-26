using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace Battuta.Windows.Views.Stats;

internal sealed class ImmediateHeatmapCellDetails
{
    private readonly FrameworkElement _owner;
    private readonly string _fallbackHelp;
    private readonly ToolTip _toolTip;
    private string? _pinnedHelp;
    private Rect? _pinnedBounds;

    public ImmediateHeatmapCellDetails(FrameworkElement owner, string fallbackHelp)
    {
        _owner = owner;
        _fallbackHelp = fallbackHelp;
        _toolTip = new ToolTip
        {
            Content = fallbackHelp,
            Placement = PlacementMode.MousePoint,
            PlacementTarget = owner,
            HorizontalOffset = 12,
            VerticalOffset = 16,
            StaysOpen = true,
        };

        owner.ToolTip = _toolTip;
        ToolTipService.SetInitialShowDelay(owner, 0);
        ToolTipService.SetBetweenShowDelay(owner, 0);
        ToolTipService.SetShowDuration(owner, int.MaxValue);
        ToolTipService.SetIsEnabled(owner, false);
        owner.Unloaded += (_, _) => ClearPin();
    }

    public bool IsPinned => _pinnedHelp is not null;

    public Rect? PinnedBounds => _pinnedBounds;

    public void Hover(Point point, IReadOnlyList<(Rect Bounds, string Help)> cells)
    {
        if (IsPinned)
        {
            return;
        }

        if (TryFind(point, cells, out var cell))
        {
            Show(cell.Help);
        }
        else
        {
            Close();
        }
    }

    public void Pin(Point point, IReadOnlyList<(Rect Bounds, string Help)> cells)
    {
        if (!TryFind(point, cells, out var cell))
        {
            ClearPin();
            return;
        }

        if (_pinnedBounds == cell.Bounds
            && string.Equals(_pinnedHelp, cell.Help, StringComparison.Ordinal))
        {
            ClearPin();
            return;
        }

        _pinnedHelp = cell.Help;
        _pinnedBounds = cell.Bounds;
        Show(cell.Help);
    }

    public void Synchronize(IReadOnlyList<(Rect Bounds, string Help)> cells)
    {
        if (_pinnedHelp is null)
        {
            return;
        }

        foreach (var cell in cells)
        {
            if (string.Equals(cell.Help, _pinnedHelp, StringComparison.Ordinal))
            {
                _pinnedBounds = cell.Bounds;
                return;
            }
        }

        ClearPin();
    }

    public void HideWhenUnpinned()
    {
        if (!IsPinned)
        {
            Close();
        }
    }

    public bool ClearPin()
    {
        var wasPinned = IsPinned;
        _pinnedHelp = null;
        _pinnedBounds = null;
        Close();
        return wasPinned;
    }

    private void Show(string help)
    {
        _toolTip.Content = help;
        AutomationProperties.SetHelpText(_owner, help);
        _toolTip.IsOpen = true;
    }

    private void Close()
    {
        _toolTip.IsOpen = false;
        _toolTip.Content = _fallbackHelp;
        AutomationProperties.SetHelpText(_owner, _fallbackHelp);
    }

    private static bool TryFind(
        Point point,
        IReadOnlyList<(Rect Bounds, string Help)> cells,
        out (Rect Bounds, string Help) match)
    {
        for (var index = cells.Count - 1; index >= 0; index--)
        {
            if (cells[index].Bounds.Contains(point))
            {
                match = cells[index];
                return true;
            }
        }

        match = (Rect.Empty, string.Empty);
        return false;
    }
}
