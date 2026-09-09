using ClipDock.Core.Interfaces;

namespace ClipDock.Platform.Windows.Clipboard;

public sealed class WindowsClipboardMonitor : NativeWindow, IClipboardMonitor
{
    private const int WM_CLIPBOARDUPDATE = 0x031D;
    private bool _isStarted;

    public event EventHandler? ClipboardChanged;

    public void Start()
    {
        if (_isStarted)
        {
            return;
        }

        CreateHandle(new CreateParams());
        if (!NativeMethods.AddClipboardFormatListener(Handle))
        {
            throw new InvalidOperationException("Failed to register clipboard listener.");
        }

        _isStarted = true;
    }

    public void Stop()
    {
        if (!_isStarted)
        {
            return;
        }

        NativeMethods.RemoveClipboardFormatListener(Handle);
        DestroyHandle();
        _isStarted = false;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_CLIPBOARDUPDATE)
        {
            ClipboardChanged?.Invoke(this, EventArgs.Empty);
        }

        base.WndProc(ref m);
    }
}
