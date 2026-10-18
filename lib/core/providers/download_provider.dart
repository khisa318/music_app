import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_;
import 'package:metadata_god/metadata_god.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:disk_space_plus/disk_space_plus.dart';
import '../services/audio_url_isolate.dart';
import '../services/local_songs_service.dart';
import '../../shared/components/app_snackbar.dart';

import 'connectivity_provider.dart';
import 'settings_provider.dart';
import '../services/download_notification_service.dart';
import '../models/song_model.dart';

class DownloadProvider with ChangeNotifier {
  final _yt = GetIt.I<yt_.YoutubeExplode>();
  yt_.YoutubeExplode get yt => _yt;
  final _collectionEquality = const DeepCollectionEquality();

  /// How many automatic retries a failed download gets before it is parked
  /// as permanently failed. Between retries the song is rotated to the back
  /// of the queue so the remaining downloads are not held up.
  static const int _maxAutoRetries = 3;

  /// Public mirror of [_maxAutoRetries] so the UI can render "Retry 2/3"
  /// without duplicating the constant.
  static int get maxAutoRetries => _maxAutoRetries;

  final Map<String, CancelToken?> _downloadCancelTokens = {};
  final Map<String, DownloadProgress> _progressMap = {};
  List<Map<String, dynamic>> _downloadQueue = [];
  List<Map<String, dynamic>> _downloadedSongs = [];
  final Set<String> _preparing = {};
  final Set<String> _activeDownloads = {};

  /// Video ids whose in-flight download was cancelled on purpose (per-item
  /// pause/cancel/remove) rather than by a network failure. The download
  /// error path uses this to skip the automatic retry rotation.
  final Set<String> _userCancelledDownloads = {};

  /// Partial file currently being written for an active download, so a
  /// cancel or remove can delete the half-finished file instead of leaking it.
  final Map<String, String> _inFlightFilePaths = {};
  final Map<String, int> _notificationIds = {};
  int _nextNotificationId = 1000;
  bool _isPaused = false;
  bool _isProcessingQueue = false;
  late final ConnectivityProvider? _connectivityProvider;

  /// Tracks the last connectivity state seen by [_handleConnectivityChanged]
  /// so the queue is only resumed on a transition back online instead of on
  /// every notification the connectivity provider emits.
  bool _wasConnected = false;

  /// Throttles reconnect-driven resumes so a flapping network cannot requeue
  /// and restart the queue repeatedly in quick succession.
  DateTime? _lastReconnectResumeAt;
  static const Duration _reconnectResumeCooldown = Duration(seconds: 5);

  DownloadProvider() {
    _connectivityProvider = _getConnectivityProvider();
    _wasConnected = _connectivityProvider?.isConnected ?? false;
    _connectivityProvider?.addListener(_handleConnectivityChanged);
    loadDownloadedSongs();
    loadDownloadQueue();
    _initializeDownloads();
  }

  Map<String, DownloadProgress> get progressMap => _progressMap;
  List<Map<String, dynamic>> get downloadQueue => _downloadQueue;
  List<Map<String, dynamic>> get downloadedSongs => _downloadedSongs;
  Set<String> get preparing => _preparing;
  Set<String> get activeDownloads => _activeDownloads;
  bool get isPaused => _isPaused;

  ConnectivityProvider? _getConnectivityProvider() {
    try {
      return GetIt.I<ConnectivityProvider>();
    } catch (_) {
      return null;
    }
  }

  /// Resumes queued work whenever the device regains a usable connection,
  /// on Wi-Fi or mobile data alike. The Wi-Fi-only rule is kept intact: when
  /// [SettingsProvider.wifiOnlyDownloads] is on, a mobile connection is not
  /// enough and processing waits for Wi-Fi. Acting only on a transition to
  /// connected (plus a short cooldown) keeps a flapping network from looping.
  void _handleConnectivityChanged() {
    final connectivity = _connectivityProvider;
    if (connectivity == null) return;

    final isConnected = connectivity.isConnected;
    final wasConnected = _wasConnected;
    _wasConnected = isConnected;

    if (!isConnected || wasConnected) return;

    final now = DateTime.now();
    if (_lastReconnectResumeAt != null &&
        now.difference(_lastReconnectResumeAt!) < _reconnectResumeCooldown) {
      return;
    }
    _lastReconnectResumeAt = now;

    final settingsProvider = GetIt.I<SettingsProvider>();
    if (settingsProvider.wifiOnlyDownloads && !connectivity.isWifiConnected) {
      return;
    }

    if (_isPaused || _isProcessingQueue) return;

    unawaited(_resumeAfterReconnect());
  }

  /// Re-queues downloads that failed while offline (when they still have
  /// automatic retries left) and restarts queue processing once the device is
  /// back online on an allowed connection.
  Future<void> _resumeAfterReconnect() async {
    await _requeueFailedDownloadsWithRemainingRetries();
    if (!_isPaused && !_isProcessingQueue) {
      await _processDownloadQueue();
    }
  }

  @override
  void dispose() {
    _connectivityProvider?.removeListener(_handleConnectivityChanged);
    super.dispose();
  }

