using ClipDock.Core.Interfaces;
using ClipDock.Platform.Windows.Clipboard;
using ClipDock.Platform.Windows.Hotkey;
using Microsoft.Extensions.DependencyInjection;

namespace ClipDock.Platform.Windows;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddClipDockWindowsPlatform(this IServiceCollection services)
    {
        services.AddSingleton<IClipboardRetryPolicy, WindowsClipboardRetryPolicy>();
        services.AddSingleton<IClipboardMonitor, WindowsClipboardMonitor>();
        services.AddSingleton<IClipboardSnapshotReader, WindowsClipboardSnapshotReader>();
        services.AddSingleton<IClipboardWriter, WindowsClipboardWriter>();
        services.AddSingleton<IGlobalHotkeyService, GlobalHotkeyService>();
        return services;
    }
}
