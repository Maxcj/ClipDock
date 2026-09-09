namespace ClipDock.Platform.Windows.Hotkey;

public interface IGlobalHotkeyService
{
    void Register(Hotkey hotkey, Action callback);

    void UnregisterAll();
}
