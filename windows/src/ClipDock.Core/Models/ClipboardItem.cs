namespace ClipDock.Core.Models;

public sealed class ClipboardItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ClipboardPayloadType PayloadType { get; set; }
    public ClipboardSemanticType SemanticType { get; set; }
    public string ContentHash { get; set; } = string.Empty;
    public string? TextContent { get; set; }
    public string? AssetPath { get; set; }
    public string? SourceApplication { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset LastUsedAt { get; set; }
    public int UsageCount { get; set; } = 1;
    public bool IsPinned { get; set; }
}
