import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart'
    show ArtistDetailed, ThumbnailFull;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/song_model.dart';
import '../../../../core/providers/download_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/services/content_details_service.dart';
import '../../../../core/utils/content_router.dart';
import '../../../../core/widgets/glass_modal.dart';
import '../../../../shared/components/app_empty_state.dart';
import '../../../../shared/components/app_snackbar.dart';
import '../../../../shared/components/songs_options_bottomsheet.dart';
import '../../../main_screen/presentation/screens/full_player_screen.dart';
import '../../../player/presentation/screens/player_ui.dart';
import '../widgets/download_settings_sheet.dart';

enum QueueSortOption { status, titleAsc, titleDesc }

enum DownloadedSortOption {
  titleAsc,
  titleDesc,
  artistAsc,
  artistDesc,
  dateDesc,
  dateAsc,
  fileSizeDesc,
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  Set<String> _selectedSongs = {};
  bool _isSelectionMode = false;

  late TabController _tabController;

  QueueSortOption _queueSort = QueueSortOption.status;
  DownloadedSortOption _downloadedSort = DownloadedSortOption.dateDesc;

  bool _showQueueSearch = false;
  bool _showDownloadedSearch = false;
  final _queueSearchController = TextEditingController();
  final _downloadedSearchController = TextEditingController();

  /// Cached file sizes for downloaded songs, keyed by video id, so the list
  /// and the storage summary do not stat every file on each rebuild.
  final Map<String, int> _fileSizeCache = {};
  int _downloadedBytes = 0;

