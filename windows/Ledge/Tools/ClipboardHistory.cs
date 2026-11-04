using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Ledge;

/// <summary>The last 20 things you copied as text, kept in memory only. Copies that password managers
/// mark as private (the formats Windows' own clipboard history respects) are never remembered.</summary>
public sealed class ClipboardHistory
{
    const int Limit = 20, MaxLength = 10_000, WM_CLIPBOARDUPDATE = 0x031D;

    readonly List<string> items = [];
    string? ownCopy;

    public IReadOnlyList<string> Items => items;
    /// <summary>Off, it remembers nothing and forgets what it had.</summary>
    public bool Enabled { get; set; } = true;
    public event Action? Changed;

    /// <summary>Asks Windows to tell this window whenever the clipboard changes.</summary>
    public void Listen(nint window)
    {
        Native.AddClipboardFormatListener(window);
        HwndSource.FromHwnd(window).AddHook((nint hwnd, int message, nint wParam, nint lParam, ref bool handled) =>
        {
            if (message == WM_CLIPBOARDUPDATE) Read();
            return 0;
        });
    }

    public void Remember(string text)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Length > MaxLength) return;
        items.Remove(text);
        items.Insert(0, text);
        if (items.Count > Limit) items.RemoveAt(Limit);
        Changed?.Invoke();
    }

    /// <summary>Puts an older copy back on the clipboard, and at the top of the list.</summary>
    public void Copy(string text)
    {
        ownCopy = text;
        try
        {
            Clipboard.SetText(text);
        }
        catch (COMException)
        {
            ownCopy = null; // another app has the clipboard open; nothing changed
            return;
        }
        Remember(text);
    }

    public void Clear()
    {
        items.Clear();
        Changed?.Invoke();
    }

    void Read()
    {
        if (!Enabled)
        {
            if (items.Count > 0) Clear();
            return;
        }
        try
        {
            if (!Clipboard.ContainsText() || IsPrivate()) return;
            var text = Clipboard.GetText();
            if (text == ownCopy)
            {
                ownCopy = null;
                return;
            }
            Remember(text);
        }
        catch (COMException)
        {
            // Another app still has the clipboard open; its next change comes through.
        }
    }

    /// <summary>The flags password managers set so clipboard tools and Windows' history leave a copy alone.</summary>
    static bool IsPrivate()
    {
        if (Clipboard.ContainsData("ExcludeClipboardContentFromMonitorProcessing") || Clipboard.ContainsData("Clipboard Viewer Ignore")) return true;
        return Clipboard.GetData("CanIncludeInClipboardHistory") is MemoryStream flag && flag.Length >= 4 && new BinaryReader(flag).ReadInt32() == 0;
    }
}
