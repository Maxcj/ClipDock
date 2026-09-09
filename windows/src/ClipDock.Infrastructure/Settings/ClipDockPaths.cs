namespace ClipDock.Infrastructure.Settings;

public sealed class ClipDockPaths
{
    public string RootDirectory { get; }
    public string DataDirectory => Path.Combine(RootDirectory, "Data");
    public string DatabasePath => Path.Combine(DataDirectory, "clipdock.db");
    public string AssetsDirectory => Path.Combine(RootDirectory, "Assets");
    public string LogsDirectory => Path.Combine(RootDirectory, "Logs");

    public ClipDockPaths()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        RootDirectory = Path.Combine(localAppData, "ClipDock");
    }

    public void EnsureCreated()
    {
        Directory.CreateDirectory(DataDirectory);
        Directory.CreateDirectory(Path.Combine(AssetsDirectory, "Images"));
        Directory.CreateDirectory(Path.Combine(AssetsDirectory, "Files"));
        Directory.CreateDirectory(LogsDirectory);
    }
}
