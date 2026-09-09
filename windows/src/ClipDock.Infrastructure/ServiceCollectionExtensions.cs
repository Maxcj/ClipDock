using ClipDock.Core.Interfaces;
using ClipDock.Infrastructure.Database;
using ClipDock.Infrastructure.Settings;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace ClipDock.Infrastructure;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddClipDockInfrastructure(this IServiceCollection services)
    {
        services.AddSingleton<ClipDockPaths>();
        services.AddDbContext<ClipDockDbContext>((provider, options) =>
        {
            var paths = provider.GetRequiredService<ClipDockPaths>();
            paths.EnsureCreated();
            options.UseSqlite($"Data Source={paths.DatabasePath}");
        });
        services.AddScoped<IClipboardRepository, ClipboardRepository>();
        return services;
    }
}
