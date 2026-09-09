using ClipDock.Core.Models;
using ClipDock.Core.Services;
using Xunit;

namespace ClipDock.Tests;

public sealed class ClipboardClassifierTests
{
    private readonly ClipboardClassifier _classifier = new();

    [Fact]
    public void Classify_ReturnsLink_ForHttpUrl()
    {
        var snapshot = new ClipboardSnapshot(ClipboardPayloadType.Text, "https://github.com", null, null, null);

        Assert.Equal(ClipboardSemanticType.Link, _classifier.Classify(snapshot));
    }

    [Fact]
    public void Classify_ReturnsColor_ForHexColor()
    {
        var snapshot = new ClipboardSnapshot(ClipboardPayloadType.Text, "#ff8800", null, null, null);

        Assert.Equal(ClipboardSemanticType.Color, _classifier.Classify(snapshot));
    }

    [Fact]
    public void Classify_ReturnsPlainText_ForOrdinaryText()
    {
        var snapshot = new ClipboardSnapshot(ClipboardPayloadType.Text, "hello from ClipDock", null, null, null);

        Assert.Equal(ClipboardSemanticType.PlainText, _classifier.Classify(snapshot));
    }
}
