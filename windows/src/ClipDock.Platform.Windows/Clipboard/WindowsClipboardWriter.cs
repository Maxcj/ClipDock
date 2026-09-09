using ClipDock.Core.Interfaces;
using ClipDock.Core.Models;

namespace ClipDock.Platform.Windows.Clipboard;

public sealed class WindowsClipboardWriter : IClipboardWriter
{
    private readonly IClipboardRetryPolicy _retryPolicy;

    public WindowsClipboardWriter(IClipboardRetryPolicy retryPolicy)
    {
        _retryPolicy = retryPolicy;
    }

    public async Task WriteAsync(ClipboardItem item, CancellationToken cancellationToken)
    {
        if (item.PayloadType != ClipboardPayloadType.Text || string.IsNullOrEmpty(item.TextContent))
        {
            return;
        }

        await _retryPolicy.ExecuteAsync<object>(() =>
        {
            StaClipboard.Invoke(() => System.Windows.Forms.Clipboard.SetText(item.TextContent));
            return new object();
        }, cancellationToken).ConfigureAwait(false);
    }
}
