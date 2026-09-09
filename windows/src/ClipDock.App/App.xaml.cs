using ClipDock.Core.Services;
using ClipDock.Infrastructure;
using ClipDock.Infrastructure.Database;
using ClipDock.Platform.Windows;
using ClipDock.Platform.Windows.Hotkey;
using ClipDock.Platform.Windows.Tray;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.UI.Xaml;
using Serilog;

namespace ClipDock.App;

public partial class App : Application
{
    private IHost? _host;
    private MainWindow? _mainWindow;
    private TrayIconService? _tray;

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        _host = Host.CreateDefaultBuilder()
            .UseSerilog((context, services, configuration) => configuration
                .WriteTo.File(
                    Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "ClipDock",
                        "Logs",
                        "clipdock-.log"),
                    rollingInterval: RollingInterval.Day))
            .ConfigureServices(services =>
            {
                services.AddClipDockInfrastructure();
                services.AddClipDockWindowsPlatform();
                services.AddSingleton<ContentHashService>();
                services.AddSingleton<ClipboardClassifier>();
                services.AddSingleton<ClipboardCaptureCoordinator>();
                services.AddTransient<ClipboardViewModel>();
                services.AddTransient<MainWindow>();
            })
            .Build();

        await _host.StartAsync().ConfigureAwait(false);

        using (var scope = _host.Services.CreateScope())
        {
            await scope.ServiceProvider.GetRequiredService<ClipDockDbContext>().Database.EnsureCreatedAsync();
        }

        _mainWindow = _host.Services.GetRequiredService<MainWindow>();
        _mainWindow.Activate();

        _host.Services.GetRequiredService<ClipboardCaptureCoordinator>().Start();
        RegisterDefaultHotkey();
        _tray = new TrayIconService(ShowMainWindow, ShowMainWindow, Exit);
    }

    private void RegisterDefaultHotkey()
    {
        var hotkeys = _host!.Services.GetRequiredService<IGlobalHotkeyService>();
        hotkeys.Register(new Hotkey(HotkeyModifiers.Control | HotkeyModifiers.Shift, (uint)System.Windows.Forms.Keys.V), ShowMainWindow);
    }

    private void ShowMainWindow()
    {
        _mainWindow ??= _host!.Services.GetRequiredService<MainWindow>();
        _mainWindow.Activate();
    }

    private async void Exit()
    {
        _tray?.Dispose();
        if (_host is not null)
        {
            await _host.StopAsync();
            _host.Dispose();
        }

        Current.Exit();
    }
}
