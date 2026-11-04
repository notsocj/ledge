namespace Ledge;

/// <summary>Keeps the display (and so the PC) awake, like PowerToys Awake or the Mac's caffeinate -d.</summary>
public sealed class KeepAwake
{
    const uint ES_CONTINUOUS = 0x80000000, ES_SYSTEM_REQUIRED = 0x1, ES_DISPLAY_REQUIRED = 0x2;

    public bool IsOn { get; private set; }

    /// <summary>Call from the UI thread: the request lasts as long as the thread that made it.</summary>
    public void Toggle()
    {
        IsOn = !IsOn;
        Native.SetThreadExecutionState(IsOn ? ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);
    }
}
