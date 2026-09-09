using ClipDock.Core.Models;
using Microsoft.EntityFrameworkCore;

namespace ClipDock.Infrastructure.Database;

public sealed class ClipDockDbContext : DbContext
{
    public ClipDockDbContext(DbContextOptions<ClipDockDbContext> options)
        : base(options)
    {
    }

    public DbSet<ClipboardItem> ClipboardItems => Set<ClipboardItem>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var item = modelBuilder.Entity<ClipboardItem>();
        item.ToTable("clipboard_items");
        item.HasKey(x => x.Id);
        item.Property(x => x.Id).HasColumnName("id").HasConversion<string>();
        item.Property(x => x.PayloadType).HasColumnName("payload_type").HasConversion<int>();
        item.Property(x => x.SemanticType).HasColumnName("semantic_type").HasConversion<int>();
        item.Property(x => x.ContentHash).HasColumnName("content_hash").IsRequired();
        item.Property(x => x.TextContent).HasColumnName("text_content");
        item.Property(x => x.AssetPath).HasColumnName("asset_path");
        item.Property(x => x.SourceApplication).HasColumnName("source_application");
        item.Property(x => x.CreatedAt).HasColumnName("created_at");
        item.Property(x => x.LastUsedAt).HasColumnName("last_used_at");
        item.Property(x => x.UsageCount).HasColumnName("usage_count").HasDefaultValue(1);
        item.Property(x => x.IsPinned).HasColumnName("is_pinned").HasDefaultValue(false);
        item.HasIndex(x => x.ContentHash).HasDatabaseName("idx_clipboard_hash");
        item.HasIndex(x => x.LastUsedAt).HasDatabaseName("idx_clipboard_last_used").IsDescending();
        item.HasIndex(x => x.IsPinned).HasDatabaseName("idx_clipboard_pinned");
        item.HasIndex(x => new { x.PayloadType, x.ContentHash }).IsUnique();
    }
}
