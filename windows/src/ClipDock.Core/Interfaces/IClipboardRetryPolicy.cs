namespace ClipDock.Core.Interfaces;

public interface IClipboardRetryPolicy
{
    Task<T?> ExecuteAsync<T>(Func<T> action, CancellationToken cancellationToken);
}
