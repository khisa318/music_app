import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../data/providers/playlist_album_library_provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/content_details_service.dart';
import '../../../../core/services/spotify_service.dart';
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
  final SpotifyService _spotifyService = SpotifyService();
  bool _isImporting = false;
  PlaylistSource _detectedSource = PlaylistSource.unknown;
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

  void _onLinkChanged(String value) {
    final source = _spotifyService.detectSource(value);
    if (source != _detectedSource) {
      setState(() {
        _detectedSource = source;
      });
    }
  }

  Future<void> _importPlaylist() async {
    final input = _importLinkController.text.trim();
    if (input.isEmpty) return;

    switch (_spotifyService.detectSource(input)) {
      case PlaylistSource.spotify:
        await _importSpotifyPlaylist(input);
      case PlaylistSource.youtube:
        await _importYouTubePlaylist(input);
      case PlaylistSource.unknown:
        AppSnackBar.showError(context, 'invalid_playlist_link'.tr());
    }
  }

  Future<void> _importYouTubePlaylist(String url) async {
    setState(() {
      _isImporting = true;
    });

    try {
      final String? playlistId = _contentDetailsService.extractPlaylistId(url);

      if (playlistId == null) {
        AppSnackBar.showError(context, 'invalid_youtube_playlist_link'.tr());
        return;
      }

      final playlistData = await _contentDetailsService.getPlaylistDetails(
        playlistId,
      );

      if (!mounted) return;

      if (playlistData == null) {
        AppSnackBar.showError(context, 'could_not_fetch_playlist_details'.tr());
        return;
      }

      if (!mounted) return;

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

      final importedType =
          (playlistData['contentType'] as String?) ?? 'Playlist';
      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        'playlist_imported'.tr(args: [importedType, playlistData['name']]),
      );

      _importLinkController.clear();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'Error importing playlist: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _importSpotifyPlaylist(String input) async {
    final playlistId = _spotifyService.extractPlaylistId(input);
    if (playlistId == null) {
      AppSnackBar.showError(context, 'invalid_playlist_link'.tr());
      return;
    }

    setState(() {
      _isImporting = true;
      _importStatus = 'fetching_playlist'.tr();
    });

    try {
      final spotifyPlaylist = await _spotifyService.fetchPlaylist(playlistId);

      if (!mounted) return;

      if (spotifyPlaylist == null || spotifyPlaylist.tracks.isEmpty) {
        AppSnackBar.showError(context, 'spotify_no_tracks'.tr());
        return;
      }

      final matched = await _spotifyService.matchTracksToYouTube(
        spotifyPlaylist.tracks,
        fallbackThumbnail: spotifyPlaylist.thumbnail,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _importStatus = 'import_progress'.tr(
              args: ['$completed', '$total'],
            );
          });
        },
      );

      if (!mounted) return;

      if (matched.isEmpty) {
        AppSnackBar.showError(context, 'spotify_no_tracks'.tr());
        return;
      }

      final provider = Provider.of<PlaylistAlbumLibraryProvider>(
        context,
        listen: false,
      );

      final uniqueName = _buildUniqueName(provider, spotifyPlaylist.name);

      await provider.saveCreatedPlaylist(
        uniqueName,
        thumbnail: spotifyPlaylist.thumbnail.isEmpty
            ? null
            : spotifyPlaylist.thumbnail,
      );

      for (final song in matched) {
        await provider.saveSongToPlaylist(uniqueName, song);
      }

      await provider.loadCreatedPlaylists();

      if (!mounted) return;
      AppSnackBar.showSuccess(
        context,
        'spotify_import_success'.tr(args: [uniqueName, '${matched.length}']),
      );

      _importLinkController.clear();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'Error importing Spotify playlist: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importStatus = '';
        });
      }
    }
  }

  String _buildUniqueName(
    PlaylistAlbumLibraryProvider provider,
    String base,
  ) {
    final existing = provider.createdPlaylists
        .map((p) => p['name']?.toString())
        .toSet();
    var name = base;
    var counter = 2;
    while (existing.contains(name)) {
      name = '$base ($counter)';
      counter++;
    }
    return name;
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
      child: Container(
        height: screenHeight * 0.6,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: MainScreenColors.getSurfaceColor(isDarkMode),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              spreadRadius: 0,
            ),
          ],
        ),
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
                        onChanged: _onLinkChanged,
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
                      if (_detectedSource != PlaylistSource.unknown) ...[
                        const SizedBox(height: 12),
                        _buildSourceIndicator(isDarkMode),
                      ],
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
                        const SizedBox(height: 16),
                        Text(
                          _importStatus,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: MainScreenColors.getTextColor(
                              isDarkMode,
                            ).withValues(alpha: 0.7),
                            fontSize: 13,
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
    );
  }

  Widget _buildSourceIndicator(bool isDarkMode) {
    final isSpotify = _detectedSource == PlaylistSource.spotify;
    final color = isSpotify ? const Color(0xFF1DB954) : Colors.red;
    final label = isSpotify ? 'detected_spotify'.tr() : 'detected_youtube'.tr();

    return Row(
      children: [
        Icon(
          isSpotify ? Icons.graphic_eq : Icons.smart_display,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