  DownloadProvider? _downloadProvider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _downloadProvider = context.read<DownloadProvider>();
      _downloadProvider!.addListener(_refreshDerivedInfo);
      _refreshDerivedInfo();
    });
  }

  @override
  void dispose() {
    _downloadProvider?.removeListener(_refreshDerivedInfo);
    _tabController.dispose();
    _queueSearchController.dispose();
    _downloadedSearchController.dispose();
    super.dispose();
  }

  void _onTabChange() {
    if (_isSelectionMode) {
      setState(() {
        _selectedSongs.clear();
        _isSelectionMode = false;
      });
    } else {
      setState(() {});
    }
  }

  /// Recomputes per-song file sizes and the total used bytes whenever the
  /// download provider reports a change.
  Future<void> _refreshDerivedInfo() async {
    final provider = _downloadProvider;
    if (provider == null) return;
    final seenIds = <String>{};
    var total = 0;
    var cacheChanged = false;

    for (final song in provider.downloadedSongs) {
      final id = song['id'] as String? ?? '';
      final path = (song['localPath'] ?? song['filePath']) as String?;
      if (id.isEmpty || path == null) continue;
      seenIds.add(id);

      var size = _fileSizeCache[id];
      if (size == null) {
        try {
          final file = File(path);
          size = await file.exists() ? await file.length() : 0;
        } catch (_) {
          size = 0;
        }
        _fileSizeCache[id] = size;
        cacheChanged = true;
      }
      total += size;
    }

    if (_fileSizeCache.length != seenIds.length) {
      _fileSizeCache.removeWhere((id, _) => !seenIds.contains(id));
      cacheChanged = true;
    }

    if (mounted && (cacheChanged || total != _downloadedBytes)) {
      setState(() {
        _downloadedBytes = total;
      });
    }
  }

  // ---------------------------------------------------------------------
  // Filtering & sorting
  // ---------------------------------------------------------------------

  List<Map<String, dynamic>> _filteredQueue(DownloadProvider downloadProvider) {
    final query = _queueSearchController.text.trim().toLowerCase();
    final items = downloadProvider.downloadQueue.where((song) {
      if (query.isEmpty) return true;
      final title = (song['title'] as String? ?? '').toLowerCase();
      final artist = (song['artist'] as String? ?? '').toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();

    items.sort((a, b) {
      switch (_queueSort) {
        case QueueSortOption.status:
          final byStatus = _statusOrder(a).compareTo(_statusOrder(b));
          if (byStatus != 0) return byStatus;
          return _titleOf(a).compareTo(_titleOf(b));
        case QueueSortOption.titleAsc:
          return _titleOf(a).compareTo(_titleOf(b));
        case QueueSortOption.titleDesc:
          return _titleOf(b).compareTo(_titleOf(a));
      }
    });
    return items;
  }

  List<Map<String, dynamic>> _filteredDownloaded(
    DownloadProvider downloadProvider,
  ) {
    final query = _downloadedSearchController.text.trim().toLowerCase();
    final items = downloadProvider.downloadedSongs.where((song) {
      if (query.isEmpty) return true;
      final title = (song['title'] as String? ?? '').toLowerCase();
      final artist = (song['artist'] as String? ?? '').toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();

    items.sort((a, b) {
      switch (_downloadedSort) {
        case DownloadedSortOption.titleAsc:
          return _titleOf(a).compareTo(_titleOf(b));
        case DownloadedSortOption.titleDesc:
          return _titleOf(b).compareTo(_titleOf(a));
        case DownloadedSortOption.artistAsc:
          return _artistOf(a).compareTo(_artistOf(b));
        case DownloadedSortOption.artistDesc:
          return _artistOf(b).compareTo(_artistOf(a));
        case DownloadedSortOption.dateDesc:
          return _getSongTimestamp(b).compareTo(_getSongTimestamp(a));
        case DownloadedSortOption.dateAsc:
          return _getSongTimestamp(a).compareTo(_getSongTimestamp(b));
        case DownloadedSortOption.fileSizeDesc:
          return _sizeOf(b).compareTo(_sizeOf(a));
      }
    });
    return items;
  }

  int _statusOrder(Map<String, dynamic> song) {
    switch (song['status']) {
      case 'downloading':
      case 'preparing':
        return 0;
      case 'queued':
        return 1;
      case 'paused':
        return 2;
      case 'failed':
        return 3;
      default:
        return 4;
    }
  }

  String _titleOf(Map<String, dynamic> song) =>
      (song['title'] as String? ?? '').toLowerCase();

  String _artistOf(Map<String, dynamic> song) =>
      (song['artist'] as String? ?? '').toLowerCase();

  int _sizeOf(Map<String, dynamic> song) =>
      _fileSizeCache[song['id'] as String? ?? ''] ?? 0;

  int _getSongTimestamp(Map<String, dynamic> song) {
    try {
      final downloadedAt = song['downloadedAt'];
      if (downloadedAt is int) return downloadedAt;
      if (downloadedAt is String) {
        final parsedInt = int.tryParse(downloadedAt);
        if (parsedInt != null) return parsedInt;
        final parsedDate = DateTime.tryParse(downloadedAt);
        if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
      }

      final path = song['localPath'] ?? song['filePath'];
      if (path != null && path is String) {
        final file = File(path);
        if (file.existsSync()) {
          return file.lastModifiedSync().millisecondsSinceEpoch;
        }
      }
    } catch (_) {}
    return 0;
  }

  // ---------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------

  static String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024.0;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  static String _fmtDuration(Duration duration) {
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '${duration.inMinutes}:$seconds';
  }

  static String _fmtDate(int milliseconds) {
    if (milliseconds <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'downloading':
      case 'preparing':
        return 'download_status_downloading'.tr();
      case 'paused':
        return 'download_status_paused'.tr();
      case 'failed':
        return 'download_status_failed'.tr();
      default:
        return 'download_status_queued'.tr();
    }
  }

  SongInfo _convertToSongInfo(Map<String, dynamic> song) {
    return SongInfo(
      videoId: song['id'] ?? '',
      name: song['title'] ?? '',
      artists: [
        Artist(
          name: song['artist'] ?? '',
          id: (song['artistId'] as String?) ?? '',
        ),
      ],
      thumbnails: [
        Thumbnail(url: song['thumbnail'] ?? '', width: 480, height: 360),
      ],
      duration: Duration(seconds: (song['duration'] as num?)?.toInt() ?? 0),
    );
  }

  // ---------------------------------------------------------------------
  // Queue actions
  // ---------------------------------------------------------------------

  Future<void> _toggleAllDownloads() async {
    final downloadProvider = context.read<DownloadProvider>();
    if (downloadProvider.isPaused) {
      await downloadProvider.resumeAllDownloads();
      if (!mounted) return;
      AppSnackBar.showInfo(context, 'resumed_downloads'.tr());
    } else {
      await downloadProvider.pauseAllDownloads();
      if (!mounted) return;
      AppSnackBar.showInfo(context, 'paused_downloads'.tr());
    }
  }

  Widget _buildQueueItem(
    Map<String, dynamic> song,
    DownloadProvider downloadProvider,
    Color accentColor,
    bool isDarkMode,
  ) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);
    final status = (song['status'] as String?) ?? 'queued';
    final videoId = song['id'] as String? ?? '';
    final progress = downloadProvider.progressMap[videoId];
    final error = song['error'] as String?;
    final retryCount = (song['retryCount'] as num?)?.toInt() ?? 0;
    final showProgress =
        progress != null && status != 'failed' && status != 'paused';

    final retryText = retryCount > 0
        ? 'retry_attempt'.tr(
            args: ['$retryCount', '${DownloadProvider.maxAutoRetries}'],
          )
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingLg,
        vertical: AppDimens.spacingSm,
      ),
      decoration: BoxDecoration(
        color: MainScreenColors.getSurfaceColor(isDarkMode),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.all(AppDimens.paddingSm),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
            child: _buildThumbnail(song['thumbnail'], isDarkMode),
          ),
          title: Text(
            song['title'] ?? '',
            style: AppTextStyles.queueItem(isDarkMode: isDarkMode),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song['artist'] ?? '',
                style: AppTextStyles.settingsSubtitle(isDarkMode: isDarkMode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppDimens.spacingXs),
              Row(
                children: [
                  Icon(
                    _statusIcon(status),
                    size: AppDimens.iconXs,
                    color: status == 'failed'
                        ? Colors.red
                        : status == 'paused'
                        ? Colors.orange
                        : status == 'downloading' || status == 'preparing'
                        ? accentColor
                        : textColor.withValues(alpha: AppDimens.opacityMuted),
                  ),
                  const SizedBox(width: AppDimens.spacingXs),
                  Flexible(
                    child: Text(
                      [_statusLabel(status), ?retryText].join(' • '),
                      style: AppTextStyles.caption(isDarkMode: isDarkMode)
                          .copyWith(
                            color: status == 'failed'
                                ? Colors.red
                                : status == 'paused'
                                ? Colors.orange
                                : status == 'downloading' ||
                                      status == 'preparing'
                                ? accentColor
                                : textColor.withValues(
                                    alpha: AppDimens.opacityMuted,
                                  ),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: AppDimens.spacingSm),
                LinearProgressIndicator(
                  value: progress.progress,
                  backgroundColor: isDarkMode
                      ? Colors.grey[800]
                      : Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  borderRadius: BorderRadius.circular(AppDimens.radiusXxs),
                ),
                const SizedBox(height: AppDimens.spacingXs),
                Text(
                  '${(progress.progress * 100).toInt()}%',
                  style: AppTextStyles.caption(isDarkMode: isDarkMode).copyWith(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
              if (status == 'failed' && error != null && error.isNotEmpty) ...[
                const SizedBox(height: AppDimens.spacingXs),
                Text(
                  error,
                  style: AppTextStyles.caption(
                    isDarkMode: isDarkMode,
                    color: Colors.red,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == 'downloading' ||
                  status == 'preparing' ||
                  status == 'queued')
                IconButton(
                  icon: Icon(
                    Icons.pause_circle_outline,
                    color: MainScreenColors.getTextColor(isDarkMode),
                  ),
                  tooltip: 'pause_download'.tr(),
                  onPressed: () => downloadProvider.pauseDownload(videoId),
                ),
              if (status == 'paused')
                IconButton(
                  icon: Icon(Icons.play_circle_outline, color: accentColor),
                  tooltip: 'resume_download'.tr(),
                  onPressed: () => downloadProvider.resumeDownload(videoId),
                ),
              if (status == 'failed')
                IconButton(
                  icon: Icon(Icons.refresh, color: accentColor),
                  tooltip: 'retry_download'.tr(),
                  onPressed: () => downloadProvider.retryDownload(videoId),
                ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: MainScreenColors.getTextColor(isDarkMode),
                ),
                tooltip: 'cancel_download'.tr(),
                onPressed: () => downloadProvider.cancelDownload(videoId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'downloading':
      case 'preparing':
        return Icons.downloading_rounded;
      case 'paused':
        return Icons.pause_circle_outline;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.schedule_rounded;
    }
  }

  // ---------------------------------------------------------------------
  // Downloaded actions
  // ---------------------------------------------------------------------

  Future<void> _playDownloaded({
    required bool shuffle,
    required List<Map<String, dynamic>> songs,
  }) async {
    if (songs.isEmpty) return;

    final playerProvider = context.read<PlayerProvider>();
    final queueProvider = context.read<QueueProvider>();
    final songInfos = songs.map(_convertToSongInfo).toList();
    if (shuffle) songInfos.shuffle();

    try {
      await ContentDetailsService().playSong(
        songInfos.first,
        playerProvider,
        queueProvider,
        songInfos,
        playlistId: 'downloads',
        playlistName: 'Downloads',
      );
      queueProvider.setQueue(
        songInfos,
        currentIndex: 0,
        playlistId: 'downloads',
        playlistName: 'Downloads',
      );
      await queueProvider.saveQueue();
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'failed_to_play_song_error'.tr());
      }
    }
  }

  Future<void> _playSong(
    Map<String, dynamic> song,
    DownloadProvider downloadProvider,
    PlayerProvider playerProvider,
    QueueProvider queueProvider,
  ) async {
    try {
      final songInfo = _convertToSongInfo(song);

      final allDownloadedSongs = downloadProvider.downloadedSongs
          .map(_convertToSongInfo)
          .toList();

      final contentDetailsService = ContentDetailsService();
      await contentDetailsService.playSong(
        songInfo,
        playerProvider,
        queueProvider,
        allDownloadedSongs,
        playlistId: 'downloads',
        playlistName: 'Downloads',
      );
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'failed_to_play_song_error'.tr());
      }
    }
  }

  Future<void> _openFile(Map<String, dynamic> song) async {
    final path = (song['localPath'] ?? song['filePath']) as String?;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      if (mounted) {
        AppSnackBar.showError(context, 'failed_to_play_song_error'.tr());
      }
      return;
    }
    try {
      final opened = await launchUrl(Uri.file(path));
      if (!opened && mounted) {
        AppSnackBar.showError(context, 'open_file'.tr());
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'open_file'.tr());
      }
    }
  }

  Future<void> _shareFile(Map<String, dynamic> song) async {
    final path = (song['localPath'] ?? song['filePath']) as String?;
    final title = (song['title'] as String?) ?? '';
    final artist = (song['artist'] as String?) ?? '';
    final text = artist.isEmpty ? title : '$title - $artist';

    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: text),
      );
      return;
    }
    await SharePlus.instance.share(ShareParams(text: text));
  }

  /// Opens the artist page when the download entry carries an artist id;
  /// otherwise the option is inert (context-aware navigation).
  void _goToArtist(Map<String, dynamic> song) {
    final artistId = (song['artistId'] as String?) ?? '';
    if (artistId.isEmpty) return;
    final thumbUrl = (song['thumbnail'] as String?) ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContentRouter(
          content: ArtistDetailed(
            artistId: artistId,
            name: (song['artist'] as String?) ?? '',
            thumbnails: [ThumbnailFull(url: thumbUrl, width: 0, height: 0)],
            type: '',
          ),
        ),
      ),
    );
  }

  void _showSongOptions(Map<String, dynamic> song, bool isDarkMode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: SongOptionsBottomSheet(
          song: _convertToSongInfo(song),
          isDarkMode: isDarkMode,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDownloadedSong(Map<String, dynamic> song) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: glassDialogColor(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
          ),
          title: Text(
            'delete_songs'.tr(),
            style: AppTextStyles.titleSm(isDarkMode: isDarkMode).copyWith(
              fontWeight: AppTextStyles.weightBold,
              color: MainScreenColors.getTextColor(isDarkMode),
            ),
          ),
          content: Text(
            'are_you_sure_you_want_to_delete_selected_songs'.tr(args: ['1']),
            style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'cancel'.tr(),
                style: AppTextStyles.button(
                  color: MainScreenColors.getTextColor(isDarkMode),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: Text(
                'delete'.tr(),
                style: AppTextStyles.button(color: Colors.red),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final downloadProvider = context.read<DownloadProvider>();
      await downloadProvider.deleteDownloadedSong(song['id']);
      if (mounted) {
        AppSnackBar.showInfo(context, 'removed_from_downloads'.tr());
      }
    }
  }

  // ---------------------------------------------------------------------
  // Storage & settings
  // ---------------------------------------------------------------------

  void _showStorageInfoSheet(bool isDarkMode) {
    final downloadProvider = context.read<DownloadProvider>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final textColor = MainScreenColors.getTextColor(isDarkMode);
        return GlassSheet(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.paddingLg,
            AppDimens.paddingLg,
          ),
          child: SafeArea(
            top: false,
            child: FutureBuilder<({String path, int used, int? free})>(
              future: () async {
                final path = await downloadProvider.getDownloadDirectoryPath();
                final used = await downloadProvider.getTotalDownloadedBytes();
                final free = await downloadProvider.getFreeDiskSpaceBytes();
                return (path: path, used: used, free: free);
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(AppDimens.paddingXl),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return Padding(
                    padding: const EdgeInsets.all(AppDimens.paddingXl),
                    child: Text(
                      'storage_free'.tr(),
                      style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'downloads_storage'.tr(),
                      style: AppTextStyles.titleSm(
                        isDarkMode: isDarkMode,
                      ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
                    ),
                    const SizedBox(height: AppDimens.spacingMd),
                    _storageRow(
                      Icons.folder_open_rounded,
                      'storage_location'.tr(),
                      data.path,
                      isDarkMode,
                      textColor,
                    ),
                    _storageRow(
                      Icons.sd_storage_rounded,
                      'storage_used'.tr(),
                      _fmtBytes(data.used),
                      isDarkMode,
                      textColor,
                    ),
                    _storageRow(
                      Icons.storage_rounded,
                      'storage_free'.tr(),
                      data.free != null ? _fmtBytes(data.free!) : '—',
                      isDarkMode,
                      textColor,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _storageRow(
    IconData icon,
    String label,
    String value,
    bool isDarkMode,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: AppDimens.iconMd,
            color: textColor.withValues(alpha: AppDimens.opacityMuted),
          ),
          const SizedBox(width: AppDimens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption(isDarkMode: isDarkMode).copyWith(
                    color: textColor.withValues(alpha: AppDimens.opacityMuted),
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Shared UI pieces
  // ---------------------------------------------------------------------

  Widget _buildThumbnail(String thumbnailUrl, bool isDarkMode) {
    return CachedNetworkImage(
      imageUrl: thumbnailUrl,
      width: AppDimens.thumbnailDefault,
      height: AppDimens.thumbnailDefault,
      fit: BoxFit.cover,
      placeholder: (context, url) => Image.asset(
        'assets/default_artwork.png',
        width: AppDimens.thumbnailDefault,
        height: AppDimens.thumbnailDefault,
        fit: BoxFit.cover,
      ),
      errorWidget: (context, url, error) => Container(
        width: AppDimens.thumbnailDefault,
        height: AppDimens.thumbnailDefault,
        color: isDarkMode ? Colors.grey[850] : Colors.grey[300],
        child: const Icon(Icons.error),
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required bool isDarkMode,
    required Color accentColor,
    required VoidCallback onClear,
  }) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.spacingXs,
        AppDimens.paddingLg,
        AppDimens.spacingSm,
      ),
      child: TextField(
        controller: controller,
        autofocus: false,
        onChanged: (_) => setState(() {}),
        style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.bodyMd(
            isDarkMode: isDarkMode,
            color: textColor.withValues(alpha: AppDimens.opacityMuted),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: textColor.withValues(alpha: AppDimens.opacityMuted),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.close,
              color: textColor.withValues(alpha: AppDimens.opacityMuted),
            ),
            onPressed: onClear,
          ),
          filled: true,
          fillColor: MainScreenColors.getSurfaceColor(isDarkMode),
          contentPadding: const EdgeInsets.symmetric(
            vertical: AppDimens.paddingSm,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            borderSide: BorderSide(color: accentColor, width: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    String message, {
    required bool isDarkMode,
    required Color accentColor,
    IconData icon = Icons.cloud_download_outlined,
  }) {
    return AppEmptyState(
      icon: icon,
      title: message,
      isDarkMode: isDarkMode,
      accentColor: accentColor,
    );
  }

  // ---------------------------------------------------------------------
  // Queue tab
  // ---------------------------------------------------------------------

  /// One-tap recovery for a batch of failed downloads. Rendered above the
  /// queue list so it is reachable from both the mobile tab and the desktop
  /// column, and only while at least one entry is actually failed.
  Widget _buildRetryAllFailedBanner(Color accentColor, int failedCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.spacingXs,
        AppDimens.paddingLg,
        AppDimens.spacingSm,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _retryAllFailed(failedCount),
          style: FilledButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: AppDimens.paddingMd),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusMdLg),
            ),
          ),
          icon: const Icon(Icons.refresh_rounded, size: AppDimens.iconMd),
          label: Text(
            'retry_all_failed'.tr(args: ['$failedCount']),
            style: AppTextStyles.button(
              color: Colors.black,
            ).copyWith(fontWeight: AppTextStyles.weightBold),
          ),
        ),
      ),
    );
  }

  Future<void> _retryAllFailed(int failedCount) async {
    final downloadProvider = context.read<DownloadProvider>();
    await downloadProvider.retryAllFailed();
    if (!mounted) return;
    AppSnackBar.showSuccess(
      context,
      'retry_all_failed_started'.tr(args: ['$failedCount']),
      accentColor: context.read<SettingsProvider>().accentColor,
    );
  }

  Widget _buildQueueList(bool isDarkMode, Color accentColor) {
    final downloadProvider = context.watch<DownloadProvider>();
    final items = _filteredQueue(downloadProvider);
    final failedCount = downloadProvider.downloadQueue
        .where((song) => song['status'] == 'failed')
        .length;

    return Column(
      children: [
        if (_showQueueSearch)
          _buildSearchField(
            controller: _queueSearchController,
            hint: 'search_queue'.tr(),
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            onClear: () {
              _queueSearchController.clear();
              setState(() {});
            },
          ),
        if (failedCount > 0)
          _buildRetryAllFailedBanner(accentColor, failedCount),
        Expanded(
          child: RefreshIndicator(
            color: accentColor,
            onRefresh: downloadProvider.loadDownloadQueue,
            child: items.isEmpty
                ? (_queueSearchController.text.trim().isEmpty
                      ? _buildEmptyState(
                          'no_songs_in_queue'.tr(),
                          isDarkMode: isDarkMode,
                          accentColor: accentColor,
                        )
                      : _buildEmptyState(
                          'no_matches'.tr(),
                          isDarkMode: isDarkMode,
                          accentColor: accentColor,
                          icon: Icons.search_off_rounded,
                        ))
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _buildQueueItem(
                      items[index],
                      downloadProvider,
                      accentColor,
                      isDarkMode,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Downloaded tab
  // ---------------------------------------------------------------------

  Widget _buildDownloadedHeaderActions(
    bool isDarkMode,
    Color accentColor,
    List<Map<String, dynamic>> items,
  ) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.play_arrow_rounded, color: textColor),
          tooltip: 'play_all'.tr(),
          onPressed: items.isEmpty
              ? null
              : () => _playDownloaded(shuffle: false, songs: items),
        ),
        IconButton(
          icon: Icon(Icons.shuffle_rounded, color: textColor),
          tooltip: 'shuffle'.tr(),
          onPressed: items.isEmpty
              ? null
              : () => _playDownloaded(shuffle: true, songs: items),
        ),
        PopupMenuButton<_ClearAction>(
          icon: Icon(Icons.delete_sweep_rounded, color: textColor),
          tooltip: 'clear_all'.tr(),
          onSelected: (action) => _runClearAction(action, isDarkMode),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ClearAction.completed,
              child: Text('clear_completed'.tr()),
            ),
            PopupMenuItem(
              value: _ClearAction.all,
              child: Text('clear_all_downloads'.tr()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadedSongItem(
    Map<String, dynamic> song,
    bool isDarkMode,
    Color accentColor,
  ) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);
    final songInfo = _convertToSongInfo(song);
    final playerProvider = context.watch<PlayerProvider>();
    final bool isPlaying =
        playerProvider.currentSong?.videoId == songInfo.videoId ||
        playerProvider.lastPlayedSong?.videoId == songInfo.videoId;
    final videoId = song['id'] as String? ?? '';
    final isSelected = _selectedSongs.contains(videoId);
    final path = (song['localPath'] ?? song['filePath']) as String?;
    final hasFile = path != null && File(path).existsSync();
    final artistId = (song['artistId'] as String?) ?? '';

    final size = _sizeOf(song);
    final timestamp = _getSongTimestamp(song);
    final duration = Duration(
      seconds: (song['duration'] as num?)?.toInt() ?? 0,
    );

    final metaParts = <String>[
      if (duration.inSeconds > 0) _fmtDuration(duration),
      if (size > 0) _fmtBytes(size),
      if (timestamp > 0) _fmtDate(timestamp),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDimens.paddingSm,
        vertical: AppDimens.spacingXxs,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? MainScreenColors.primaryPurple.withValues(alpha: 0.2)
            : (isPlaying
                  ? MainScreenColors.primaryPurple.withValues(alpha: 0.12)
                  : Colors.transparent),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.all(AppDimens.paddingSm),
          leading: _isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value ?? false) {
                        _selectedSongs.add(videoId);
                      } else {
                        _selectedSongs.remove(videoId);
                        if (_selectedSongs.isEmpty) _isSelectionMode = false;
                      }
                    });
                  },
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? accentColor
                        : Colors.grey,
                  ),
                  checkColor: textColor,
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                      child: _buildThumbnail(
                        song['thumbnail'] ?? '',
                        isDarkMode,
                      ),
                    ),
                    if (isPlaying)
                      Container(
                        width: AppDimens.thumbnailDefault,
                        height: AppDimens.thumbnailDefault,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusSm,
                          ),
                        ),
                        child: Icon(Icons.equalizer, color: accentColor),
                      ),
                  ],
                ),
          title: Text(
            song['title'] ?? '',
            style: AppTextStyles.queueItem(
              isDarkMode: isDarkMode,
            ).copyWith(color: isPlaying ? accentColor : textColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song['artist'] ?? '',
                style: AppTextStyles.settingsSubtitle(isDarkMode: isDarkMode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (metaParts.isNotEmpty)
                Text(
                  metaParts.join(' • '),
                  style: AppTextStyles.caption(isDarkMode: isDarkMode).copyWith(
                    color: textColor.withValues(alpha: AppDimens.opacityMuted),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          trailing: _isSelectionMode
              ? null
              : PopupMenuButton<_DownloadedAction>(
                  icon: Icon(Icons.more_vert, color: textColor),
                  tooltip: 'song_options'.tr(),
                  onSelected: (action) {
                    switch (action) {
                      case _DownloadedAction.options:
                        _showSongOptions(song, isDarkMode);
                        break;
                      case _DownloadedAction.openFile:
                        _openFile(song);
                        break;
                      case _DownloadedAction.shareFile:
                        _shareFile(song);
                        break;
                      case _DownloadedAction.goToArtist:
                        _goToArtist(song);
                        break;
                      case _DownloadedAction.delete:
                        _confirmDeleteDownloadedSong(song);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _DownloadedAction.options,
                      child: Text('song_options'.tr()),
                    ),
                    PopupMenuItem(
                      value: _DownloadedAction.openFile,
                      enabled: hasFile,
                      child: Text('open_file'.tr()),
                    ),
                    PopupMenuItem(
                      value: _DownloadedAction.shareFile,
                      child: Text('share_file'.tr()),
                    ),
                    PopupMenuItem(
                      value: _DownloadedAction.goToArtist,
                      enabled: artistId.isNotEmpty,
                      child: Text('go_to_artist'.tr()),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _DownloadedAction.delete,
                      child: Text(
                        'remove_from_downloads'.tr(),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
          onTap: () {
            if (_isSelectionMode) {
              setState(() {
                if (_selectedSongs.contains(videoId)) {
                  _selectedSongs.remove(videoId);
                  if (_selectedSongs.isEmpty) _isSelectionMode = false;
                } else {
                  _selectedSongs.add(videoId);
                }
              });
              return;
            }
            final downloadProvider = context.read<DownloadProvider>();
            final playerProvider = context.read<PlayerProvider>();
            final queueProvider = context.read<QueueProvider>();
            _playSong(song, downloadProvider, playerProvider, queueProvider);
          },
          onLongPress: _isSelectionMode
              ? null
              : () {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedSongs.add(videoId);
                  });
                },
        ),
      ),
    );
  }

  Widget _buildDownloadedList(
    bool isDarkMode,
    Color accentColor, {
    bool showHeader = true,
  }) {
    final downloadProvider = context.watch<DownloadProvider>();
    final items = _filteredDownloaded(downloadProvider);
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.paddingLg,
              vertical: AppDimens.spacingXs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${'downloaded'.tr()} (${items.length})',
                    style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_isSelectionMode)
                  _buildDownloadedHeaderActions(isDarkMode, accentColor, items),
              ],
            ),
          ),
        if (_showDownloadedSearch)
          _buildSearchField(
            controller: _downloadedSearchController,
            hint: 'search_downloads'.tr(),
            isDarkMode: isDarkMode,
            accentColor: accentColor,
            onClear: () {
              _downloadedSearchController.clear();
              setState(() {});
            },
          ),
        Expanded(
          child: RefreshIndicator(
            color: accentColor,
            onRefresh: downloadProvider.loadDownloadedSongs,
            child: items.isEmpty
                ? (_downloadedSearchController.text.trim().isEmpty
                      ? _buildEmptyState(
                          'no_songs_in_downloads'.tr(),
                          isDarkMode: isDarkMode,
                          accentColor: accentColor,
                        )
                      : _buildEmptyState(
                          'no_matches'.tr(),
                          isDarkMode: isDarkMode,
                          accentColor: accentColor,
                          icon: Icons.search_off_rounded,
                        ))
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: AppDimens.spacingLg),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _buildDownloadedSongItem(
                      items[index],
                      isDarkMode,
                      accentColor,
                    ),
                  ),
          ),
        ),
        if (!_isSelectionMode)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.paddingLg,
              vertical: AppDimens.spacingXs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: AppDimens.iconSm,
                  color: textColor.withValues(alpha: AppDimens.opacityMuted),
                ),
                const SizedBox(width: AppDimens.spacingSm),
                Expanded(
                  child: Text(
                    '${'storage_used'.tr()}: ${_fmtBytes(_downloadedBytes)}',
                    style: AppTextStyles.caption(isDarkMode: isDarkMode)
                        .copyWith(
                          color: textColor.withValues(
                            alpha: AppDimens.opacityMuted,
                          ),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Clear actions
  // ---------------------------------------------------------------------

  Future<void> _runClearAction(_ClearAction action, bool isDarkMode) async {
    final downloadProvider = context.read<DownloadProvider>();

    String? message;
    String doneMessage;
    Future<void> Function() run;
    switch (action) {
      case _ClearAction.queue:
        message = 'confirm_clear_queue'.tr();
        doneMessage = 'queue_cleared_success'.tr();
        run = downloadProvider.clearQueue;
        break;
      case _ClearAction.completed:
        doneMessage = 'removed_from_downloads'.tr();
        run = downloadProvider.clearCompletedDownloads;
        break;
      case _ClearAction.all:
        message = 'confirm_clear_downloads'.tr();
        doneMessage = 'removed_from_downloads'.tr();
        run = downloadProvider.clearAllDownloads;
        break;
    }

    if (message != null) {
      final confirmed = await showGlassDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            backgroundColor: glassDialogColor(dialogContext),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            ),
            title: Text(
              'clear_all'.tr(),
              style: AppTextStyles.titleSm(isDarkMode: isDarkMode).copyWith(
                fontWeight: AppTextStyles.weightBold,
                color: MainScreenColors.getTextColor(isDarkMode),
              ),
            ),
            content: Text(
              message!,
              style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(
                  'cancel'.tr(),
                  style: AppTextStyles.button(
                    color: MainScreenColors.getTextColor(isDarkMode),
                  ),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(
                child: Text(
                  'clear'.tr(),
                  style: AppTextStyles.button(color: Colors.red),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }

    await run();
    if (mounted) {
      AppSnackBar.showInfo(context, doneMessage);
    }
  }

  // ---------------------------------------------------------------------
  // Headers, app bar, build
  // ---------------------------------------------------------------------

  Widget _buildDesktopColumnHeader({
    required String title,
    required bool isDarkMode,
    required List<Widget> actions,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.paddingLg,
        AppDimens.spacingSm,
        AppDimens.paddingLg,
        AppDimens.spacingSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.titleSm(
                isDarkMode: isDarkMode,
              ).copyWith(fontWeight: AppTextStyles.weightSemiBold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _buildDesktopQueueColumn(bool isDarkMode, Color accentColor) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);
    final downloadProvider = context.watch<DownloadProvider>();
    final count = _filteredQueue(downloadProvider).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDesktopColumnHeader(
          title: '${'queue'.tr()} ($count)',
          isDarkMode: isDarkMode,
          actions: [
            IconButton(
              icon: Icon(
                Icons.search,
                color: _showQueueSearch
                    ? accentColor
                    : MainScreenColors.getTextColor(isDarkMode),
              ),
              tooltip: 'search_queue'.tr(),
              onPressed: () =>
                  setState(() => _showQueueSearch = !_showQueueSearch),
            ),
            PopupMenuButton<QueueSortOption>(
              icon: Icon(Icons.sort, color: textColor),
              tooltip: 'sort_status'.tr(),
              initialValue: _queueSort,
              onSelected: (value) => setState(() => _queueSort = value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: QueueSortOption.status,
                  child: Text('sort_status'.tr()),
                ),
                PopupMenuItem(
                  value: QueueSortOption.titleAsc,
                  child: Text('sort_title_az'.tr()),
                ),
                PopupMenuItem(
                  value: QueueSortOption.titleDesc,
                  child: Text('sort_title_za'.tr()),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                downloadProvider.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                color: textColor,
              ),
              tooltip: downloadProvider.isPaused
                  ? 'resume_downloads'.tr()
                  : 'pause_downloads'.tr(),
              onPressed: downloadProvider.downloadQueue.isEmpty
                  ? null
                  : _toggleAllDownloads,
            ),
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: textColor),
              tooltip: 'clear_all'.tr(),
              onPressed: downloadProvider.downloadQueue.isEmpty
                  ? null
                  : () => _runClearAction(_ClearAction.queue, isDarkMode),
            ),
          ],
        ),
        Expanded(child: _buildQueueList(isDarkMode, accentColor)),
      ],
    );
  }

  Widget _buildDesktopDownloadedColumn(bool isDarkMode, Color accentColor) {
    final textColor = MainScreenColors.getTextColor(isDarkMode);
    final downloadProvider = context.watch<DownloadProvider>();
    final count = _filteredDownloaded(downloadProvider).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDesktopColumnHeader(
          title: '${'downloaded'.tr()} ($count)',
          isDarkMode: isDarkMode,
          actions: [
            IconButton(
              icon: Icon(Icons.play_arrow_rounded, color: textColor),
              tooltip: 'play_all'.tr(),
              onPressed: () => _playDownloaded(
                shuffle: false,
                songs: _filteredDownloaded(downloadProvider),
              ),
            ),
            IconButton(
              icon: Icon(Icons.shuffle_rounded, color: textColor),
              tooltip: 'shuffle'.tr(),
              onPressed: () => _playDownloaded(
                shuffle: true,
                songs: _filteredDownloaded(downloadProvider),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.search,
                color: _showDownloadedSearch
                    ? accentColor
                    : MainScreenColors.getTextColor(isDarkMode),
              ),
              tooltip: 'search_downloads'.tr(),
              onPressed: () => setState(
                () => _showDownloadedSearch = !_showDownloadedSearch,
              ),
            ),
            PopupMenuButton<DownloadedSortOption>(
              icon: Icon(Icons.sort, color: textColor),
              tooltip: 'file_size'.tr(),
              initialValue: _downloadedSort,
              onSelected: (value) => setState(() => _downloadedSort = value),
              itemBuilder: (context) => _downloadedSortMenuItems(),
            ),
            PopupMenuButton<_ClearAction>(
              icon: Icon(Icons.delete_sweep_rounded, color: textColor),
              tooltip: 'clear_all'.tr(),
              onSelected: (action) => _runClearAction(action, isDarkMode),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _ClearAction.completed,
                  child: Text('clear_completed'.tr()),
                ),
                PopupMenuItem(
                  value: _ClearAction.all,
                  child: Text('clear_all_downloads'.tr()),
                ),
              ],
            ),
          ],
        ),
        Expanded(
          child: _buildDownloadedList(
            isDarkMode,
            accentColor,
            showHeader: false,
          ),
        ),
      ],
    );
  }

  List<PopupMenuEntry<DownloadedSortOption>> _downloadedSortMenuItems() {
    return [
      PopupMenuItem(
        value: DownloadedSortOption.titleAsc,
        child: Text('sort_title_az'.tr()),
      ),
      PopupMenuItem(
        value: DownloadedSortOption.titleDesc,
        child: Text('sort_title_za'.tr()),
      ),
      PopupMenuItem(
        value: DownloadedSortOption.artistAsc,
        child: Text('sort_artist_az'.tr()),
      ),
      PopupMenuItem(
        value: DownloadedSortOption.artistDesc,
        child: Text('sort_artist_za'.tr()),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: DownloadedSortOption.dateDesc,
        child: Text('sort_date_newest_first'.tr()),
      ),
      PopupMenuItem(
        value: DownloadedSortOption.dateAsc,
        child: Text('sort_date_oldest_first'.tr()),
      ),
      PopupMenuItem(
        value: DownloadedSortOption.fileSizeDesc,
        child: Text('file_size'.tr()),
      ),
    ];
  }

  List<PopupMenuEntry<QueueSortOption>> _queueSortMenuItems() {
    return [
      PopupMenuItem(
        value: QueueSortOption.status,
        child: Text('sort_status'.tr()),
      ),
      PopupMenuItem(
        value: QueueSortOption.titleAsc,
        child: Text('sort_title_az'.tr()),
      ),
      PopupMenuItem(
        value: QueueSortOption.titleDesc,
        child: Text('sort_title_za'.tr()),
      ),
    ];
  }

  List<PopupMenuEntry<_ClearAction>> _clearMenuItems() {
    return [
      PopupMenuItem(value: _ClearAction.queue, child: Text('clear_queue'.tr())),
      PopupMenuItem(
        value: _ClearAction.completed,
        child: Text('clear_completed'.tr()),
      ),
      PopupMenuItem(
        value: _ClearAction.all,
        child: Text('clear_all_downloads'.tr()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.theme == 'Dark';
    final accentColor = settingsProvider.accentColor;
    final isDesktopLayout = !AppDimens.isMobile(context);
    final textColor = MainScreenColors.getTextColor(isDarkMode);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() {
            _selectedSongs.clear();
            _isSelectionMode = false;
          });
        }
      },
      child: SafeArea(
        top: false,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              _isSelectionMode
                  ? '${_selectedSongs.length} selected'
                  : 'downloads'.tr(),
              style: AppTextStyles.appBarTitle(isDarkMode: isDarkMode),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            actions: [
              if (_isSelectionMode) ...[
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _deleteSelected(isDarkMode),
                ),
                Consumer<DownloadProvider>(
                  builder: (context, downloadProvider, _) {
                    final allSongIds = downloadProvider.downloadedSongs
                        .map((song) => song['id'] as String?)
                        .where((id) => id != null && id.isNotEmpty)
                        .cast<String>()
                        .toSet();
                    final isAllSelected =
                        allSongIds.isNotEmpty &&
                        _selectedSongs.containsAll(allSongIds) &&
                        _selectedSongs.length == allSongIds.length;

                    return IconButton(
                      icon: Icon(
                        isAllSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        color: textColor,
                      ),
                      tooltip: isAllSelected
                          ? 'unselect_all'.tr()
                          : 'select_all'.tr(),
                      onPressed: () => _toggleSelectAll(downloadProvider),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedSongs.clear();
                      _isSelectionMode = false;
                    });
                  },
                ),
              ] else ...[
                if (!isDesktopLayout) ...[
                  Consumer<DownloadProvider>(
                    builder: (context, downloadProvider, _) {
                      if (downloadProvider.downloadQueue.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final isPaused = downloadProvider.isPaused;
                      return IconButton(
                        icon: Icon(
                          isPaused ? Icons.play_arrow : Icons.pause,
                          color: textColor,
                        ),
                        tooltip: isPaused
                            ? 'resume_downloads'.tr()
                            : 'pause_downloads'.tr(),
                        onPressed: _toggleAllDownloads,
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.search, color: textColor),
                    tooltip: 'search'.tr(),
                    onPressed: () {
                      setState(() {
                        if (_tabController.index == 0) {
                          _showQueueSearch = !_showQueueSearch;
                        } else {
                          _showDownloadedSearch = !_showDownloadedSearch;
                        }
                      });
                    },
                  ),
                  if (_tabController.index == 1)
                    PopupMenuButton<DownloadedSortOption>(
                      icon: Icon(Icons.sort, color: textColor),
                      onSelected: (value) =>
                          setState(() => _downloadedSort = value),
                      itemBuilder: (context) => _downloadedSortMenuItems(),
                    )
                  else
                    PopupMenuButton<QueueSortOption>(
                      icon: Icon(Icons.sort, color: textColor),
                      onSelected: (value) => setState(() => _queueSort = value),
                      itemBuilder: (context) => _queueSortMenuItems(),
                    ),
                ],
                IconButton(
                  icon: Icon(Icons.storage_rounded, color: textColor),
                  tooltip: 'storage_location'.tr(),
                  onPressed: () => _showStorageInfoSheet(isDarkMode),
                ),
                IconButton(
                  icon: Icon(Icons.tune_rounded, color: textColor),
                  tooltip: 'download_settings'.tr(),
                  onPressed: () => DownloadSettingsSheet.show(context),
                ),
                if (!isDesktopLayout)
                  PopupMenuButton<_ClearAction>(
                    icon: Icon(Icons.more_vert, color: textColor),
                    tooltip: 'clear_all'.tr(),
                    onSelected: (action) => _runClearAction(action, isDarkMode),
                    itemBuilder: (context) => _clearMenuItems(),
                  ),
              ],
            ],
            bottom: isDesktopLayout
                ? null
                : TabBar(
                    controller: _tabController,
                    indicatorColor: accentColor,
                    labelColor: accentColor,
                    unselectedLabelColor: textColor.withValues(alpha: 0.7),
                    labelStyle: AppTextStyles.subtitle(isDarkMode: isDarkMode),
                    tabs: [
                      Tab(text: 'queue'.tr()),
                      Tab(text: 'downloaded'.tr()),
                    ],
                  ),
          ),
          body: Consumer<PlayerProvider>(
            builder: (context, playerProvider, _) {
              final hasPlayer =
                  playerProvider.currentSong != null ||
                  playerProvider.lastPlayedSong != null;

              final mq = MediaQuery.of(context);
              final double textScale = mq.textScaler.scale(1.0);
              final double navIconScale = textScale > 1.0
                  ? (1.0 / textScale).clamp(0.75, 1.0).toDouble()
                  : 1.0;

              return Stack(
                children: [
                  isDesktopLayout
                      ? Row(
                          children: [
                            Expanded(
                              child: _buildDesktopQueueColumn(
                                isDarkMode,
                                accentColor,
                              ),
                            ),
                            VerticalDivider(
                              width: 1,
                              color: isDarkMode
                                  ? Colors.grey[800]
                                  : Colors.grey[300],
                            ),
                            Expanded(
                              child: _buildDesktopDownloadedColumn(
                                isDarkMode,
                                accentColor,
                              ),
                            ),
                          ],
                        )
                      : Padding(
                          padding: EdgeInsets.only(
                            bottom: hasPlayer
                                ? AppDimens.miniPlayerHeight * navIconScale
                                : 0,
                          ),
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildQueueList(isDarkMode, accentColor),
                              _buildDownloadedList(isDarkMode, accentColor),
                            ],
                          ),
                        ),

                  if (!isDesktopLayout && hasPlayer)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).appBarTheme.backgroundColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppDimens.radiusMd),
                          ),
                        ),
                        child: SizedBox(
                          height: AppDimens.miniPlayerHeight * navIconScale,
                          child: PlayerUI(
                            showFullScreen: false,
                            isEmbedded: true,
                            onMinimize: () {},
                            onExpand: () => _showFullPlayerBottomSheet(context),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showFullPlayerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) => const FullPlayerScreen(),
    );
  }

  void _toggleSelectAll(DownloadProvider downloadProvider) {
    final allSongIds = downloadProvider.downloadedSongs
        .map((song) => song['id'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toSet();
    final isAllSelected =
        allSongIds.isNotEmpty &&
        _selectedSongs.containsAll(allSongIds) &&
        _selectedSongs.length == allSongIds.length;

    setState(() {
      if (isAllSelected) {
        _selectedSongs.clear();
        _isSelectionMode = false;
      } else {
        _selectedSongs = allSongIds;
        if (allSongIds.isNotEmpty) _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelected(bool isDarkMode) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: glassDialogColor(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
          ),
          title: Text(
            'delete_songs'.tr(),
            style: AppTextStyles.titleSm(isDarkMode: isDarkMode).copyWith(
              fontWeight: AppTextStyles.weightBold,
              color: MainScreenColors.getTextColor(isDarkMode),
            ),
          ),
          content: Text(
            'are_you_sure_you_want_to_delete_selected_songs'.tr(
              args: [_selectedSongs.length.toString()],
            ),
            style: AppTextStyles.bodyMd(isDarkMode: isDarkMode),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'cancel'.tr(),
                style: AppTextStyles.button(
                  color: MainScreenColors.getTextColor(isDarkMode),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: Text(
                'delete'.tr(),
                style: AppTextStyles.button(color: Colors.red),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final downloadProvider = context.read<DownloadProvider>();
    for (final songId in _selectedSongs) {
      await downloadProvider.deleteDownloadedSong(songId);
    }

    if (mounted) {
      AppSnackBar.showInfo(context, 'removed_from_downloads'.tr());
      setState(() {
        _selectedSongs.clear();
        _isSelectionMode = false;
      });
    }
  }
}

enum _DownloadedAction { options, openFile, shareFile, goToArtist, delete }

enum _ClearAction { queue, completed, all }
