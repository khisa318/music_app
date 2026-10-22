import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/models/song_model.dart';
import '../widgets/playlist_album_content_shimmer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/glass_modal.dart';
import '../../../../shared/components/song_list_tile.dart';
import '../../../playlists/data/providers/playlist_album_library_provider.dart';
import '../../../../core/providers/player_provider.dart';
import '../../../../core/providers/queued_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/providers/download_provider.dart' as dp;
import '../../../../core/services/related_song_service.dart';
import '../../data/providers/playlist_album_content_provider.dart';
import '../../data/models/local_playlist_content.dart';
import '../widgets/search_song_delegate.dart';
import '../../../../shared/components/app_snackbar.dart';

class PlaylistAlbumContent extends StatefulWidget {
  final dynamic content;

  const PlaylistAlbumContent({super.key, required this.content});

  @override
  State<PlaylistAlbumContent> createState() => _PlaylistAlbumContentState();
}

class _PlaylistAlbumContentState extends State<PlaylistAlbumContent> {
  final ScrollController _scrollController = ScrollController();
  late PlaylistAlbumContentProvider _provider;
  late final PlaylistAlbumLibraryProvider _libraryProvider;
  bool _isLocal = false;
  String _playlistName = '';
  final RelatedSongService _relatedSongService = RelatedSongService();
  List<SongInfo> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _hasLoadedSuggestions = false;

