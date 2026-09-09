namespace ClipDock.Platform.Windows.Clipboard;

internal static class StaClipboard
{
    public static T Invoke<T>(Func<T> action)
    {
        T? result = default;
        Exception? error = null;

        var thread = new Thread(() =>
        {
            try
            {
                result = action();
            }
            catch (Exception ex)
            {
                error = ex;
            }
        });

        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();

        if (error is not null)
        {
            throw error;
        }

        return result!;
    }

    public static void Invoke(Action action)
    {
        Invoke(() =>
        {
            action();
            return true;
        });
    }
}
