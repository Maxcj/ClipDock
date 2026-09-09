using System.Security.Cryptography;
using System.Text;
using ClipDock.Core.Models;

namespace ClipDock.Core.Services;

public sealed class ContentHashService
{
    public string Compute(ClipboardSnapshot snapshot)
    {
        var bytes = snapshot.PayloadType switch
        {
            ClipboardPayloadType.Text => Encoding.UTF8.GetBytes(snapshot.Text ?? string.Empty),
            ClipboardPayloadType.Html => Encoding.UTF8.GetBytes(snapshot.Html ?? snapshot.Text ?? string.Empty),
            ClipboardPayloadType.Image => snapshot.ImageData ?? Array.Empty<byte>(),
            ClipboardPayloadType.File => Encoding.UTF8.GetBytes(string.Join('\n', snapshot.FilePaths ?? Array.Empty<string>())),
            _ => Array.Empty<byte>()
        };

        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }
}
