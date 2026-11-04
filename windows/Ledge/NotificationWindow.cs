using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace Ledge;

/// <summary>A separate layered window lets the visible capsule pass native mouse input through to
/// other apps, while the island remains interactive. WPF's IsHitTestVisible alone cannot do that.</summary>
sealed class NotificationWindow : Window
{
    const double Padding = 32, CapsuleTop = 50;
    readonly Window island;
    readonly NotificationCapsule capsule = new()
    {
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Top,
        Margin = new Thickness(Padding),
    };
    Native.RECT work;
    double scale = 1;
    bool placed, closed;

    public NotificationWindow(Window island)
    {
        this.island = island;
        Title = "Ledge notification";
        Width = 364 + 2 * Padding;
        Height = 64 + 2 * Padding;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        Content = new Grid { Children = { capsule } };
        capsule.Dismissed += () => { if (!closed && IsVisible) Hide(); };
        SourceInitialized += (_, _) =>
        {
            var style = Native.GetWindowLongPtr(Handle, Native.GWL_EXSTYLE);
            Native.SetWindowLongPtr(Handle, Native.GWL_EXSTYLE,
                style | Native.WS_EX_TRANSPARENT | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
            PlaceCurrent();
        };
        DpiChanged += (_, _) => PlaceCurrent();
        Closed += (_, _) => closed = true;
    }

    nint Handle => new WindowInteropHelper(this).Handle;

    public void Present(NotificationContent content)
    {
        if (closed || !island.IsVisible) return;
        // The owner has been shown by now. Ownership keeps the overlay above the island and closes
        // it with the app, without activating either window or creating another taskbar entry.
        Owner ??= island;
        capsule.Show(content);
        if (!IsVisible) Show();
    }

    public void Dismiss()
    {
        if (!closed) capsule.Dismiss();
    }

    /// <summary>Fullscreen apps must never reveal an expired alert when Ledge returns.</summary>
    public void Suppress()
    {
        if (closed) return;
        capsule.Clear();
        if (IsVisible) Hide();
    }

    public void CloseOverlay()
    {
        // WPF may already have closed this owned window while closing the main island.
        if (!closed) Close();
    }

    public void Place(Native.RECT work, double scale)
    {
        this.work = work;
        this.scale = scale;
        placed = true;
        if (IsSourceInitialized) PlaceCurrent();
    }

    void PlaceCurrent()
    {
        if (closed || !placed) return;
        var pixelWidth = (int)Math.Round(Width * scale);
        var pixelHeight = (int)Math.Round(Height * scale);
        var left = work.Left + (work.Right - work.Left - pixelWidth) / 2;
        var top = work.Top + (int)Math.Round((CapsuleTop - Padding) * scale);
        Native.SetWindowPos(Handle, Native.HWND_TOPMOST, left, top, pixelWidth, pixelHeight, Native.SWP_NOACTIVATE);
    }
}
