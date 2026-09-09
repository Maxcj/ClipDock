using ClipDock.Core.Interfaces;
using ClipDock.Core.Models;

namespace ClipDock.Platform.Windows.Clipboard;

public sealed class WindowsClipboardSnapshotReader : IClipboardSnapshotReader
{
    private readonly IClipboardRetryPolicy _retryPolicy;

    public WindowsClipboardSnapshotReader(IClipboardRetryPolicy retryPolicy)
    {
        _retryPolicy = retryPolicy;
    }

    public Task<ClipboardSnapshot?> ReadAsync(CancellationToken cancellationToken)
    {
        return _retryPolicy.ExecuteAsync(() => StaClipboard.Invoke(ReadSnapshot), cancellationToken);
    }

    private static ClipboardSnapshot? ReadSnapshot()
    {
        if (System.Windows.Forms.Clipboard.ContainsText(TextDataFormat.Html))
        {
            var html = System.Windows.Forms.Clipboard.GetText(TextDataFormat.Html);
            return new ClipboardSnapshot(ClipboardPayloadType.Html, StripHtmlClipboardHeader(html), null, null, html);
        }

        if (System.Windows.Forms.Clipboard.ContainsText())
        {
            var text = System.Windows.Forms.Clipboard.GetText();
            return new ClipboardSnapshot(ClipboardPayloadType.Text, text, null, null, null);
        }

        if (System.Windows.Forms.Clipboard.ContainsFileDropList())
        {
            var files = System.Windows.Forms.Clipboard.GetFileDropList().Cast<string>().ToArray();
            return new ClipboardSnapshot(ClipboardPayloadType.File, null, null, files, null);
        }

        if (System.Windows.Forms.Clipboard.ContainsImage())
        {
            using var image = System.Windows.Forms.Clipboard.GetImage();
            if (image is null)
            {
                return null;
            }

            using var stream = new MemoryStream();
            image.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
            return new ClipboardSnapshot(ClipboardPayloadType.Image, null, stream.ToArray(), null, null);
        }

        return null;
    }

    private static string StripHtmlClipboardHeader(string html)
    {
        var fragmentStart = html.IndexOf("<!--StartFragment-->", StringComparison.OrdinalIgnoreCase);
        var fragmentEnd = html.IndexOf("<!--EndFragment-->", StringComparison.OrdinalIgnoreCase);
        if (fragmentStart < 0 || fragmentEnd <= fragmentStart)
        {
            return html;
        }

        fragmentStart += "<!--StartFragment-->".Length;
        return html[fragmentStart..fragmentEnd];
    }
}