  Future<bool> _shouldShowNotifications() async {
    final settingsProvider = GetIt.I<SettingsProvider>();
    if (!settingsProvider.notificationsEnabled) return false;

    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } on MissingPluginException catch (e) {
      debugPrint(
        'Notification permission check unavailable, assuming granted: $e',
      );
      return true;
    } catch (e) {
      debugPrint('Error while checking notification permission: $e');
      return true;
    }
  }

  Future<void> _initializeDownloads() async {
    await _requeueFailedDownloadsWithRemainingRetries();
    await Future.delayed(const Duration(seconds: 2));
    await _processDownloadQueue();
  }

  /// Re-queues downloads that failed in a previous session and still have
  /// automatic retries left, so a flaky network at launch cannot permanently
  /// strand a song the user asked for.
  Future<void> _requeueFailedDownloadsWithRemainingRetries() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('download_queue') ?? [];
    var changed = false;

    final updatedQueue = queue.map((item) {
      final Map<String, dynamic> songData = json.decode(item);
      if (songData['status'] == 'failed') {
        final retryCount = (songData['retryCount'] as int?) ?? 0;
        if (retryCount < _maxAutoRetries) {
          songData['status'] = 'queued';
          changed = true;
          debugPrint(
            'Re-queued previously failed download $retryCount/$_maxAutoRetries '
            'retries used: ${songData['id']}',
          );
        }
      }
      return json.encode(songData);
    }).toList();

    if (changed) {
      await prefs.setStringList('download_queue', updatedQueue);
      await loadDownloadQueue();
    }
  }

  Future<void> _processDownloadQueue() async {
    if (_isProcessingQueue || _isPaused) return;
    _isProcessingQueue = true;

    try {
      final settingsProvider = GetIt.I<SettingsProvider>();
      if (settingsProvider.wifiOnlyDownloads &&
          _connectivityProvider?.isWifiConnected != true) {
        debugPrint(
          'Wi-Fi only downloads enabled and current network is not Wi-Fi. Queue processing will wait.',
        );
        return;
      }

      final maxConcurrent = settingsProvider.maxConcurrentDownloads;

      debugPrint(
        'Processing download queue. Max concurrent: $maxConcurrent, Active: ${_activeDownloads.length}',
      );

      while (!_isPaused &&
          _activeDownloads.length < maxConcurrent &&
          _downloadQueue.isNotEmpty) {
        final nextSong = _downloadQueue.firstWhereOrNull(
          (song) =>
              song['status'] == 'queued' &&
              !_activeDownloads.contains(song['id']),
        );

        if (nextSong != null) {
          _startQueuedDownload(nextSong);
        } else {
          break;
        }
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> pauseAllDownloads() async {
    if (_isPaused) return;
    _isPaused = true;

    for (final token in _downloadCancelTokens.values) {
      token?.cancel('Paused by user');
    }
    _downloadCancelTokens.clear();
    _activeDownloads.clear();

    await _setAllDownloadingStatusesToPaused();
    notifyListeners();
  }

  Future<void> resumeAllDownloads() async {
    if (!_isPaused) return;
    _isPaused = false;

    await _setAllPausedStatusesToQueued();
    notifyListeners();

    if (!_isProcessingQueue) {
      unawaited(_processDownloadQueue());
    }
  }

  Future<void> _setAllDownloadingStatusesToPaused() async {
    final prefs = await SharedPreferences.getInstance();
    final downloadQueue = prefs.getStringList('download_queue') ?? [];

    final updatedQueue = downloadQueue.map((item) {
      final Map<String, dynamic> songData = json.decode(item);
      if (songData['status'] == 'downloading') {
        songData['status'] = 'paused';
      }
      return json.encode(songData);
    }).toList();

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
  }

  Future<void> _setAllPausedStatusesToQueued() async {
    final prefs = await SharedPreferences.getInstance();
    final downloadQueue = prefs.getStringList('download_queue') ?? [];

    final updatedQueue = downloadQueue.map((item) {
      final Map<String, dynamic> songData = json.decode(item);
      if (songData['status'] == 'paused') {
        songData['status'] = 'queued';
      }
      return json.encode(songData);
    }).toList();

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
  }

  Future<void> _startQueuedDownload(Map<String, dynamic> songData) async {
    if (_isPaused) return;

    final videoId = songData['id'] as String;
    if (_activeDownloads.contains(videoId)) return;

    _activeDownloads.add(videoId);
    debugPrint('Starting queued download for videoId: $videoId');

    try {
      final artist = Artist(
        name: songData['artist'] ?? 'Unknown Artist',
        id: songData['artistId'] ?? '',
      );
      final thumbnail = Thumbnail(
        url: songData['thumbnail'] ?? '',
        width: 0,
        height: 0,
      );
      final song = SongInfo(
        videoId: videoId,
        name: songData['title'] ?? 'Unknown Title',
        artists: [artist],
        thumbnails: [thumbnail],
        duration: Duration(
          seconds: (songData['duration'] as num?)?.toInt() ?? 0,
        ),
      );

      await _startDownloadWithNotifications(song);
    } catch (e) {
      debugPrint('Failed to start queued download for $videoId: $e');
      _activeDownloads.remove(videoId);
      if (_isPaused) {
        await _updateDownloadQueueStatus(videoId, 'paused');
      } else {
        await _handleDownloadFailureWithRotation(
          videoId,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _startDownloadWithNotifications(SongInfo song) async {
    final videoId = song.videoId;
    final notificationId = _getNotificationId(videoId);
    final shouldShow = await _shouldShowNotifications();

    try {
      if (shouldShow) {
        await DownloadNotificationService().showDownloadProgress(
          notificationId: notificationId,
          title: song.name,
          artist: song.artists.isNotEmpty
              ? song.artists[0].name
              : 'Unknown Artist',
          progress: 0.0,
          isPaused: false,
        );
      }

      await _startDownload(song, shouldShow);
    } catch (e) {
      debugPrint('Download failed for $videoId: $e');
      if (shouldShow) {
        await DownloadNotificationService().showDownloadFailed(
          notificationId: notificationId,
          title: song.name,
          artist: song.artists.isNotEmpty
              ? song.artists[0].name
              : 'Unknown Artist',
        );
      }
      rethrow;
    } finally {
      _activeDownloads.remove(videoId);
      _downloadCancelTokens.remove(videoId);

      await _processDownloadQueue();
    }
  }

  int _getNotificationId(String videoId) {
    if (_notificationIds.containsKey(videoId)) {
      return _notificationIds[videoId]!;
    }
    final id = _nextNotificationId++;
    _notificationIds[videoId] = id;
    return id;
  }

  /// Older builds wrote queued entries with the duration in milliseconds
  /// while completed entries used seconds. Everything is stored in seconds
  /// now, so any leftover millisecond value is converted the first time the
  /// queue is read.
  static int _normalizeStoredDurationSeconds(dynamic raw) {
    final value = (raw as num?)?.toInt() ?? 0;
    if (value <= 0) return 0;
    // 24h expressed in seconds: no realistic track is that long, but a
    // millisecond value for anything past ~24 minutes already exceeds it.
    if (value >= const Duration(days: 1).inSeconds) {
      return (value / 1000).round();
    }
    return value;
  }

  Future<void> loadDownloadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queueList = prefs.getStringList('download_queue') ?? [];

    var migrated = false;
    final decodedQueue = queueList.map((item) {
      final songData = json.decode(item) as Map<String, dynamic>;
      final normalized = _normalizeStoredDurationSeconds(songData['duration']);
      if (normalized != songData['duration']) {
        songData['duration'] = normalized;
        migrated = true;
      }
      return songData;
    }).toList();

    if (migrated) {
      await prefs.setStringList(
        'download_queue',
        decodedQueue.map(json.encode).toList(),
      );
    }

    final newDownloadQueue = decodedQueue
        .where((song) => song['status'] != 'completed')
        .toList()
        .reversed
        .toList();

    if (!_collectionEquality.equals(_downloadQueue, newDownloadQueue)) {
      _downloadQueue = newDownloadQueue;
      notifyListeners();
    }
  }

  Future<void> loadDownloadedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final queueList = prefs.getStringList('download_queue') ?? [];

    final List<Map<String, dynamic>> completedSongs = queueList
        .map((item) => json.decode(item) as Map<String, dynamic>)
        .where((song) => song['status'] == 'completed')
        .toList();

    final List<Map<String, dynamic>> availableSongs = [];
    var removedMissing = false;

    for (final song in completedSongs) {
      song['duration'] = _normalizeStoredDurationSeconds(song['duration']);
      final path = song['localPath'] ?? song['filePath'];
      if (path == null) {
        removedMissing = true;
        continue;
      }
      final file = File(path);
      if (await file.exists()) {
        if (song['downloadedAt'] == null) {
          try {
            song['downloadedAt'] = file
                .lastModifiedSync()
                .millisecondsSinceEpoch;
          } catch (_) {}
        }
        availableSongs.add(song);
      } else {
        removedMissing = true;
      }
    }

    if (removedMissing) {
      final updatedQueue = queueList.where((item) {
        final Map<String, dynamic> songData = json.decode(item);
        if (songData['status'] == 'completed') {
          final path = songData['localPath'] ?? songData['filePath'];
          if (path == null) return false;
          final file = File(path);
          return file.existsSync();
        }
        return true;
      }).toList();
      await prefs.setStringList('download_queue', updatedQueue);
    }

    if (!_collectionEquality.equals(_downloadedSongs, availableSongs)) {
      _downloadedSongs = availableSongs;
      notifyListeners();
    }
  }

  /// Stops the in-flight download for [videoId], if any: cancels the Dio
  /// token, deletes the half-written file and clears progress so nothing
  /// keeps writing after the entry is gone.
  Future<void> _cancelInFlightDownload(String videoId) async {
    final token = _downloadCancelTokens.remove(videoId);
    final wasActive = token != null || _activeDownloads.contains(videoId);
    if (wasActive) {
      // Only mark deliberate cancellations for downloads that are actually
      // running, so a stale id cannot confuse a later genuine cancel.
      _userCancelledDownloads.add(videoId);
    }
    if (token != null && !token.isCancelled) {
      token.cancel('Cancelled by user');
    }
    _activeDownloads.remove(videoId);
    _preparing.remove(videoId);
    await _deleteFileQuietly(_inFlightFilePaths.remove(videoId));
    removeProgress(videoId);
  }

  Future<void> _deleteFileQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to delete file $path: $e');
    }
  }

  Future<void> _removeQueueEntry(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final downloadQueue = prefs.getStringList('download_queue') ?? [];

    final updatedQueue = downloadQueue.where((item) {
      final Map<String, dynamic> songData = json.decode(item);
      return songData['id'] != videoId;
    }).toList();

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
    await loadDownloadedSongs();
  }

  /// Runs [mutate] against the stored queue entry for [videoId] and persists
  /// the result. Used by the per-item pause/resume/retry actions.
  Future<void> _mutateQueueItem(
    String videoId,
    void Function(Map<String, dynamic> songData) mutate,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('download_queue') ?? [];

    var changed = false;
    final updatedQueue = queue.map((item) {
      final songData = json.decode(item) as Map<String, dynamic>;
      if (songData['id'] == videoId) {
        mutate(songData);
        changed = true;
      }
      return json.encode(songData);
    }).toList();

    if (!changed) return;
    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
    await loadDownloadedSongs();
  }

  /// Pauses a single queued or in-flight download without touching the rest
  /// of the queue.
  Future<void> pauseDownload(String videoId) async {
    await _cancelInFlightDownload(videoId);
    await _mutateQueueItem(videoId, (songData) {
      final status = songData['status'];
      if (status == 'downloading' ||
          status == 'queued' ||
          status == 'preparing') {
        songData['status'] = 'paused';
      }
    });
    notifyListeners();
  }

  /// Re-queues a single paused (or parked-as-failed) download.
  Future<void> resumeDownload(String videoId) async {
    await _mutateQueueItem(videoId, (songData) {
      final status = songData['status'];
      if (status == 'paused' || status == 'failed') {
        songData['status'] = 'queued';
        songData.remove('error');
      }
    });
    notifyListeners();
    if (!_isPaused && !_isProcessingQueue) {
      unawaited(_processDownloadQueue());
    }
  }

  /// Resets a failed download and puts it back at the front of the retry
  /// rotation with a full retry budget.
  Future<void> retryDownload(String videoId) async {
    await _mutateQueueItem(videoId, (songData) {
      final status = songData['status'];
      if (status != 'completed' && status != 'downloading') {
        songData
          ..['status'] = 'queued'
          ..['retryCount'] = 0
          ..remove('error');
      }
    });
    notifyListeners();
    if (!_isPaused && !_isProcessingQueue) {
      unawaited(_processDownloadQueue());
    }
  }

  /// Re-queues every failed download with a full retry budget and restarts the
  /// queue, so a batch of failures can be recovered in one tap. Does nothing
  /// when there is no failed entry.
  Future<void> retryAllFailed() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('download_queue') ?? [];

    var changed = false;
    final updatedQueue = queue.map((item) {
      final songData = json.decode(item) as Map<String, dynamic>;
      if (songData['status'] == 'failed') {
        songData
          ..['status'] = 'queued'
          ..['retryCount'] = 0
          ..remove('error');
        changed = true;
      }
      return json.encode(songData);
    }).toList();

    if (!changed) return;

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
    notifyListeners();

    if (_isPaused) {
      await resumeAllDownloads();
    } else if (!_isProcessingQueue) {
      unawaited(_processDownloadQueue());
    }
  }

  /// Cancels a single download: aborts any in-flight transfer and drops the
  /// entry from the queue entirely.
  Future<void> cancelDownload(String videoId) async {
    await _cancelInFlightDownload(videoId);
    await _removeQueueEntry(videoId);
    notifyListeners();
  }

  Future<void> removeDownload(Map<String, dynamic> song) async {
    final videoId = song['id'] as String?;
    if (videoId == null || videoId.isEmpty) return;
    await cancelDownload(videoId);
  }

  /// Removes every queued (non-completed) entry, cancelling anything that is
  /// still downloading. Completed downloads are left untouched.
  Future<void> clearQueue() async {
    final activeIds = _downloadQueue
        .map((song) => song['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    for (final videoId in activeIds) {
      await _cancelInFlightDownload(videoId);
    }

    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('download_queue') ?? [];
    final updatedQueue = queue.where((item) {
      final Map<String, dynamic> songData = json.decode(item);
      return songData['status'] == 'completed';
    }).toList();

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
    notifyListeners();
  }

  /// Deletes every completed download (files included) from storage.
  Future<void> clearCompletedDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('download_queue') ?? [];

    final updatedQueue = <String>[];
    for (final item in queue) {
      final Map<String, dynamic> songData = json.decode(item);
      if (songData['status'] == 'completed') {
        await _deleteFileQuietly(
          (songData['localPath'] ?? songData['filePath']) as String?,
        );
        continue;
      }
      updatedQueue.add(item);
    }

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
    await loadDownloadedSongs();
    notifyListeners();
  }

  /// Clears the queue and the completed downloads in one go.
  Future<void> clearAllDownloads() async {
    await clearQueue();
    await clearCompletedDownloads();
  }

  /// Resolves the directory downloads are written to, creating it when
  /// missing.
  Future<String> getDownloadDirectoryPath() async {
    final String base;
    if (Platform.isAndroid) {
      base = '/storage/emulated/0/Download/MusiX/Downloads';
    } else {
      base = '${(await getApplicationDocumentsDirectory()).path}/MusiX/Downloads';
    }
    final dir = Directory(base);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return base;
  }

  /// Total size, in bytes, of every downloaded file currently on disk.
  Future<int> getTotalDownloadedBytes() async {
    var total = 0;
    for (final song in _downloadedSongs) {
      final path = (song['localPath'] ?? song['filePath']) as String?;
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) {
          total += await file.length();
        }
      } catch (_) {}
    }
    return total;
  }

  /// Free space, in bytes, on the volume that holds the downloads folder.
  /// Returns null on platforms where disk_space_plus cannot answer.
  Future<int?> getFreeDiskSpaceBytes() async {
    try {
      final path = await getDownloadDirectoryPath();
      final freeMb = await DiskSpacePlus().getFreeDiskSpaceForPath(path);
      if (freeMb == null || freeMb.isNaN || freeMb.isInfinite) return null;
      return (freeMb * 1024 * 1024).round();
    } catch (e) {
      debugPrint('Failed to read free disk space: $e');
      return null;
    }
  }

  Future<void> deleteDownloadedSong(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    final downloadQueue = prefs.getStringList('download_queue') ?? [];

    String? filePath;
    final updatedQueue = downloadQueue.where((item) {
      final Map<String, dynamic> songData = json.decode(item);
      if (songData['id'] == songId) {
        filePath = songData['localPath'] ?? songData['filePath'];
        return false;
      }
      return true;
    }).toList();

    if (filePath != null) {
      final file = File(filePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadedSongs();
    notifyListeners();
  }

  Future<void> downloadSong(SongInfo song) async {
    final videoId = song.videoId;
    debugPrint('Download requested for videoId: $videoId');

    if (_progressMap.containsKey(videoId) ||
        _preparing.contains(videoId) ||
        _activeDownloads.contains(videoId)) {
      debugPrint(
        'Download already in progress or preparing for videoId: $videoId',
      );
      return;
    }

    _preparing.add(videoId);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('download_queue') ?? [];

    final existingIndex = queue.indexWhere((item) {
      final songData = json.decode(item) as Map<String, dynamic>;
      return songData['id'] == videoId;
    });

    if (existingIndex == -1) {
      debugPrint('Song not in queue. Adding to queue for videoId: $videoId');
      final newSong = {
        'id': videoId,
        'title': song.name,
        'artist': song.artists.isNotEmpty
            ? song.artists[0].name
            : 'Unknown Artist',
        'artistId': song.artists.isNotEmpty ? song.artists[0].id : '',
        'thumbnail': song.thumbnails.isNotEmpty ? song.thumbnails[0].url : '',
        'status': 'queued',
        'duration': song.duration.inSeconds,
      };
      queue.insert(0, json.encode(newSong));
      await prefs.setStringList('download_queue', queue);
      await loadDownloadQueue();
      debugPrint('Song added to queue for videoId: $videoId');
    } else {
      final existingSong =
          json.decode(queue[existingIndex]) as Map<String, dynamic>;
      final status = existingSong['status'];
      final existingPath =
          existingSong['localPath'] ?? existingSong['filePath'];
      final isCompleted =
          status == 'completed' &&
          existingPath is String &&
          await File(existingPath).exists();

      if (status == 'queued' ||
          status == 'downloading' ||
          status == 'paused' ||
          isCompleted) {
        debugPrint('Song already in queue for videoId: $videoId');
      } else {
        existingSong
          ..['title'] = song.name
          ..['artist'] = song.artists.isNotEmpty
              ? song.artists[0].name
              : 'Unknown Artist'
          ..['artistId'] = song.artists.isNotEmpty ? song.artists[0].id : ''
          ..['thumbnail'] = song.thumbnails.isNotEmpty
              ? song.thumbnails[0].url
              : ''
          ..['duration'] = song.duration.inSeconds
          ..['status'] = 'queued'
          ..['retryCount'] = 0
          ..remove('localPath')
          ..remove('filePath')
          ..remove('error');
        queue[existingIndex] = json.encode(existingSong);
        await prefs.setStringList('download_queue', queue);
        await loadDownloadQueue();
        debugPrint('Retrying download for videoId: $videoId');
      }
    }

    if (_isPaused) {
      await resumeAllDownloads();
    } else if (!_isProcessingQueue) {
      unawaited(_processDownloadQueue());
    }
  }

  Future<void> downloadPlaylist(
    List<dynamic> songs,
    String playlistName,
  ) async {
    debugPrint(
      'Download playlist requested: $playlistName with ${songs.length} songs',
    );

    final songInfos = songs.map((song) {
      final artist = Artist(
        name: song.artists != null && song.artists.isNotEmpty
            ? song.artists[0].name ?? 'Unknown Artist'
            : 'Unknown Artist',
        id: '',
      );
      final thumbnail = Thumbnail(
        url: song.thumbnails != null && song.thumbnails.isNotEmpty
            ? song.thumbnails[0].url ?? ''
            : '',
        width: 0,
        height: 0,
      );
      return SongInfo(
        videoId: song.videoId,
        name: song.name ?? 'Unknown Title',
        artists: [artist],
        thumbnails: [thumbnail],
        duration: song.duration ?? Duration.zero,
      );
    }).toList();

    for (final song in songInfos) {
      await downloadSong(song);
    }

    debugPrint(
      'All songs from playlist "$playlistName" added to download queue',
    );
  }

  Future<void> downloadSongs(List<SongInfo> songs) async {
    for (final song in songs) {
      await downloadSong(song);
    }
  }

  Future<void> startQueuedDownload(String videoId) async {
    if (_isPaused) {
      await resumeAllDownloads();
      return;
    }

    final songData = _downloadQueue.firstWhereOrNull(
      (song) => song['id'] == videoId,
    );
    if (songData != null) {
      await _startQueuedDownload(songData);
    }
  }

  DateTime? _lastStreamErrorShownAt;

  /// Shows a warning when a download URL fetch fails because YouTube is
  /// asking the user to verify they are not a bot. Throttled so a batch of
  /// downloads hitting the same check does not stack snackbars.
  void _maybeShowStreamError(
    Map<String, dynamic> urlResult,
    SettingsProvider settingsProvider,
  ) {
    if (urlResult['errorType'] != 'bot_check') return;

    final now = DateTime.now();

    if (_lastStreamErrorShownAt != null &&
        now.difference(_lastStreamErrorShownAt!) <
            const Duration(seconds: 15)) {
      return;
    }

    _lastStreamErrorShownAt = now;

    final context = settingsProvider.navigatorKey.currentContext;

    if (context == null || !context.mounted) return;

    AppSnackBar.showWarning(
      context,
      urlResult['error'] as String? ??
          'YouTube is asking to verify you are not a bot. '
              'Please try again in a moment.',
    );
  }

  Future<void> _startDownload(
    SongInfo song,
    bool shouldShowNotifications,
  ) async {
    final videoId = song.videoId;
    try {
      debugPrint('Starting download process for videoId: $videoId');
      final downloadDir = Directory(await getDownloadDirectoryPath());

      await _updateDownloadQueueStatus(song.videoId, 'downloading');
      debugPrint('Updated queue status to "downloading" for videoId: $videoId');

      final settingsProvider = GetIt.I<SettingsProvider>();

      Map<String, dynamic> urlResult = {};
      const transientErrorTypes = {'bot_check', 'network'};

      for (var attempt = 0; attempt < 2; attempt++) {
        urlResult = await AudioUrlIsolate.fetchStreamUrl(
          videoId: videoId,
          streamingQuality: settingsProvider.downloadingQuality.toLowerCase(),
          timeout: const Duration(seconds: 30),
          title: song.name,
          artist: song.artists.isNotEmpty
              ? song.artists[0].name
              : 'Unknown Artist',
          forDownloading: true,
          jioSaavnEnabled: settingsProvider.jioSaavnEnabled,
        );

        if (urlResult['success'] == true) break;

        final isTransient = transientErrorTypes.contains(urlResult['errorType']);

        if (!isTransient || attempt == 1) break;

        debugPrint(
          'Download URL fetch for $videoId failed '
          '(${urlResult['errorType']}); retrying once with a fresh URL',
        );
        await Future.delayed(const Duration(seconds: 2));
      }

      if (urlResult['success'] != true) {
        _maybeShowStreamError(urlResult, settingsProvider);
        throw Exception('Failed to fetch download URL: ${urlResult['error']}');
      }

      final downloadUrl = urlResult['url'] as String;
      final totalBytes = urlResult['size'] as int? ?? 0;
      final extension = urlResult['extension'] as String? ?? 'm4a';
      final streamDurationMs = urlResult['duration'] as int?;
      debugPrint('Download URL fetched for videoId: $videoId');
      debugPrint('Download URL $downloadUrl');

      final fileName = _sanitizeFileName(song.name);
      final uniqueFileName = await _getUniqueFileName(
        fileName,
        extension,
        downloadDir,
      );
      final filePath = '${downloadDir.path}/$uniqueFileName';
      _inFlightFilePaths[videoId] = filePath;

      final dio = Dio(
        BaseOptions(
          connectTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(minutes: 5),
        ),
      );
      final cancelToken = CancelToken();
      _downloadCancelTokens[song.videoId] = cancelToken;

      await dio.download(
        downloadUrl,
        filePath,
        options: totalBytes > 0
            ? Options(headers: {"Range": 'bytes=0-$totalBytes'})
            : null,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (_preparing.contains(videoId)) {
            _preparing.remove(videoId);
          }
          final progress = total > 0 ? received / total : 0.0;
          updateProgress(song.videoId, progress);

          if (shouldShowNotifications) {
            if ((progress * 100).round() % 5 == 0 || progress >= 0.95) {
              final notificationId = _getNotificationId(videoId);
              DownloadNotificationService().showDownloadProgress(
                notificationId: notificationId,
                title: song.name,
                artist: song.artists.isNotEmpty
                    ? song.artists[0].name
                    : 'Unknown Artist',
                progress: progress,
                isPaused: false,
              );
            }
          }
        },
      );

      debugPrint('Download completed for videoId: $videoId');
      _preparing.remove(videoId);

      try {
        await _writeMetadataToFile(song, filePath, downloadDir);
      } catch (e) {
        debugPrint(
          'Metadata writing failed for $videoId, but download succeeded: $e',
        );
      }

      try {
        await LocalSongsService().scanMedia(filePath);
      } catch (e) {
        debugPrint('Media scan failed for $filePath: $e');
      }

      await _updateDownloadQueueStatus(
        song.videoId,
        'completed',
        additionalData: {
          'filePath': filePath,
          'localPath': filePath,
          'title': song.name,
          'duration': song.duration.inSeconds > 0
              ? song.duration.inSeconds
              : (streamDurationMs != null && streamDurationMs > 0
                    ? (streamDurationMs / 1000).round()
                    : 0),
          'isDownloaded': true,
          'downloadedAt': DateTime.now().millisecondsSinceEpoch,
        },
      );

      removeProgress(song.videoId);
      _downloadCancelTokens.remove(videoId);
      _inFlightFilePaths.remove(videoId);

      if (shouldShowNotifications) {
        final notificationId = _getNotificationId(videoId);
        await DownloadNotificationService().showDownloadComplete(
          notificationId: notificationId,
          title: song.name,
          artist: song.artists.isNotEmpty
              ? song.artists[0].name
              : 'Unknown Artist',
        );
      }

      debugPrint('Updated queue status to "completed" for videoId: $videoId');
    } catch (e) {
      debugPrint('Download failed for videoId: $videoId. Exception: $e');
      _preparing.remove(videoId);
      final wasUserCancelled = _userCancelledDownloads.remove(videoId);
      final partialPath = _inFlightFilePaths.remove(videoId);
      final isCancel =
          e is DioException && e.type == DioExceptionType.cancel;

      if (isCancel && (wasUserCancelled || _isPaused)) {
        // Deliberate stop: the caller (pause/cancel/remove) already set the
        // queue status; just clean up the partial file and leave it there.
        await _deleteFileQuietly(partialPath);
        if (!wasUserCancelled && _isPaused) {
          await _updateDownloadQueueStatus(song.videoId, 'paused');
        }
      } else {
        await _deleteFileQuietly(partialPath);
        await _handleDownloadFailureWithRotation(
          videoId,
          error: e.toString(),
        );
      }
      removeProgress(song.videoId);
      _downloadCancelTokens.remove(videoId);
      notifyListeners();
      if (!isCancel || (!wasUserCancelled && !_isPaused)) {
        rethrow;
      }
    }
  }

  /// Handles a failed download by rotating it to the back of the queue for
  /// another attempt, until [_maxAutoRetries] is exhausted.
  ///
  /// Rotation is the point: a single bad stream must not block the rest of
  /// the queue. The failed song goes to the end so everything else gets a
  /// turn first, and by the time it comes around the stream may well resolve.
  Future<void> _handleDownloadFailureWithRotation(
    String videoId, {
    String? error,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('download_queue') ?? [];

    Map<String, dynamic>? target;
    for (final item in queue) {
      final Map<String, dynamic> songData = json.decode(item);
      if (songData['id'] == videoId) {
        target = songData;
        break;
      }
    }
    if (target == null) return;

    final retryCount = (target['retryCount'] as int?) ?? 0;

    if (retryCount >= _maxAutoRetries) {
      debugPrint(
        'Download failed permanently after $retryCount retries: $videoId',
      );
      await _updateDownloadQueueStatus(
        videoId,
        'failed',
        additionalData: {'error': error ?? 'Download failed'},
      );
      return;
    }

    // Move the entry to the front of the stored list, which [loadDownloadQueue]
    // reverses into the back of the in-memory queue - i.e. it retries last.
    final updatedQueue = queue.where((item) {
      final Map<String, dynamic> songData = json.decode(item);
      return songData['id'] != videoId;
    }).toList();

    target
      ..['status'] = 'queued'
      ..['retryCount'] = retryCount + 1
      ..['error'] = error ?? 'Download failed';
    updatedQueue.insert(0, json.encode(target));

    await prefs.setStringList('download_queue', updatedQueue);
    debugPrint(
      'Re-queued $videoId for retry ${retryCount + 1}/$_maxAutoRetries '
      '(moved to back of queue)',
    );
    await loadDownloadQueue();
  }

  Future<void> _updateDownloadQueueStatus(
    String videoId,
    String status, {
    Map<String, dynamic>? additionalData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final downloadQueue = prefs.getStringList('download_queue') ?? [];

    final updatedQueue = downloadQueue.map((item) {
      final Map<String, dynamic> songData = json.decode(item);
      if (songData['id'] == videoId) {
        songData['status'] = status;
        if (status == 'completed') {
          // A finished download has no lingering failure state to show.
          songData
            ..remove('error')
            ..['retryCount'] = 0;
        }
        if (additionalData != null) {
          songData.addAll(additionalData);
        }
      }
      return json.encode(songData);
    }).toList();

    await prefs.setStringList('download_queue', updatedQueue);
    await loadDownloadQueue();
    await loadDownloadedSongs();
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'\s|[\\/:*?"<>|]'), '_');
  }

  Future<String> _getUniqueFileName(
    String baseName,
    String extension,
    Directory dir,
  ) async {
    String fileName = baseName;
    int counter = 1;
    while (await File('${dir.path}/$fileName.$extension').exists()) {
      fileName = '$baseName ($counter)';
      counter++;
    }
    return '$fileName.$extension';
  }

  Future<List<Map<String, dynamic>>> getDownloadedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final downloadQueue = prefs.getStringList('download_queue') ?? [];

    final List<Map<String, dynamic>> completedSongs = downloadQueue
        .map((item) => json.decode(item) as Map<String, dynamic>)
        .where((song) => song['status'] == 'completed')
        .toList();

    final List<Map<String, dynamic>> availableSongs = [];

    for (final song in completedSongs) {
      final path = song['localPath'] ?? song['filePath'];
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) {
        availableSongs.add(song);
      }
    }

    return availableSongs;
  }

  Future<String?> getDownloadedSongPath(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final downloadQueue = prefs.getStringList('download_queue') ?? [];

    final downloadedSong = downloadQueue
        .map((item) => json.decode(item) as Map<String, dynamic>)
        .firstWhereOrNull(
          (song) => song['id'] == videoId && song['status'] == 'completed',
        );

    if (downloadedSong != null) {
      final path = downloadedSong['localPath'] ?? downloadedSong['filePath'];
      if (path != null && await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  void updateProgress(String videoId, double progress) {
    final current = _progressMap[videoId]?.progress ?? -1.0;
    if (current >= 0 && (progress - current).abs() < 0.01) return;
    _progressMap[videoId] = DownloadProgress(
      videoId: videoId,
      progress: progress,
      isPaused: _progressMap[videoId]?.isPaused ?? false,
    );
    notifyListeners();
  }

  void removeProgress(String videoId) {
    _progressMap.remove(videoId);
    notifyListeners();
  }

  Future<void> _writeMetadataToFile(
    SongInfo song,
    String filePath,
    Directory downloadDir,
  ) async {
    if (filePath.endsWith('.opus')) {
      debugPrint('Skipping metadata write for opus file: $filePath');
      return;
    }

    final videoId = song.videoId;

    Uint8List? imageBytes;
    String? imageMime;

    final maxResUrl = 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
    final thumbUrl = song.thumbnails.isNotEmpty ? song.thumbnails[0].url : null;

    try {
      FileInfo? fileInfo = await DefaultCacheManager().getFileFromCache(
        maxResUrl,
      );
      if (fileInfo != null) {
        debugPrint(
          'Using cached maxresdefault thumbnail for videoId: $videoId',
        );
        imageBytes = await fileInfo.file.readAsBytes();
      } else {
        debugPrint(
          'Fetching fresh maxresdefault thumbnail for videoId: $videoId',
        );
        final file = await DefaultCacheManager().getSingleFile(maxResUrl);
        imageBytes = await file.readAsBytes();
      }
      imageMime = 'image/jpeg';
    } catch (e) {
      debugPrint(
        'Maxresdefault thumbnail failed for videoId: $videoId. Error: $e. Falling back to original thumbnail.',
      );
      if (thumbUrl != null && thumbUrl.isNotEmpty) {
        try {
          FileInfo? fileInfo = await DefaultCacheManager().getFileFromCache(
            thumbUrl,
          );
          if (fileInfo != null) {
            debugPrint('Using cached original thumbnail for videoId: $videoId');
            imageBytes = await fileInfo.file.readAsBytes();
          } else {
            debugPrint(
              'Fetching fresh original thumbnail for videoId: $videoId',
            );
            final file = await DefaultCacheManager().getSingleFile(thumbUrl);
            imageBytes = await file.readAsBytes();
          }
          imageMime = 'image/jpeg';
        } catch (e) {
          debugPrint(
            'Original thumbnail failed for videoId: $videoId. Error: $e',
          );
        }
      }
    }

    try {
      final mimeType = imageMime ?? 'image/jpeg';

      final metadata = Metadata(
        title: song.name,
        artist: song.artists.isNotEmpty ? song.artists[0].name : '',
        album: song.name,
        durationMs: song.duration.inMilliseconds.toDouble(),
        fileSize: BigInt.from(await File(filePath).length()),
        picture: (imageBytes != null && imageBytes.isNotEmpty)
            ? Picture(data: imageBytes, mimeType: mimeType)
            : null,
      );

      await MetadataGod.writeMetadata(file: filePath, metadata: metadata);
      debugPrint('Metadata written successfully for $videoId');
    } catch (e) {
      debugPrint('Failed to write metadata for $videoId: $e');
    }
  }
}

class DownloadProgress {
  final String videoId;
  final double progress;
  final bool isPaused;

  DownloadProgress({
    required this.videoId,
    required this.progress,
    this.isPaused = false,
  });
}
