namespace ClipDock.Platform.Windows.Hotkey;

[Flags]
public enum HotkeyModifiers
{
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Windows = 0x0008
}

public sealed record Hotkey(HotkeyModifiers Modifiers, uint VirtualKey);
