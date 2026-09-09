using ClipDock.Core.Models;

namespace ClipDock.Core.Interfaces;

public interface IClipboardWriter
{
    Task WriteAsync(ClipboardItem item, CancellationToken cancellationToken);
}
