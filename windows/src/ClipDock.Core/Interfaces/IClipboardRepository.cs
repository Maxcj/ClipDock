using ClipDock.Core.Models;

namespace ClipDock.Core.Interfaces;

public interface IClipboardRepository
{
    Task<ClipboardItem> UpsertAsync(ClipboardItem item, CancellationToken cancellationToken);

    Task<IReadOnlyList<ClipboardItem>> SearchAsync(string query, CancellationToken cancellationToken);

    Task<IReadOnlyList<ClipboardItem>> GetRecentAsync(int limit, CancellationToken cancellationToken);
}
