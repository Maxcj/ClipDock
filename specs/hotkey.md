# Hotkey

Windows MVP default hotkey is `Ctrl+Shift+V`.

Hotkey behavior:

- The hotkey opens or focuses the clipboard window.
- Registration is owned by the platform layer.
- ViewModels do not call Win32 APIs directly.
- Future settings must allow the user to customize the shortcut.
