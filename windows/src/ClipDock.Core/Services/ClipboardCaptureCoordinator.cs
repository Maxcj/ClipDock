using System.Threading.Channels;
using ClipDock.Core.Interfaces;
using ClipDock.Core.Models;

namespace ClipDock.Core.Services;

public sealed class ClipboardCaptureCoordinator : IAsyncDisposable
{
    private readonly IClipboardMonitor _monitor;
    private readonly IClipboardSnapshotReader _reader;
    private readonly IClipboardRepository _repository;
    private readonly ContentHashService _hashService;
    private readonly ClipboardClassifier _classifier;
    private readonly Channel<bool> _queue = Channel.CreateBounded<bool>(new BoundedChannelOptions(1)
    {
        FullMode = BoundedChannelFullMode.DropOldest,
        SingleReader = true,
        SingleWriter = false
    });
    private readonly CancellationTokenSource _stop = new();
    private Task? _worker;

    public ClipboardCaptureCoordinator(
        IClipboardMonitor monitor,
        IClipboardSnapshotReader reader,
        IClipboardRepository repository,
        ContentHashService hashService,
        ClipboardClassifier classifier)
    {
        _monitor = monitor;
        _reader = reader;
        _repository = repository;
        _hashService = hashService;
        _classifier = classifier;
    }

    public void Start()
    {
        _monitor.ClipboardChanged += OnClipboardChanged;
        _worker = Task.Run(ProcessQueueAsync);
        _monitor.Start();
    }

    public async ValueTask DisposeAsync()
    {
        _monitor.ClipboardChanged -= OnClipboardChanged;
        _monitor.Stop();
        _stop.Cancel();
        _queue.Writer.TryComplete();

        if (_worker is not null)
        {
            await _worker.ConfigureAwait(false);
        }

        _stop.Dispose();
    }

    private void OnClipboardChanged(object? sender, EventArgs e)
    {
        _queue.Writer.TryWrite(true);
    }

    private async Task ProcessQueueAsync()
    {
        await foreach (var _ in _queue.Reader.ReadAllAsync(_stop.Token).ConfigureAwait(false))
        {
            var snapshot = await _reader.ReadAsync(_stop.Token).ConfigureAwait(false);
            if (snapshot is null || IsEmpty(snapshot))
            {
                continue;
            }

            var now = DateTimeOffset.UtcNow;
            var item = new ClipboardItem
            {
                PayloadType = snapshot.PayloadType,
                SemanticType = _classifier.Classify(snapshot),
                ContentHash = _hashService.Compute(snapshot),
                TextContent = snapshot.PayloadType is ClipboardPayloadType.Text or ClipboardPayloadType.Html
                    ? snapshot.Text ?? snapshot.Html
                    : null,
                CreatedAt = now,
                LastUsedAt = now,
                UsageCount = 1
            };

            await _repository.UpsertAsync(item, _stop.Token).ConfigureAwait(false);
        }
    }

    private static bool IsEmpty(ClipboardSnapshot snapshot)
    {
        return string.IsNullOrEmpty(snapshot.Text)
            && string.IsNullOrEmpty(snapshot.Html)
            && (snapshot.ImageData is null || snapshot.ImageData.Length == 0)
            && (snapshot.FilePaths is null || snapshot.FilePaths.Count == 0);
    }
}
