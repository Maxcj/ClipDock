namespace ClipDock.Core.Models;

public sealed record ClipboardSnapshot(
    ClipboardPayloadType PayloadType,
    string? Text,
    byte[]? ImageData,
    IReadOnlyList<string>? FilePaths,
    string? Html);
