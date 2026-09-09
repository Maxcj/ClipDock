using ClipDock.Core.Models;
using ClipDock.Core.Services;
using Xunit;

namespace ClipDock.Tests;

public sealed class ContentHashServiceTests
{
    private readonly ContentHashService _hashService = new();

    [Fact]
    public void Compute_ReturnsStableSha256_ForSameText()
    {
        var first = new ClipboardSnapshot(ClipboardPayloadType.Text, "Hello", null, null, null);
        var second = new ClipboardSnapshot(ClipboardPayloadType.Text, "Hello", null, null, null);

        Assert.Equal(_hashService.Compute(first), _hashService.Compute(second));
    }

    [Fact]
    public void Compute_ReturnsDifferentHashes_ForDifferentText()
    {
        var first = new ClipboardSnapshot(ClipboardPayloadType.Text, "Hello", null, null, null);
        var second = new ClipboardSnapshot(ClipboardPayloadType.Text, "World", null, null, null);

        Assert.NotEqual(_hashService.Compute(first), _hashService.Compute(second));
    }
}
