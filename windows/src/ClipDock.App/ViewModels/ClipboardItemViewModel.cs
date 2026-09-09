using ClipDock.Core.Models;

namespace ClipDock.App.ViewModels;

public sealed class ClipboardItemViewModel
{
    public ClipboardItem Model { get; }
    public string Title => Model.TextContent?.ReplaceLineEndings(" ") ?? Model.PayloadType.ToString();
    public string Subtitle => $"{Model.SemanticType} - {Model.LastUsedAt.LocalDateTime:g} - Used {Model.UsageCount}";

    public ClipboardItemViewModel(ClipboardItem model)
    {
        Model = model;
    }
}
