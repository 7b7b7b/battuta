using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using Battuta.Core.Input;
using Battuta.Windows.Stats.Visualization;

namespace Battuta.Windows.Controls.Keyboard;

public enum KeyboardCanvasMode
{
    Statistics,
    Editor,
}

public sealed class KeyboardCanvasKeyEventArgs(PhysicalKeyId key) : EventArgs
{
    public PhysicalKeyId Key { get; } = key;
}

public sealed class KeyboardCanvas : FrameworkElement
{
    public static readonly DependencyProperty ModeProperty = DependencyProperty.Register(
        nameof(Mode),
        typeof(KeyboardCanvasMode),
        typeof(KeyboardCanvas),
        new FrameworkPropertyMetadata(
            KeyboardCanvasMode.Editor,
            FrameworkPropertyMetadataOptions.AffectsRender | FrameworkPropertyMetadataOptions.AffectsMeasure));

    public static readonly DependencyProperty SelectedKeyProperty = DependencyProperty.Register(
        nameof(SelectedKey),
        typeof(PhysicalKeyId),
        typeof(KeyboardCanvas),
        new FrameworkPropertyMetadata(PhysicalKeys.KeyA, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty IsInteractiveProperty = DependencyProperty.Register(
        nameof(IsInteractive),
        typeof(bool),
        typeof(KeyboardCanvas),
        new PropertyMetadata(true));

    public static readonly DependencyProperty KeyCountsProperty = DependencyProperty.Register(
        nameof(KeyCounts),
        typeof(IReadOnlyDictionary<PhysicalKeyId, long>),
        typeof(KeyboardCanvas),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    private readonly List<(Rect Bounds, PhysicalKeyId Key)> _hitTargets = [];
    private readonly ToolTip _keyToolTip;
    private PhysicalKeyId? _pressedKey;

    public KeyboardCanvas()
    {
        SnapsToDevicePixels = true;
        Focusable = true;
        AutomationProperties.SetName(this, "Windows ANSI 键盘");
        _keyToolTip = new ToolTip
        {
            Content = "Windows ANSI 键盘",
            Placement = PlacementMode.MousePoint,
            PlacementTarget = this,
            HorizontalOffset = 12,
            VerticalOffset = 16,
            StaysOpen = true,
        };
        ToolTip = _keyToolTip;
        ToolTipService.SetInitialShowDelay(this, 0);
        ToolTipService.SetBetweenShowDelay(this, 0);
        ToolTipService.SetShowDuration(this, int.MaxValue);
        ToolTipService.SetIsEnabled(this, false);
        Unloaded += (_, _) => _keyToolTip.IsOpen = false;
    }

    public event EventHandler<KeyboardCanvasKeyEventArgs>? KeyPressed;

    public event EventHandler<KeyboardCanvasKeyEventArgs>? KeyReleased;

    public KeyboardCanvasMode Mode
    {
        get => (KeyboardCanvasMode)GetValue(ModeProperty);
        set => SetValue(ModeProperty, value);
    }

    public PhysicalKeyId SelectedKey
    {
        get => (PhysicalKeyId)GetValue(SelectedKeyProperty);
        set => SetValue(SelectedKeyProperty, value);
    }

    public bool IsInteractive
    {
        get => (bool)GetValue(IsInteractiveProperty);
        set => SetValue(IsInteractiveProperty, value);
    }

    public IReadOnlyDictionary<PhysicalKeyId, long>? KeyCounts
    {
        get => (IReadOnlyDictionary<PhysicalKeyId, long>?)GetValue(KeyCountsProperty);
        set => SetValue(KeyCountsProperty, value);
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        var ideal = Mode == KeyboardCanvasMode.Statistics
            ? new Size(691, 282)
            : new Size(547, 217);
        if (double.IsInfinity(availableSize.Width))
        {
            return ideal;
        }

        var width = Math.Max(1, availableSize.Width);
        return new Size(width, width * ideal.Height / ideal.Width);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        _hitTargets.Clear();

        var statistics = Mode == KeyboardCanvasMode.Statistics;
        var pitch = statistics ? 48d : 38d;
        var gap = statistics ? 5d : 4d;
        var keyHeight = statistics ? 42d : 32d;
        var rowGap = statistics ? 6d : 5d;
        var splitGap = statistics ? 3d : 2d;
        var layout = WindowsAnsiVisualLayoutCatalog.CompactAnsi;
        var baseWidth = layout.WidthUnits * pitch - gap;
        var baseHeight = layout.RowCount * keyHeight + Math.Max(0, layout.RowCount - 1) * rowGap;
        var scale = Math.Max(.1, Math.Min(ActualWidth / baseWidth, ActualHeight / baseHeight));
        var offsetX = Math.Max(0, (ActualWidth - baseWidth * scale) / 2);
        var offsetY = Math.Max(0, (ActualHeight - baseHeight * scale) / 2);
        var heatScale = AdaptiveHeatScale.FromNonZero(
            layout.Placements
                .Where(placement => placement.KeyId.HasValue)
                .Select(placement => placement.KeyId!.Value)
                .Distinct()
                .Select(CountFor));

        drawingContext.PushTransform(new TranslateTransform(offsetX, offsetY));
        drawingContext.PushTransform(new ScaleTransform(scale, scale));
        foreach (var placement in layout.Placements)
        {
            if (placement.KeyId is not { } keyId)
            {
                continue;
            }

            var x = placement.XUnits * pitch;
            var width = placement.WidthUnits * pitch - gap;
            var rowY = placement.Row * (keyHeight + rowGap);
            Rect bounds;
            if (placement.VerticalSlot == KeyboardVisualVerticalSlot.Full)
            {
                bounds = new Rect(x, rowY, width, keyHeight);
            }
            else
            {
                var halfHeight = (keyHeight - splitGap) / 2;
                bounds = placement.VerticalSlot == KeyboardVisualVerticalSlot.UpperHalf
                    ? new Rect(x, rowY, width, halfHeight)
                    : new Rect(x, rowY + halfHeight + splitGap, width, halfHeight);
            }

            var row = WindowsKeyDisplayCatalog.Get(keyId).SoundRow;
            DrawKey(
                drawingContext,
                bounds,
                placement.Label,
                keyId,
                row,
                statistics,
                scale,
                offsetX,
                offsetY,
                heatScale);
        }

        drawingContext.Pop();
        drawingContext.Pop();
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (!IsInteractive || Mode != KeyboardCanvasMode.Editor)
        {
            return;
        }

        var point = e.GetPosition(this);
        var target = _hitTargets.LastOrDefault(item => item.Bounds.Contains(point));
        if (!target.Key.IsValid)
        {
            return;
        }

        Focus();
        CaptureMouse();
        _pressedKey = target.Key;
        SelectedKey = target.Key;
        InvalidateVisual();
        KeyPressed?.Invoke(this, new KeyboardCanvasKeyEventArgs(target.Key));
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        var released = _pressedKey;
        _pressedKey = null;
        if (IsMouseCaptured)
        {
            ReleaseMouseCapture();
        }

        InvalidateVisual();
        if (released is { } key)
        {
            KeyReleased?.Invoke(this, new KeyboardCanvasKeyEventArgs(key));
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var point = e.GetPosition(this);
        var target = _hitTargets.LastOrDefault(item => item.Bounds.Contains(point));
        if (!target.Key.IsValid)
        {
            _keyToolTip.IsOpen = false;
            _keyToolTip.Content = "Windows ANSI 键盘";
            return;
        }

        var label = WindowsKeyDisplayCatalog.LabelFor(target.Key);
        _keyToolTip.Content = Mode == KeyboardCanvasMode.Statistics
            ? $"{label}：{CountFor(target.Key).ToString("N0", CultureInfo.CurrentCulture)} 次"
            : label;
        _keyToolTip.IsOpen = true;
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        _keyToolTip.IsOpen = false;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.Key == Key.Tab)
        {
            MoveSequential(System.Windows.Input.Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) ? -1 : 1);
            e.Handled = true;
            return;
        }

        var direction = e.Key switch
        {
            Key.Left => NavigationDirection.Left,
            Key.Right => NavigationDirection.Right,
            Key.Up => NavigationDirection.Up,
            Key.Down => NavigationDirection.Down,
            _ => NavigationDirection.None,
        };
        if (direction != NavigationDirection.None)
        {
            MoveDirectional(direction);
            e.Handled = true;
            return;
        }

        if (e.Key is Key.Enter or Key.Space
            && IsInteractive
            && Mode == KeyboardCanvasMode.Editor
            && _pressedKey is null)
        {
            PressSelectedKey();
            e.Handled = true;
        }
    }

    protected override void OnKeyUp(KeyEventArgs e)
    {
        base.OnKeyUp(e);
        if (e.Key is Key.Enter or Key.Space && _pressedKey is { } pressed)
        {
            _pressedKey = null;
            InvalidateVisual();
            KeyReleased?.Invoke(this, new KeyboardCanvasKeyEventArgs(pressed));
            e.Handled = true;
        }
    }

    protected override AutomationPeer OnCreateAutomationPeer() =>
        new KeyboardCanvasAutomationPeer(this);

    private void DrawKey(
        DrawingContext drawingContext,
        Rect bounds,
        string label,
        PhysicalKeyId keyId,
        KeyboardRowId soundRow,
        bool statistics,
        double scale,
        double offsetX,
        double offsetY,
        AdaptiveHeatScale heatScale)
    {
        _hitTargets.Add((
            new Rect(
                offsetX + bounds.X * scale,
                offsetY + bounds.Y * scale,
                bounds.Width * scale,
                bounds.Height * scale),
            keyId));

        var selected = SelectedKey == keyId && (!statistics || IsKeyboardFocusWithin);
        var pressed = !statistics && _pressedKey == keyId;
        var rowColor = RowColor(soundRow);
        Brush fill;
        Pen border;
        var count = CountFor(keyId);
        var heatIntensity = 0d;
        if (statistics)
        {
            heatIntensity = heatScale.Normalize(count);
            var heatColor = BattutaHeatmapPalette.SequentialColor(heatIntensity);
            fill = new SolidColorBrush(count == 0
                ? Color.FromArgb(230, 37, 41, 37)
                : heatColor);
            border = new Pen(
                new SolidColorBrush(count == 0
                    ? Color.FromArgb(48, 255, 255, 255)
                    : heatColor),
                1);
        }
        else
        {
            var alpha = pressed ? (byte)77 : selected ? (byte)51 : (byte)28;
            fill = new SolidColorBrush(Color.FromArgb(alpha, rowColor.R, rowColor.G, rowColor.B));
            border = new Pen(
                selected
                    ? new SolidColorBrush(Color.FromRgb(145, 201, 43))
                    : new SolidColorBrush(Color.FromArgb(70, rowColor.R, rowColor.G, rowColor.B)),
                selected ? 2 : 1);
        }

        var radius = statistics ? 7 : 6;
        drawingContext.DrawRoundedRectangle(fill, border, bounds, radius, radius);
        if (statistics && selected)
        {
            drawingContext.DrawRoundedRectangle(
                null,
                new Pen(new SolidColorBrush(Color.FromRgb(184, 232, 77)), 2),
                bounds,
                radius,
                radius);
        }
        var labelFont = statistics && bounds.Height >= 30 ? 10d : 9d;
        var typeface = new Typeface(
            new FontFamily("Segoe UI Variable"),
            FontStyles.Normal,
            selected ? FontWeights.SemiBold : FontWeights.Normal,
            FontStretches.Normal);
        var activeTextColor = heatIntensity >= .70
            ? Color.FromArgb(214, 0, 0, 0)
            : Color.FromArgb(240, 255, 255, 255);
        var labelColor = statistics && count > 0
            ? activeTextColor
            : Color.FromArgb(235, 255, 255, 255);
        var text = new FormattedText(
            label,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            typeface,
            labelFont,
            new SolidColorBrush(labelColor),
            VisualTreeHelper.GetDpi(this).PixelsPerDip)
        {
            MaxTextWidth = Math.Max(2, bounds.Width - 6),
            MaxLineCount = 1,
            Trimming = TextTrimming.CharacterEllipsis,
            TextAlignment = TextAlignment.Center,
        };

        if (statistics && bounds.Height >= 30)
        {
            drawingContext.DrawText(text, new Point(bounds.X + 3, bounds.Y + 7));
            var countText = new FormattedText(
                CompactCount(count),
                CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                new Typeface(
                    new FontFamily("Segoe UI Variable"),
                    FontStyles.Normal,
                    count > 0 ? FontWeights.SemiBold : FontWeights.Normal,
                    FontStretches.Normal),
                8.5,
                new SolidColorBrush(count > 0
                    ? activeTextColor
                    : Color.FromArgb(110, 255, 255, 255)),
                VisualTreeHelper.GetDpi(this).PixelsPerDip)
            {
                MaxTextWidth = Math.Max(2, bounds.Width - 6),
                TextAlignment = TextAlignment.Center,
                MaxLineCount = 1,
            };
            drawingContext.DrawText(countText, new Point(bounds.X + 3, bounds.Bottom - 16));
        }
        else
        {
            drawingContext.DrawText(
                text,
                new Point(bounds.X + 3, bounds.Y + Math.Max(1, (bounds.Height - text.Height) / 2)));
        }

        if (selected)
        {
            AutomationProperties.SetHelpText(
                this,
                statistics
                    ? $"已选 {label}，{count.ToString("N0", CultureInfo.CurrentCulture)} 次。使用方向键或 Tab 浏览按键。"
                    : $"已选 {label}。使用方向键或 Tab 移动，按 Enter 或空格试听。");
        }
    }

    private void MoveSequential(int offset)
    {
        var placements = WindowsAnsiVisualLayoutCatalog.CompactAnsi.Placements
            .Where(placement => placement.KeyId.HasValue)
            .ToArray();
        if (placements.Length == 0)
        {
            return;
        }

        var index = Array.FindIndex(placements, placement => placement.KeyId == SelectedKey);
        index = index < 0 ? 0 : (index + offset + placements.Length) % placements.Length;
        SelectKey(placements[index].KeyId!.Value);
    }

    private void MoveDirectional(NavigationDirection direction)
    {
        var placements = WindowsAnsiVisualLayoutCatalog.CompactAnsi.Placements
            .Where(placement => placement.KeyId.HasValue)
            .ToArray();
        var current = placements.FirstOrDefault(placement => placement.KeyId == SelectedKey)
            ?? placements.FirstOrDefault();
        if (current is null)
        {
            return;
        }

        var currentCenterX = current.XUnits + current.WidthUnits / 2;
        var currentCenterY = current.Row + VerticalOffset(current.VerticalSlot);
        KeyboardVisualPlacement? target = null;
        var bestScore = double.PositiveInfinity;
        foreach (var candidate in placements)
        {
            if (candidate.KeyId == current.KeyId)
            {
                continue;
            }

            var candidateX = candidate.XUnits + candidate.WidthUnits / 2;
            var candidateY = candidate.Row + VerticalOffset(candidate.VerticalSlot);
            var deltaX = candidateX - currentCenterX;
            var deltaY = candidateY - currentCenterY;
            var isCandidate = direction switch
            {
                NavigationDirection.Left => deltaX < -.01 && Math.Abs(deltaY) < .51,
                NavigationDirection.Right => deltaX > .01 && Math.Abs(deltaY) < .51,
                NavigationDirection.Up => deltaY < -.01,
                NavigationDirection.Down => deltaY > .01,
                _ => false,
            };
            if (!isCandidate)
            {
                continue;
            }

            var score = direction is NavigationDirection.Left or NavigationDirection.Right
                ? Math.Abs(deltaX) + Math.Abs(deltaY) * 8
                : Math.Abs(deltaY) * 8 + Math.Abs(deltaX);
            if (score < bestScore)
            {
                bestScore = score;
                target = candidate;
            }
        }

        if (target?.KeyId is { } key)
        {
            SelectKey(key);
        }
    }

    private void SelectKey(PhysicalKeyId key)
    {
        SelectedKey = key;
        InvalidateVisual();
        var peer = UIElementAutomationPeer.FromElement(this);
        peer?.RaiseAutomationEvent(AutomationEvents.AutomationFocusChanged);
    }

    private void PressSelectedKey()
    {
        if (!SelectedKey.IsValid)
        {
            return;
        }

        _pressedKey = SelectedKey;
        InvalidateVisual();
        KeyPressed?.Invoke(this, new KeyboardCanvasKeyEventArgs(SelectedKey));
    }

    private void InvokeKey(PhysicalKeyId key)
    {
        Focus();
        SelectKey(key);
        if (IsInteractive && Mode == KeyboardCanvasMode.Editor)
        {
            KeyPressed?.Invoke(this, new KeyboardCanvasKeyEventArgs(key));
            KeyReleased?.Invoke(this, new KeyboardCanvasKeyEventArgs(key));
        }
    }

    private static double VerticalOffset(KeyboardVisualVerticalSlot slot) => slot switch
    {
        KeyboardVisualVerticalSlot.UpperHalf => .25,
        KeyboardVisualVerticalSlot.LowerHalf => .75,
        _ => .5,
    };

    private long CountFor(PhysicalKeyId keyId) =>
        KeyCounts?.TryGetValue(keyId, out var count) == true ? count : 0;

    private static string CompactCount(long count)
    {
        if (count >= 100_000_000)
        {
            return $"{count / 100_000_000d:0.#}亿";
        }

        return count >= 10_000
            ? $"{count / 10_000d:0.#}万"
            : count.ToString("N0", CultureInfo.CurrentCulture);
    }

    private static Color RowColor(KeyboardRowId row) => row switch
    {
        KeyboardRowId.R0 => Color.FromRgb(242, 171, 51),
        KeyboardRowId.R1 => Color.FromRgb(64, 184, 209),
        KeyboardRowId.R2 => Color.FromRgb(145, 201, 43),
        KeyboardRowId.R3 => Color.FromRgb(153, 128, 235),
        _ => Color.FromRgb(150, 158, 151),
    };

    private enum NavigationDirection
    {
        None,
        Left,
        Right,
        Up,
        Down,
    }

    private sealed class KeyboardCanvasAutomationPeer(KeyboardCanvas owner)
        : FrameworkElementAutomationPeer(owner)
    {
        private KeyboardCanvas Canvas => (KeyboardCanvas)Owner;

        protected override string GetClassNameCore() => nameof(KeyboardCanvas);

        protected override AutomationControlType GetAutomationControlTypeCore() =>
            AutomationControlType.Pane;

        protected override List<AutomationPeer> GetChildrenCore() =>
            WindowsAnsiVisualLayoutCatalog.CompactAnsi.Placements
                .Where(placement => placement.KeyId.HasValue)
                .Select(placement => placement.KeyId!.Value)
                .Distinct()
                .Select(key => (AutomationPeer)new KeyboardKeyAutomationPeer(Canvas, key))
                .ToList();
    }

    private sealed class KeyboardKeyAutomationPeer(
        KeyboardCanvas canvas,
        PhysicalKeyId key) : AutomationPeer, IInvokeProvider
    {
        protected override string GetAcceleratorKeyCore() => string.Empty;

        protected override string GetAccessKeyCore() => string.Empty;

        protected override string GetAutomationIdCore() => $"keyboard.key.{key.Value}";

        protected override string GetClassNameCore() => "KeyboardKey";

        protected override AutomationControlType GetAutomationControlTypeCore() =>
            AutomationControlType.Button;

        protected override string GetNameCore() => WindowsKeyDisplayCatalog.LabelFor(key);

        protected override string GetHelpTextCore() => canvas.Mode == KeyboardCanvasMode.Statistics
            ? $"{GetNameCore()}，{canvas.CountFor(key).ToString("N0", CultureInfo.CurrentCulture)} 次"
            : $"{GetNameCore()}，按下可选择并试听";

        protected override string GetItemStatusCore() => canvas.Mode == KeyboardCanvasMode.Statistics
            ? $"{canvas.CountFor(key).ToString("N0", CultureInfo.CurrentCulture)} 次"
            : canvas.SelectedKey == key ? "已选择" : string.Empty;

        protected override string GetItemTypeCore() => "键盘按键";

        protected override AutomationPeer? GetLabeledByCore() => null;

        protected override List<AutomationPeer>? GetChildrenCore() => null;

        protected override bool IsControlElementCore() => true;

        protected override bool IsContentElementCore() => true;

        protected override bool IsEnabledCore() => canvas.IsEnabled;

        protected override bool IsKeyboardFocusableCore() => true;

        protected override bool HasKeyboardFocusCore() =>
            canvas.IsKeyboardFocusWithin && canvas.SelectedKey == key;

        protected override bool IsOffscreenCore() => !canvas.IsVisible;

        protected override bool IsPasswordCore() => false;

        protected override bool IsRequiredForFormCore() => false;

        protected override AutomationOrientation GetOrientationCore() => AutomationOrientation.None;

        protected override Rect GetBoundingRectangleCore()
        {
            var target = canvas._hitTargets.FirstOrDefault(item => item.Key == key);
            if (target.Bounds.IsEmpty || !canvas.IsVisible)
            {
                return Rect.Empty;
            }

            var topLeft = canvas.PointToScreen(target.Bounds.TopLeft);
            var bottomRight = canvas.PointToScreen(target.Bounds.BottomRight);
            return new Rect(topLeft, bottomRight);
        }

        protected override Point GetClickablePointCore()
        {
            var bounds = GetBoundingRectangleCore();
            return bounds.IsEmpty
                ? new Point(double.NaN, double.NaN)
                : new Point(bounds.Left + bounds.Width / 2, bounds.Top + bounds.Height / 2);
        }

        protected override void SetFocusCore()
        {
            canvas.Focus();
            canvas.SelectKey(key);
        }

        public override object? GetPattern(PatternInterface patternInterface) =>
            patternInterface == PatternInterface.Invoke ? this : null;

        public void Invoke()
        {
            if (!canvas.IsEnabled)
            {
                throw new ElementNotEnabledException();
            }

            _ = canvas.Dispatcher.BeginInvoke(() => canvas.InvokeKey(key));
        }
    }
}
