namespace ClipDock.Core.Interfaces;

public interface IClipboardMonitor
{
    event EventHandler? ClipboardChanged;

    void Start();

    void Stop();
}