  @override
  void initState() {
    super.initState();
    _provider = PlaylistAlbumContentProvider();
    _provider.addListener(_onProviderChanged);
    _libraryProvider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );
    _isLocal = widget.content is LocalPlaylistContent;
    if (_isLocal) {
      _playlistName = (widget.content as LocalPlaylistContent).playlistName;
      _libraryProvider.addListener(_onLibraryChanged);
    }
    _provider.loadContent(widget.content, libraryProvider: _libraryProvider);
    _provider.checkIfSaved(widget.content, _libraryProvider);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeLoadSuggestions(),
    );
  }

  void _onProviderChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeLoadSuggestions();
  }

  /// Local playlists can be written to (removing a song, or a background
  /// Spotify import still filling them in), so re-read them on change.
  void _onLibraryChanged() {
    if (!mounted) return;
    _provider.refreshLocalSongs(_libraryProvider);
  }

  String get _localPlaylistName => _playlistName;

  Future<void> _removeSong(dynamic song) async {
    await _libraryProvider.removeSongFromPlaylist(
      _localPlaylistName,
      song.videoId as String,
    );
    if (!mounted) return;
    AppSnackBar.showInfo(
      context,
      'removed_from_playlist'.tr(),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _addToLibrary() async {
    final libraryProvider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );
    final message = await _provider.addToLibrary(
      widget.content,
      _provider.contentDescription,
      _provider.totalDuration,
      libraryProvider,
    );
    if (!mounted) return;
    setState(() {});
    AppSnackBar.showInfo(
      context,
      message,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _removeFromLibrary() async {
    final libraryProvider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );
    final message = await _provider.removeFromLibrary(
      widget.content,
      _provider.contentDescription,
      libraryProvider,
    );
    if (!mounted) return;
    setState(() {});
    AppSnackBar.showInfo(
      context,
      message,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _playSong(dynamic song) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    final queueProvider = Provider.of<QueueProvider>(context, listen: false);
    try {
      await _provider.playSong(
        song,
        playerProvider,
        queueProvider,
        _provider.allSongs,
        widget.content.playlistId,
      );
    } catch (e) {
      debugPrint('Error playing song: $e');
      if (!mounted) return;
      AppSnackBar.showError(context, 'Error playing song');
    }
  }

  void _shareContent() {
    _provider.shareContent(widget.content, _provider.contentDescription);
  }

  Future<void> _downloadPlaylist() async {
    final downloadProvider = Provider.of<dp.DownloadProvider>(
      context,
      listen: false,
    );
    try {
      await _provider.downloadPlaylist(downloadProvider);
      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        'All songs added to download queue',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        'Failed to add songs to download queue: $e',
      );
    }
  }

  Future<void> _loadMoreSongs() async {
    await _provider.loadMoreSongs();
  }

  Future<void> _renamePlaylist() async {
    final controller = TextEditingController(text: _playlistName);

    final newName = await showGlassDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: glassDialogColor(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Rename playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Playlist name',
              hintText: 'Enter a new name',
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newName == null ||
        newName.isEmpty ||
        newName == _playlistName ||
        !mounted) {
      return;
    }

    try {
      await _libraryProvider.renameCreatedPlaylist(_playlistName, newName);
      final content = widget.content as LocalPlaylistContent;
      if (!mounted) return;
      content.playlistName = newName;
      content.name = newName;
      _playlistName = newName;
      await _libraryProvider.loadCreatedPlaylistsWithThumbnails();
      if (!mounted) return;
      setState(() {});
      AppSnackBar.showSuccess(context, 'Playlist renamed');
    } catch (e) {
      debugPrint('Error renaming playlist: $e');
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        'A playlist with that name already exists',
      );
    }
  }

  Future<void> _setCoverFromTopSong() async {
    try {
      await _libraryProvider.setCoverFromTopSong(_playlistName);
      if (!mounted) return;
      await _libraryProvider.loadCreatedPlaylistsWithThumbnails();
      if (!mounted) return;
      AppSnackBar.showSuccess(context, 'Cover set to top song');
    } catch (e) {
      debugPrint('Error setting cover: $e');
      if (!mounted) return;
      AppSnackBar.showError(context, 'Could not set cover');
    }
  }

  void _maybeLoadSuggestions() {
    if (!mounted ||
        _hasLoadedSuggestions ||
        _provider.isLoading ||
        _provider.songs.isEmpty) {
      return;
    }
    _hasLoadedSuggestions = true;
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final seedId = _provider.songs.last.videoId?.toString() ?? '';
    if (seedId.isEmpty) return;

    setState(() => _loadingSuggestions = true);

    try {
      final related = await _relatedSongService.getRelatedSongs(seedId);
      if (!mounted) return;
      final existingIds = _provider.allSongs
          .map((s) => s.videoId?.toString())
          .whereType<String>()
          .toSet();
      setState(() {
        _suggestions = related
            .where((s) => !existingIds.contains(s.videoId))
            .take(15)
            .toList();
        _loadingSuggestions = false;
      });
    } catch (e) {
      debugPrint('Error loading suggestions: $e');
      if (!mounted) return;
      setState(() => _loadingSuggestions = false);
    }
  }

  Map<String, dynamic> _songInfoToMap(SongInfo song) {
    final artist = song.artists.isNotEmpty ? song.artists.first : null;
    final thumbnail = song.thumbnails.isNotEmpty ? song.thumbnails.first : null;
    return {
      'id': song.videoId,
      'title': song.name,
      'artist': artist?.name ?? '',
      'artistId': artist?.id ?? '',
      'thumbnail': thumbnail?.url ?? '',
      'duration': song.duration.inSeconds,
    };
  }

  Future<void> _addSuggestionToPlaylist(SongInfo song) async {
    final inPlaylist = _provider.allSongs.any(
      (s) => s.videoId?.toString() == song.videoId,
    );
    if (inPlaylist) {
      AppSnackBar.showError(context, 'Already in this playlist');
      return;
    }

    try {
      await _libraryProvider.saveSongToPlaylist(
        _playlistName,
        _songInfoToMap(song),
      );
      if (!mounted) return;
      setState(() {
        _suggestions.removeWhere((s) => s.videoId == song.videoId);
      });
      AppSnackBar.showSuccess(context, 'Added to playlist');
    } catch (e) {
      debugPrint('Error adding suggestion: $e');
      if (!mounted) return;
      AppSnackBar.showError(context, 'Failed to add song');
    }
  }

  Future<void> _playSuggestion(SongInfo song) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    final queueProvider = Provider.of<QueueProvider>(context, listen: false);
    try {
      await _provider.playSong(song, playerProvider, queueProvider, [
        ..._provider.allSongs.cast<SongInfo>(),
        song,
      ], widget.content.playlistId);
    } catch (e) {
      debugPrint('Error playing suggested song: $e');
      if (!mounted) return;
      AppSnackBar.showError(context, 'Error playing song');
    }
  }

  static const double _desktopBreakpoint = AppDimens.breakpointDesktop;

  Widget _buildHeader({bool isDesktop = false}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final double effectiveWidth = isDesktop ? screenWidth * 0.45 : screenWidth;

    final imageSize = isDesktop
        ? AppDimens.headerImageMd
        : (effectiveWidth < AppDimens.breakpointMobile
              ? AppDimens.headerImageSm
              : AppDimens.headerImageMd);

    final TextStyle titleStyle = isDesktop
        ? AppTextStyles.display()
        : (effectiveWidth < AppDimens.breakpointMobile
              ? AppTextStyles.titleLg()
              : AppTextStyles.headingLg());

    final TextStyle subtitleStyle = isDesktop
        ? AppTextStyles.subtitle()
        : (effectiveWidth < AppDimens.breakpointMobile
              ? AppTextStyles.bodyLg()
              : AppTextStyles.subtitle());

    final padding = isDesktop
        ? AppDimens.paddingXl
        : (effectiveWidth < AppDimens.breakpointMobile
              ? AppDimens.paddingMd
              : AppDimens.paddingLg);
    final margin = isDesktop
        ? AppDimens.spacingLg
        : (effectiveWidth < AppDimens.breakpointMobile
              ? AppDimens.spacingSm
              : AppDimens.spacingLg);

    Widget headerContent = Column(
      crossAxisAlignment: isDesktop
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDesktop) ...[
          Hero(
            tag: 'content-image-${widget.content.name}',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppDimens.radiusXl),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radiusXl),
                child: CachedNetworkImage(
                  imageUrl: widget.content.thumbnails.last.url,
                  width: imageSize,
                  height: imageSize,
                  fit: BoxFit.cover,
                  memCacheWidth: (imageSize * 2).toInt(),
                  memCacheHeight: (imageSize * 2).toInt(),
                  placeholder: (context, url) => Container(
                    width: imageSize,
                    height: imageSize,
                    color: Colors.grey[850],
                    child: const Center(
                      child: Icon(
                        Icons.my_library_music,
                        size: AppDimens.iconHero,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: imageSize,
                    height: imageSize,
                    color: Colors.grey[850],
                    child: const Icon(Icons.error, size: AppDimens.iconHero),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: AppDimens.spacingXl),
          Text(
            widget.content.name,
            style: titleStyle.copyWith(
              color: MainScreenColors.getTextColor(isDarkMode),
              height: 1.2,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppDimens.spacingS),
          Text(
            _provider.contentDescription,
            style: subtitleStyle.copyWith(
              color: MainScreenColors.getTextColor(
                isDarkMode,
              ).withValues(alpha: 0.7),
              height: 1.4,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppDimens.spacingXs),
          Text(
            '${_provider.songs.length} songs • ${_provider.formatTotalDuration()}',
            style: subtitleStyle.copyWith(
              color: MainScreenColors.getTextColor(
                isDarkMode,
              ).withValues(alpha: 0.7),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppDimens.spacingXl),
          _buildActionButtons(isDarkMode, isDesktop: true),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'content-image-${widget.content.name}',
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                    child: CachedNetworkImage(
                      imageUrl: widget.content.thumbnails.last.url,
                      width: imageSize,
                      height: imageSize,
                      fit: BoxFit.cover,
                      memCacheWidth: (imageSize * 2).toInt(),
                      memCacheHeight: (imageSize * 2).toInt(),
                      placeholder: (context, url) => Container(
                        color: Colors.grey[850],
                        child: const Center(
                          child: Icon(Icons.my_library_music),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[850],
                        child: const Icon(Icons.error),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: effectiveWidth < AppDimens.breakpointMobile
                    ? AppDimens.spacingMd
                    : AppDimens.spacingLg,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.content.name,
                      style: titleStyle.copyWith(
                        color: MainScreenColors.getTextColor(isDarkMode),
                        height: 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(
                      height: effectiveWidth < AppDimens.breakpointMobile
                          ? AppDimens.spacingXxs
                          : AppDimens.paddingXs,
                    ),
                    Text(
                      _provider.contentDescription,
                      style: subtitleStyle.copyWith(
                        color: MainScreenColors.getTextColor(
                          isDarkMode,
                        ).withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(
                      height: effectiveWidth < AppDimens.breakpointMobile
                          ? AppDimens.spacingXxs
                          : AppDimens.paddingXs,
                    ),
                    Text(
                      '${_provider.songs.length} songs • ${_provider.formatTotalDuration()}',
                      style: subtitleStyle.copyWith(
                        color: MainScreenColors.getTextColor(
                          isDarkMode,
                        ).withValues(alpha: 0.7),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(
            height: effectiveWidth < AppDimens.breakpointMobile
                ? AppDimens.spacingMd
                : AppDimens.spacingLg,
          ),
          _buildActionButtons(isDarkMode),
        ],
      ],
    );

    return Container(
      margin: EdgeInsets.all(margin),
      decoration: BoxDecoration(
        color: MainScreenColors.getSurfaceColor(isDarkMode),
        borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: headerContent),
    );
  }

  Widget _buildActionButtons(bool isDarkMode, {bool isDesktop = false}) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final accentColor = settingsProvider.accentColor;
    final screenWidth = MediaQuery.of(context).size.width;
    if (isDesktop) {
      final double buttonPadding = AppDimens.spacingSmMd;
      final double buttonSize = AppDimens.buttonSizeLg;
      final double iconSize = AppDimens.iconMdLg;

      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _provider.songs.isEmpty
                  ? null
                  : () => _playSong(_provider.songs.first),
              icon: const Icon(Icons.play_arrow, color: Colors.black),
              label: Text(
                'Play All',
                style: AppTextStyles.bodyLg(
                  color: Colors.white,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: AppDimens.spacingMdLg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
                ),
              ),
            ),
          ),
          SizedBox(height: AppDimens.spacingLg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildResponsiveIconButton(
                icon: Icons.queue_music,
                onPressed: () {
                  final queueProvider = Provider.of<QueueProvider>(
                    context,
                    listen: false,
                  );
                  if (queueProvider.hasLocalSongsInQueue) {
                    AppSnackBar.showError(
                      context,
                      'cannot_add_songs_to_queue'.tr(),
                    );
                    return;
                  }
                  queueProvider.addAllToQueue(
                    _provider.allSongs.cast<SongInfo>(),
                  );
                  AppSnackBar.showInfo(
                    context,
                    'added_all_songs_to_queue'.tr(),
                    duration: const Duration(seconds: 2),
                  );
                },
                tooltip: 'add_to_queue'.tr(),
                isDarkMode: isDarkMode,
                size: buttonSize,
                iconSize: iconSize,
                padding: buttonPadding,
              ),
              if (_provider.canToggleLibrary)
                _buildResponsiveIconButton(
                  icon: _provider.isSaved
                      ? Icons.library_add_check
                      : Icons.library_add,
                  onPressed: _provider.isSaved
                      ? _removeFromLibrary
                      : _addToLibrary,
                  tooltip: _provider.isSaved
                      ? 'remove_from_library'.tr()
                      : 'add_to_library'.tr(),
                  isDarkMode: isDarkMode,
                  size: buttonSize,
                  iconSize: iconSize,
                  padding: buttonPadding,
                ),
              _buildResponsiveIconButton(
                icon: Icons.download,
                onPressed: _provider.allSongs.isEmpty
                    ? null
                    : () => _downloadPlaylist(),
                tooltip: 'download_all'.tr(),
                isDarkMode: isDarkMode,
                size: buttonSize,
                iconSize: iconSize,
                padding: buttonPadding,
              ),
              _buildResponsiveIconButton(
                icon: Icons.share,
                onPressed: _shareContent,
                tooltip: 'share'.tr(),
                isDarkMode: isDarkMode,
                size: buttonSize,
                iconSize: iconSize,
                padding: buttonPadding,
              ),
            ],
          ),
        ],
      );
    }
    final isVerySmall = screenWidth < 400;
    final double buttonPadding = isVerySmall
        ? AppDimens.paddingXs
        : (screenWidth < AppDimens.breakpointMobile
              ? AppDimens.spacingS
              : AppDimens.paddingSm);
    final double buttonSize = isVerySmall
        ? AppDimens.buttonSizeCompact
        : (screenWidth < AppDimens.breakpointMobile
              ? AppDimens.buttonSizeCompact
              : AppDimens.buttonSizeDefault);
    final double iconSize = isVerySmall
        ? AppDimens.iconXs
        : (screenWidth < AppDimens.breakpointMobile
              ? AppDimens.iconSm
              : AppDimens.iconMd);

    final TextStyle playButtonStyle = isVerySmall
        ? AppTextStyles.finePrint()
        : (screenWidth < AppDimens.breakpointMobile
              ? AppTextStyles.caption()
              : AppTextStyles.button());

    final EdgeInsets playButtonPadding = isVerySmall
        ? const EdgeInsets.symmetric(
            vertical: AppDimens.spacingS,
            horizontal: AppDimens.paddingXs,
          )
        : (screenWidth < AppDimens.breakpointMobile
              ? const EdgeInsets.symmetric(
                  vertical: AppDimens.paddingSm,
                  horizontal: AppDimens.spacingMd,
                )
              : const EdgeInsets.symmetric(
                  vertical: AppDimens.paddingMd,
                  horizontal: AppDimens.paddingLg,
                ));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildResponsiveIconButton(
          icon: Icons.queue_music,
          onPressed: () {
            final queueProvider = Provider.of<QueueProvider>(
              context,
              listen: false,
            );
            if (queueProvider.hasLocalSongsInQueue) {
              AppSnackBar.showError(context, 'cannot_add_songs_to_queue'.tr());
              return;
            }
            queueProvider.addAllToQueue(_provider.allSongs.cast<SongInfo>());
            AppSnackBar.showInfo(
              context,
              'added_all_songs_to_queue'.tr(),
              duration: const Duration(seconds: 2),
            );
          },
          tooltip: 'add_to_queue'.tr(),
          isDarkMode: isDarkMode,
          size: buttonSize,
          iconSize: iconSize,
          padding: buttonPadding,
        ),
        if (_provider.canToggleLibrary)
          _buildResponsiveIconButton(
            icon: _provider.isSaved
                ? Icons.library_add_check
                : Icons.library_add,
            onPressed: _provider.isSaved ? _removeFromLibrary : _addToLibrary,
            tooltip: _provider.isSaved
                ? 'remove_from_library'.tr()
                : 'add_to_library'.tr(),
            isDarkMode: isDarkMode,
            size: buttonSize,
            iconSize: iconSize,
            padding: buttonPadding,
          ),
        SizedBox(
          width: isVerySmall ? screenWidth * 0.25 : screenWidth * 0.3,
          child: ElevatedButton(
            onPressed: _provider.songs.isEmpty
                ? null
                : () => _playSong(_provider.songs.first),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              padding: playButtonPadding,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimens.radiusMdLg),
              ),
            ),
            child: Center(
              child: Text(
                'play_all'.tr(),
                style: playButtonStyle.copyWith(color: Colors.black),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        _buildResponsiveIconButton(
          icon: Icons.download,
          onPressed: _provider.allSongs.isEmpty
              ? null
              : () => _downloadPlaylist(),
          tooltip: 'download'.tr(),
          isDarkMode: isDarkMode,
          size: buttonSize,
          iconSize: iconSize,
          padding: buttonPadding,
        ),
        _buildResponsiveIconButton(
          icon: Icons.share,
          onPressed: _shareContent,
          tooltip: 'share'.tr(),
          isDarkMode: isDarkMode,
          size: buttonSize,
          iconSize: iconSize,
          padding: buttonPadding,
        ),
      ],
    );
  }

  Widget _buildResponsiveIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required bool isDarkMode,
    required double size,
    required double iconSize,
    required double padding,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: MainScreenColors.getTextColor(isDarkMode).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: tooltip,
        iconSize: iconSize,
        color: MainScreenColors.getTextColor(isDarkMode),
        padding: EdgeInsets.all(padding),
        constraints: BoxConstraints(minWidth: size, minHeight: size),
      ),
    );
  }

  Widget _buildSuggestionsSection(bool isDarkMode) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final accentColor = settingsProvider.accentColor;

    if (_loadingSuggestions) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppDimens.spacingXxl,
          horizontal: AppDimens.paddingLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suggested for you',
              style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
            ),
            const SizedBox(height: AppDimens.spacingLg),
            Center(
              child: CircularProgressIndicator(
                strokeWidth: AppDimens.progressStroke,
                color: accentColor,
              ),
            ),
          ],
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return const SizedBox(height: AppDimens.spacingXxl);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.paddingLg,
            AppDimens.spacingXl,
            AppDimens.paddingLg,
            AppDimens.spacingSm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: AppDimens.iconMd,
                color: accentColor,
              ),
              const SizedBox(width: AppDimens.spacingMd),
              Text(
                'Suggested for you',
                style: AppTextStyles.titleSm(isDarkMode: isDarkMode),
              ),
            ],
          ),
        ),
        ..._suggestions.map(
          (song) => ListTile(
            onTap: () => _playSuggestion(song),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              child: CachedNetworkImage(
                imageUrl: song.thumbnails.isNotEmpty
                    ? song.thumbnails.first.url
                    : '',
                width: AppDimens.thumbnailDefault,
                height: AppDimens.thumbnailDefault,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  color: MainScreenColors.getSurfaceColor(isDarkMode),
                ),
                errorWidget: (_, _, _) => Container(
                  color: MainScreenColors.getSurfaceColor(isDarkMode),
                  child: const Icon(Icons.music_note, size: 20),
                ),
              ),
            ),
            title: Text(
              song.name,
              style: AppTextStyles.queueItem(isDarkMode: isDarkMode),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              song.artists.isNotEmpty ? song.artists.first.name : '',
              style: AppTextStyles.bodyMd(
                isDarkMode: isDarkMode,
                color: MainScreenColors.getTextColor(
                  isDarkMode,
                ).withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _isLocal
                ? IconButton(
                    tooltip: 'Add to playlist',
                    icon: Icon(Icons.add_circle_outline, color: accentColor),
                    onPressed: () => _addSuggestionToPlaylist(song),
                  )
                : null,
          ),
        ),
        const SizedBox(height: AppDimens.bottomDockClearance),
      ],
    );
  }

  Widget _buildLoadMoreButton(bool isDarkMode) {
    final bool hasMoreSongs =
        _provider.songs.length < _provider.allSongs.length;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingLg),
        child: ElevatedButton(
          onPressed: hasMoreSongs ? _loadMoreSongs : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: MainScreenColors.getTextColor(
              isDarkMode,
            ).withValues(alpha: 0.1),
            foregroundColor: MainScreenColors.getTextColor(isDarkMode),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.spacingXxl,
              vertical: AppDimens.paddingMd,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimens.radiusXxl),
            ),
          ),
          child: Text(
            hasMoreSongs ? 'load_more_songs'.tr() : 'no_more_songs'.tr(),
            style: AppTextStyles.bodyMd().copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // copyWith (not a bare ThemeData) so brightness, text colors and the
    // MusiXAccent extension survive; a fresh ThemeData() silently reverts
    // this whole subtree to light mode, which painted white surfaces
    // (shimmer header, overscroll glow, default Material colours) on top of
    // the dark theme and flashed white while scrolling.
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        cardColor: MainScreenColors.getSurfaceColor(isDarkMode),
        popupMenuTheme: PopupMenuThemeData(
          color: MainScreenColors.getSurfaceColor(isDarkMode),
        ),
      ),
      child: Consumer<PlayerProvider>(
        builder: (context, playerProvider, child) {
          return SafeArea(
            top: false,
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: isDarkMode
                    ? Colors.transparent
                    : MainScreenColors.getSurfaceColor(false),
                elevation: 0,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(AppDimens.paddingSm),
                    decoration: BoxDecoration(
                      color: MainScreenColors.getSurfaceColor(isDarkMode),
                      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      color: MainScreenColors.getTextColor(isDarkMode),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.search),
                    onPressed: () => showSearch(
                      context: context,
                      delegate: SongSearchDelegate(
                        songs: _provider.songs,
                        onPlay: _playSong,
                      ),
                    ),
                  ),
                  if (_isLocal)
                    PopupMenuButton<String>(
                      tooltip: 'Playlist options',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'rename') {
                          _renamePlaylist();
                        } else if (value == 'set_cover') {
                          _setCoverFromTopSong();
                        }
                      },
                      itemBuilder: (context) {
                        return const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 20),
                                SizedBox(width: 10),
                                Text('Rename playlist'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'set_cover',
                            child: Row(
                              children: [
                                Icon(Icons.image_outlined, size: 20),
                                SizedBox(width: 10),
                                Text('Use top song as cover'),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                ],
              ),
              body: Stack(
                children: [_buildContent(playerProvider, isDarkMode)],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _onReorderItem(int oldIndex, int newIndex) async {
    if (!_isLocal) return;
    final songs = _provider.songs;
    if (oldIndex >= songs.length || newIndex > songs.length) return;
    final library = _libraryProvider;

    // onReorderItem already accounts for the removed item. reorderPlaylistSongs
    // still expects the raw ReorderableListView index, which is one higher when
    // moving an item down, so undo that adjustment before handing it over.
    final candidate = newIndex > oldIndex ? newIndex + 1 : newIndex;
    final rawNewIndex = candidate < 0
        ? 0
        : (candidate > songs.length ? songs.length : candidate);

    await library.reorderPlaylistSongs(_playlistName, oldIndex, rawNewIndex);
    if (mounted) {
      await _provider.refreshLocalSongs(library, force: true);
      setState(() {});
    }
  }

  Widget _buildSongList(PlayerProvider playerProvider, bool isDarkMode) {
    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingLg),
          sliver: _isLocal
              ? SliverReorderableList(
                  itemBuilder: (context, index) {
                    if (index == _provider.songs.length) {
                      return KeyedSubtree(
                        key: const ValueKey('playlist-load-more'),
                        child: _buildLoadMoreButton(isDarkMode),
                      );
                    }
                    final song = _provider.songs[index];
                    final settingsProvider = Provider.of<SettingsProvider>(
                      context,
                      listen: false,
                    );
                    final accentColor = settingsProvider.accentColor;

                    return Builder(
                      key: ValueKey(
                        song.videoId?.toString() ?? '${song.name}_$index',
                      ),
                      builder: (context) {
                        final isCurrentlyPlaying = context
                            .select<PlayerProvider, bool>(
                              (p) => p.currentSong?.videoId == song.videoId,
                            );
                        // Delayed listener: the drag only starts after a long
                        // press, so a normal swipe scrolls the list instead of
                        // picking the song up.
                        return ReorderableDelayedDragStartListener(
                          index: index,
                          child: Container(
                            decoration: BoxDecoration(
                              color: isCurrentlyPlaying
                                  ? accentColor.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusLg,
                              ),
                            ),
                            child: SongListTile(
                              song: song,
                              isPlaying: isCurrentlyPlaying,
                              onPlay: () => _playSong(song),
                              onDelete: () => _removeSong(song),
                              isDarkMode: isDarkMode,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  itemCount: _provider.songs.length + 1,
                  onReorderItem: _onReorderItem,
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index == _provider.songs.length) {
                      return _buildLoadMoreButton(isDarkMode);
                    }
                    final song = _provider.songs[index];
                    final settingsProvider = Provider.of<SettingsProvider>(
                      context,
                      listen: false,
                    );
                    final accentColor = settingsProvider.accentColor;

                    return Builder(
                      builder: (context) {
                        final isCurrentlyPlaying = context
                            .select<PlayerProvider, bool>(
                              (p) => p.currentSong?.videoId == song.videoId,
                            );
                        return Container(
                          decoration: BoxDecoration(
                            color: isCurrentlyPlaying
                                ? accentColor.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppDimens.radiusLg,
                            ),
                          ),
                          child: SongListTile(
                            key: ValueKey('${song.name}_$index'),
                            song: song,
                            isPlaying: isCurrentlyPlaying,
                            onPlay: () => _playSong(song),
                            onDelete: null,
                            isDarkMode: isDarkMode,
                          ),
                        );
                      },
                    );
                  }, childCount: _provider.songs.length + 1),
                ),
        ),
        if (_suggestions.isNotEmpty || _loadingSuggestions)
          SliverToBoxAdapter(child: _buildSuggestionsSection(isDarkMode)),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).padding.bottom +
                AppDimens.miniPlayerHeightWide,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLeftPanel(bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80),
      child: _buildHeader(isDesktop: true),
    );
  }

  Widget _buildContent(PlayerProvider playerProvider, bool isDarkMode) {
    if (_provider.isLoading) {
      return PlaylistAlbumContentShimmer.buildShimmer(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: constraints.maxWidth * 0.38,
                child: _buildDesktopLeftPanel(isDarkMode),
              ),
              Container(
                width: 1,
                height: double.infinity,
                color: MainScreenColors.getTextColor(
                  isDarkMode,
                ).withValues(alpha: 0.1),
              ),
              Expanded(child: _buildSongList(playerProvider, isDarkMode)),
            ],
          );
        }
        return CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.spacingLg,
              ),
              sliver: _isLocal
                  ? SliverReorderableList(
                      itemBuilder: (context, index) {
                        if (index == _provider.songs.length) {
                          return KeyedSubtree(
                            key: const ValueKey('playlist-load-more'),
                            child: _buildLoadMoreButton(isDarkMode),
                          );
                        }
                        final song = _provider.songs[index];
                        final settingsProvider = Provider.of<SettingsProvider>(
                          context,
                          listen: false,
                        );
                        final accentColor = settingsProvider.accentColor;

                        return Builder(
                          key: ValueKey(
                            song.videoId?.toString() ?? '${song.name}_$index',
                          ),
                          builder: (context) {
                            final isCurrentlyPlaying = context
                                .select<PlayerProvider, bool>(
                                  (p) => p.currentSong?.videoId == song.videoId,
                                );
                            // Delayed listener: the drag only starts after a
                            // long press, so a normal swipe scrolls the list
                            // instead of picking the song up.
                            return ReorderableDelayedDragStartListener(
                              index: index,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isCurrentlyPlaying
                                      ? accentColor.withValues(alpha: 0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusLg,
                                  ),
                                ),
                                child: SongListTile(
                                  song: song,
                                  isPlaying: isCurrentlyPlaying,
                                  onPlay: () => _playSong(song),
                                  onDelete: () => _removeSong(song),
                                  isDarkMode: isDarkMode,
                                ),
                              ),
                            );
                          },
                        );
                      },
                      itemCount: _provider.songs.length + 1,
                      onReorderItem: _onReorderItem,
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index == _provider.songs.length) {
                          return _buildLoadMoreButton(isDarkMode);
                        }
                        final song = _provider.songs[index];
                        final settingsProvider = Provider.of<SettingsProvider>(
                          context,
                          listen: false,
                        );
                        final accentColor = settingsProvider.accentColor;

                        return Builder(
                          builder: (context) {
                            final isCurrentlyPlaying = context
                                .select<PlayerProvider, bool>(
                                  (p) => p.currentSong?.videoId == song.videoId,
                                );
                            return Container(
                              decoration: BoxDecoration(
                                color: isCurrentlyPlaying
                                    ? accentColor.withValues(alpha: 0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AppDimens.radiusLg,
                                ),
                              ),
                              child: SongListTile(
                                key: ValueKey('${song.name}_$index'),
                                song: song,
                                isPlaying: isCurrentlyPlaying,
                                onPlay: () => _playSong(song),
                                onDelete: null,
                                isDarkMode: isDarkMode,
                              ),
                            );
                          },
                        );
                      }, childCount: _provider.songs.length + 1),
                    ),
            ),
            if (_suggestions.isNotEmpty || _loadingSuggestions)
              SliverToBoxAdapter(child: _buildSuggestionsSection(isDarkMode)),
            SliverPadding(
              padding: EdgeInsets.only(
                bottom:
                    MediaQuery.of(context).padding.bottom +
                    AppDimens.miniPlayerHeightWide,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    if (_isLocal) _libraryProvider.removeListener(_onLibraryChanged);
    _provider.removeListener(_onProviderChanged);
    _scrollController.dispose();
    super.dispose();
  }
}
