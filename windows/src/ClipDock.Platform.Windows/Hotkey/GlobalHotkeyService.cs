namespace ClipDock.Platform.Windows.Hotkey;

public sealed class GlobalHotkeyService : NativeWindow, IGlobalHotkeyService, IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private int _nextId = 1;
    private readonly Dictionary<int, Action> _callbacks = [];

    public GlobalHotkeyService()
    {
        CreateHandle(new CreateParams());
    }

    public void Register(Hotkey hotkey, Action callback)
    {
        var id = _nextId++;
        if (!Native.NativeMethods.RegisterHotKey(Handle, id, (uint)hotkey.Modifiers, hotkey.VirtualKey))
        {
            throw new InvalidOperationException("Failed to register global hotkey.");
        }

        _callbacks[id] = callback;
    }

    public void UnregisterAll()
    {
        foreach (var id in _callbacks.Keys.ToArray())
        {
            Native.NativeMethods.UnregisterHotKey(Handle, id);
        }

        _callbacks.Clear();
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && _callbacks.TryGetValue(m.WParam.ToInt32(), out var callback))
        {
            callback();
        }

        base.WndProc(ref m);
    }

    public void Dispose()
    {
        UnregisterAll();
        DestroyHandle();
    }
}
