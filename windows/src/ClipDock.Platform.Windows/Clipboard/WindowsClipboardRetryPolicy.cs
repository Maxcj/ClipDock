using ClipDock.Core.Interfaces;

namespace ClipDock.Platform.Windows.Clipboard;

public sealed class WindowsClipboardRetryPolicy : IClipboardRetryPolicy
{
    private static readonly TimeSpan[] Delays =
    [
        TimeSpan.Zero,
        TimeSpan.FromMilliseconds(20),
        TimeSpan.FromMilliseconds(50),
        TimeSpan.FromMilliseconds(100),
        TimeSpan.FromMilliseconds(200)
    ];

    public async Task<T?> ExecuteAsync<T>(Func<T> action, CancellationToken cancellationToken)
    {
        Exception? lastError = null;

        foreach (var delay in Delays)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (delay > TimeSpan.Zero)
            {
                await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
            }

            try
            {
                return action();
            }
            catch (ExternalException ex)
            {
                lastError = ex;
            }
            catch (InvalidOperationException ex)
            {
                lastError = ex;
            }
        }

        throw lastError ?? new InvalidOperationException("Clipboard read failed.");
    }
}
