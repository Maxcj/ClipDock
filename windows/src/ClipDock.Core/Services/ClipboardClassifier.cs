using System.Text.RegularExpressions;
using ClipDock.Core.Models;

namespace ClipDock.Core.Services;

public sealed partial class ClipboardClassifier
{
    public ClipboardSemanticType Classify(ClipboardSnapshot snapshot)
    {
        if (snapshot.PayloadType != ClipboardPayloadType.Text || string.IsNullOrWhiteSpace(snapshot.Text))
        {
            return ClipboardSemanticType.Unknown;
        }

        var text = snapshot.Text.Trim();
        if (Uri.TryCreate(text, UriKind.Absolute, out var uri) &&
            (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps))
        {
            return ClipboardSemanticType.Link;
        }

        if (ColorRegex().IsMatch(text))
        {
            return ClipboardSemanticType.Color;
        }

        if (LooksLikeCode(text))
        {
            return ClipboardSemanticType.Code;
        }

        return ClipboardSemanticType.PlainText;
    }

    private static bool LooksLikeCode(string text)
    {
        return text.Contains("function ", StringComparison.Ordinal)
            || text.Contains("class ", StringComparison.Ordinal)
            || text.Contains("=>", StringComparison.Ordinal)
            || text.Contains("{", StringComparison.Ordinal) && text.Contains("}", StringComparison.Ordinal)
            || text.Contains("import ", StringComparison.Ordinal)
            || text.Contains("#include", StringComparison.Ordinal);
    }

    [GeneratedRegex("^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")]
    private static partial Regex ColorRegex();
}
