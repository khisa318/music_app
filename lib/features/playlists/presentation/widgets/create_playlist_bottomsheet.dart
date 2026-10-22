import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../data/providers/playlist_album_library_provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/content_details_service.dart';
import '../../../../core/services/spotify_playlist_service.dart';
import '../../../../core/services/spotify_track_matcher.dart';
import '../../../../core/widgets/glass_modal.dart';
import '../../../../shared/components/app_snackbar.dart';

class CreatePlaylistBottomSheet extends StatefulWidget {
  const CreatePlaylistBottomSheet({super.key});

  @override
  State<CreatePlaylistBottomSheet> createState() =>
      _CreatePlaylistBottomSheetState();
}

class _CreatePlaylistBottomSheetState extends State<CreatePlaylistBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _playlistNameController = TextEditingController();
  final TextEditingController _importLinkController = TextEditingController();
  List<Map<String, dynamic>> _playlists = [];
  final ContentDetailsService _contentDetailsService = ContentDetailsService();
  final SpotifyPlaylistService _spotifyService = SpotifyPlaylistService();

  /// How many tracks are matched before the playlist opens. The remainder keep
  /// matching in the background.
  static const int _foregroundImportCount = 10;
  bool _isImporting = false;
  String _importStatus = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlaylists();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _playlistNameController.dispose();
    _importLinkController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists() async {
    final provider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );
    if (!provider.hasLoadedCreatedPlaylists) {
      await provider.loadCreatedPlaylists();
    }
    setState(() {
      _playlists = provider.createdPlaylists;
    });
  }

  Future<void> _createNewPlaylist() async {
    final playlistName = _playlistNameController.text.trim();
    if (playlistName.isEmpty) return;

    final provider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );
    try {
      await provider.saveCreatedPlaylist(playlistName);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(
        context,
        'playlist_already_exists'.tr(args: [playlistName]),
      );
      return;
    }

    await provider.loadCreatedPlaylists();

    if (!mounted) return;

    AppSnackBar.showSuccess(
      context,
      'playlist_created'.tr(args: [playlistName]),
    );

    _playlistNameController.clear();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _importPlaylist() async {
    final String url = _importLinkController.text.trim();

    if (url.isEmpty) {
      AppSnackBar.showError(context, 'enter_link_first'.tr());
      return;
    }

    setState(() {
      _isImporting = true;
      _importStatus = '';
    });

    try {
      // YouTube playlists keep their existing behaviour (saved playlist).
      final String? youtubeId = _contentDetailsService.extractPlaylistId(url);
      if (youtubeId != null) {
        await _importYouTubePlaylist(youtubeId);
        return;
      }

      // Spotify playlists are matched to YouTube Music and stored locally.
      final String? spotifyId = SpotifyPlaylistService.extractPlaylistId(url);
      if (spotifyId != null) {
        await _importSpotifyPlaylist(spotifyId);
        return;
      }

      if (!mounted) return;
      AppSnackBar.showError(context, 'invalid_playlist_link'.tr());
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'Error importing playlist: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importStatus = '';
        });
      }
    }
  }

  Future<void> _importYouTubePlaylist(String playlistId) async {
    final playlistData = await _contentDetailsService.getPlaylistDetails(
      playlistId,
    );

    if (!mounted) return;

    if (playlistData == null) {
      AppSnackBar.showError(context, 'could_not_fetch_playlist_details'.tr());
      return;
    }

    final provider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );

    if ((playlistData['contentType'] as String?)?.toLowerCase() == 'album') {
      final albumData = {
        'name': playlistData['name'],
        'thumbnail': playlistData['thumbnail'],
        'duration': playlistData['duration'],

        'albumId': playlistData['playlistId'],
        'contentType': 'Album',
        'artist': playlistData['artist'],
      };
      await provider.saveAlbum(albumData);
    } else {
      final playlistSaveData = {
        'name': playlistData['name'],
        'thumbnail': playlistData['thumbnail'],
        'duration': playlistData['duration'],
        'playlistId': playlistData['playlistId'],
        'contentType': 'Playlist',
        'artist': playlistData['artist'],
      };
      await provider.savePlaylist(playlistSaveData);
    }

    final importedType = (playlistData['contentType'] as String?) ?? 'Playlist';
    if (!mounted) return;
    AppSnackBar.showSuccess(
      context,
      'playlist_imported'.tr(args: [importedType, playlistData['name']]),
    );

    _importLinkController.clear();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _importSpotifyPlaylist(String playlistId) async {
    final SpotifyPlaylist playlist;
    try {
      playlist = await _spotifyService.getPlaylist(playlistId);
    } on SpotifyImportException catch (e) {
      if (!mounted) return;
      switch (e.type) {
        case SpotifyImportError.notFound:
          AppSnackBar.showError(context, 'spotify_playlist_not_found'.tr());
          break;
        case SpotifyImportError.network:
        case SpotifyImportError.parse:
          AppSnackBar.showError(
            context,
            'could_not_fetch_playlist_details'.tr(),
          );
          break;
      }
      return;
    }

    if (!mounted) return;

    final total = playlist.tracks.length;
    _updateImportStatus(0, total);

    final provider = Provider.of<PlaylistAlbumLibraryProvider>(
      context,
      listen: false,
    );

    // Create the playlist up front so it can be opened right away.
    final playlistName = await provider.createPlaylistWithUniqueName(
      playlist.name,
      thumbnail: playlist.thumbnail,
    );

    final foregroundTracks = playlist.tracks
        .take(_foregroundImportCount)
        .toList();
    final remainingTracks = playlist.tracks
        .skip(_foregroundImportCount)
        .toList();

    final matcher = SpotifyTrackMatcher();
    final foregroundSongs = await matcher.matchAll(
      foregroundTracks,
      onProgress: (completed, _) => _updateImportStatus(completed, total),
    );

    for (final song in foregroundSongs) {
      await provider.saveSongToPlaylist(playlistName, song);
    }

    // Small playlist where nothing matched at all: don't keep it around.
    if (foregroundSongs.isEmpty && remainingTracks.isEmpty) {
      await provider.deleteCreatedPlaylist(playlistName);
      if (!mounted) return;
      AppSnackBar.showError(context, 'no_tracks_matched'.tr(args: ['$total']));
      return;
    }

    // Let the rest match in the background while the playlist is open.
    if (remainingTracks.isNotEmpty) {
      provider.importSpotifyTracksIntoPlaylist(
        playlistName,
        remainingTracks,
        totalTracks: total,
        alreadyMatched: foregroundSongs.length,
      );
    }

    if (!mounted) return;

    if (remainingTracks.isEmpty && foregroundSongs.length < total) {
      AppSnackBar.showWarning(
        context,
        'spotify_partial_match'.tr(
          args: ['${foregroundSongs.length}', '$total'],
        ),
      );
    } else {
      AppSnackBar.showSuccess(
        context,
        'playlist_imported'.tr(args: ['Spotify', playlistName]),
      );
    }

    _importLinkController.clear();
    if (!mounted) return;

    Navigator.pop(context, {
      'name': playlistName,
      'thumbnail': playlist.thumbnail,
    });
  }

  void _updateImportStatus(int completed, int total) {
    if (!mounted) return;
    setState(() {
      _importStatus = 'matching_track_progress'.tr(
        args: ['$completed', '$total'],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final settingsProvider = Provider.of<SettingsProvider>(
      context,
      listen: false,
    );
    final accentColor = settingsProvider.accentColor;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: screenHeight * 0.6,
        child: GlassSheet(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: accentColor,
                labelColor: accentColor,
                unselectedLabelColor: MainScreenColors.getTextColor(
                  isDarkMode,
                ).withValues(alpha: 0.6),
                labelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                tabs: [
                  Tab(text: 'create_playlist'.tr()),
                  Tab(text: 'import_playlist'.tr()),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    Column(
                      children: [
                        TextField(
                          controller: _playlistNameController,
                          cursorColor: accentColor,
                          decoration: InputDecoration(
                            hintText: 'new_playlist_name'.tr(),
                            filled: true,
                            fillColor: MainScreenColors.getTextColor(
                              isDarkMode,
                            ).withValues(alpha: 0.1),
                            hintStyle: TextStyle(
                              color: MainScreenColors.getTextColor(
                                isDarkMode,
                              ).withValues(alpha: 0.5),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                color: accentColor,
                              ),
                              onPressed: _createNewPlaylist,
                            ),
                          ),
                          style: TextStyle(
                            color: MainScreenColors.getTextColor(isDarkMode),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _playlists.length,
                            itemBuilder: (context, index) {
                              final playlist = _playlists[index];
                              return Card(
                                elevation: 0,
                                color: MainScreenColors.getTextColor(
                                  isDarkMode,
                                ).withValues(alpha: 0.05),
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    playlist['name'],
                                    style: TextStyle(
                                      color: MainScreenColors.getTextColor(
                                        isDarkMode,
                                      ),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    Column(
                      children: [
                        TextField(
                          cursorColor: accentColor,

                          controller: _importLinkController,
                          decoration: InputDecoration(
                            hintText: 'enter_playlist_link'.tr(),
                            filled: true,
                            fillColor: MainScreenColors.getTextColor(
                              isDarkMode,
                            ).withValues(alpha: 0.1),
                            hintStyle: TextStyle(
                              color: MainScreenColors.getTextColor(
                                isDarkMode,
                              ).withValues(alpha: 0.5),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                          ),
                          style: TextStyle(
                            color: MainScreenColors.getTextColor(isDarkMode),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _isImporting ? null : _importPlaylist,
                          icon: _isImporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_download,
                                  color: Colors.black,
                                ),
                          label: Text(
                            _isImporting
                                ? 'importing'.tr()
                                : 'import_playlist'.tr(),
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                        if (_isImporting && _importStatus.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _importStatus,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: MainScreenColors.getTextColor(
                                isDarkMode,
                              ).withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
