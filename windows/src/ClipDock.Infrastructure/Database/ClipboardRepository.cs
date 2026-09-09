using ClipDock.Core.Interfaces;
using ClipDock.Core.Models;
using Microsoft.EntityFrameworkCore;

namespace ClipDock.Infrastructure.Database;

public sealed class ClipboardRepository : IClipboardRepository
{
    private readonly ClipDockDbContext _db;

    public ClipboardRepository(ClipDockDbContext db)
    {
        _db = db;
    }

    public async Task<ClipboardItem> UpsertAsync(ClipboardItem item, CancellationToken cancellationToken)
    {
        var existing = await _db.ClipboardItems
            .FirstOrDefaultAsync(x => x.PayloadType == item.PayloadType && x.ContentHash == item.ContentHash, cancellationToken)
            .ConfigureAwait(false);

        if (existing is not null)
        {
            existing.LastUsedAt = item.LastUsedAt;
            existing.UsageCount += 1;
            await _db.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
            return existing;
        }

        _db.ClipboardItems.Add(item);
        await _db.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
        return item;
    }

    public async Task<IReadOnlyList<ClipboardItem>> SearchAsync(string query, CancellationToken cancellationToken)
    {
        var trimmed = query.Trim();
        var items = _db.ClipboardItems.AsNoTracking();

        if (!string.IsNullOrEmpty(trimmed))
        {
            items = items.Where(x => x.TextContent != null && x.TextContent.Contains(trimmed));
        }

        return await items
            .OrderByDescending(x => x.IsPinned)
            .ThenByDescending(x => x.LastUsedAt)
            .Take(200)
            .ToListAsync(cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<ClipboardItem>> GetRecentAsync(int limit, CancellationToken cancellationToken)
    {
        return await _db.ClipboardItems
            .AsNoTracking()
            .OrderByDescending(x => x.IsPinned)
            .ThenByDescending(x => x.LastUsedAt)
            .Take(limit)
            .ToListAsync(cancellationToken)
            .ConfigureAwait(false);
    }
}
