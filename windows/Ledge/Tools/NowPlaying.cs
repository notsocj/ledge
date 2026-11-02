using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Windows.Foundation;
using Windows.Media.Control;
using Session = Windows.Media.Control.GlobalSystemMediaTransportControlsSession;

namespace Ledge;

/// <summary>What's playing in any app that reports to Windows' media controls: Spotify, browsers,
/// Media Player and the rest. Windows' events arrive on other threads, so everything is moved onto the UI thread.</summary>
public sealed class NowPlaying(Dispatcher dispatcher)
{
    GlobalSystemMediaTransportControlsSessionManager? manager;
    Session? session;
    string artworkFor = "";

    public string Title { get; private set; } = "";
    public string Artist { get; private set; } = "";
    public bool IsPlaying { get; private set; }
    public ImageSource? Artwork { get; private set; }
    public bool HasMedia => Title.Length > 0;
    public event Action? Changed;

    public async Task StartAsync()
    {
        try
        {
            manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        }
        catch (Exception)
        {
            return; // media controls aren't available, as on Windows N editions without the Media Feature Pack
        }
        manager.CurrentSessionChanged += (_, _) => Later(Follow);
        Follow();
    }

    public Task PlayPause() => Send(current => current.TryTogglePlayPauseAsync());
    public Task Next() => Send(current => current.TrySkipNextAsync());
    public Task Previous() => Send(current => current.TrySkipPreviousAsync());

    async Task Send(Func<Session, IAsyncOperation<bool>> command)
    {
        if (session is not { } current) return;
        try { await command(current); } catch (Exception) { } // the app closed in between
    }

    void Later(Action action) => dispatcher.BeginInvoke(action);

    void Follow()
    {
        if (session is not null)
        {
            session.MediaPropertiesChanged -= OnMediaChanged;
            session.PlaybackInfoChanged -= OnPlaybackChanged;
        }
        session = manager?.GetCurrentSession();
        if (session is not null)
        {
            session.MediaPropertiesChanged += OnMediaChanged;
            session.PlaybackInfoChanged += OnPlaybackChanged;
        }
        _ = Refresh();
    }

    void OnMediaChanged(Session sender, MediaPropertiesChangedEventArgs args) => Later(() => _ = Refresh());
    void OnPlaybackChanged(Session sender, PlaybackInfoChangedEventArgs args) => Later(() => _ = Refresh());

    async Task Refresh()
    {
        var current = session;
        try
        {
            if (current is null)
            {
                Title = Artist = artworkFor = "";
                IsPlaying = false;
                Artwork = null;
            }
            else
            {
                var media = await current.TryGetMediaPropertiesAsync();
                if (current != session) return; // another app took over while reading
                IsPlaying = current.GetPlaybackInfo()?.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
                Title = media?.Title ?? "";
                Artist = media?.Artist ?? "";
                var song = Title + "\n" + Artist;
                if (song != artworkFor)
                {
                    artworkFor = song;
                    Artwork = media?.Thumbnail is { } thumbnail ? await LoadArtwork(thumbnail) : null;
                }
            }
        }
        catch (Exception)
        {
            // The app went away mid-read; its next event refreshes.
        }
        Changed?.Invoke();
    }

    static async Task<ImageSource?> LoadArtwork(Windows.Storage.Streams.IRandomAccessStreamReference thumbnail)
    {
        using var stream = await thumbnail.OpenReadAsync();
        using var source = stream.AsStreamForRead();
        var memory = new MemoryStream();
        await source.CopyToAsync(memory);
        memory.Position = 0;
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.DecodePixelWidth = 176; // the 88 px artwork at 200%
        image.StreamSource = memory;
        image.EndInit();
        image.Freeze();
        return image;
    }
}
