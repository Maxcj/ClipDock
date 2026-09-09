using ClipDock.Core.Models;

namespace ClipDock.Core.Interfaces;

public interface IClipboardSnapshotReader
{
    Task<ClipboardSnapshot?> ReadAsync(CancellationToken cancellationToken);
}
