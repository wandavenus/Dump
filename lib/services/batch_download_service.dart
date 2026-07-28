import '../models/online_track.dart';

abstract class TrackQueueSink {
  Future<void> enqueue(OnlineTrack track, {String? qualityOverride, String? extensionId});

  Future<void> enqueueBatch(List<OnlineTrack> tracks, {String? extensionId});
}

abstract class OnlineCollectionResolver {
  Future<List<OnlineTrack>> getAlbumTracks(String albumId, String extensionId);

  Future<List<OnlineTrack>> getPlaylistTracks(String playlistId, String extensionId);
}

class BatchDownloadService {
  final OnlineCollectionResolver _resolver;
  final TrackQueueSink _queueSink;

  const BatchDownloadService({
    required OnlineCollectionResolver resolver,
    required TrackQueueSink queueSink,
  }) : _resolver = resolver,
       _queueSink = queueSink;

  Future<void> downloadAlbum(
    String albumId, {
    required String extensionId,
    String? quality,
    bool createSubfolder = true,
  }) async {
    final tracks = await resolveAlbumTracks(albumId, extensionId);
    await _enqueueTracks(tracks, extensionId: extensionId, quality: quality);
  }

  Future<void> downloadPlaylist(
    String playlistId, {
    required String extensionId,
    String? quality,
  }) async {
    final tracks = await resolvePlaylistTracks(playlistId, extensionId);
    await _enqueueTracks(tracks, extensionId: extensionId, quality: quality);
  }

  Future<List<OnlineTrack>> resolveAlbumTracks(String albumId, String extensionId) {
    return _resolver.getAlbumTracks(albumId, extensionId);
  }

  Future<List<OnlineTrack>> resolvePlaylistTracks(String playlistId, String extensionId) {
    return _resolver.getPlaylistTracks(playlistId, extensionId);
  }

  Future<void> _enqueueTracks(
    List<OnlineTrack> tracks, {
    required String extensionId,
    String? quality,
  }) async {
    if (quality == null) {
      await _queueSink.enqueueBatch(tracks, extensionId: extensionId);
      return;
    }

    for (final track in tracks) {
      await _queueSink.enqueue(track, qualityOverride: quality, extensionId: extensionId);
    }
  }
}
