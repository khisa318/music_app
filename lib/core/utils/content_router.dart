import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import '../../features/artist/presentation/screens/artist_content.dart';
import '../../features/playlist_album_content/presentation/screens/playlist_album_content_screen.dart';
import '../models/song_model.dart';
import '../providers/player_provider.dart';
import '../providers/queued_provider.dart';
import '../services/content_details_service.dart';

class ContentRouter extends StatelessWidget {
  final dynamic content;

  const ContentRouter({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    if (content is ArtistDetailed) {
      return ArtistContent(artist: content);
    }

    // Song shelves (the "Listen again" / Speed Dial row) have no detail page,
    // and AlbumDetailed/PlaylistDetailed are the only shapes PlaylistAlbumContent
    // understands. Route songs to the player rather than to a broken screen.
    if (content is SongDetailed) {
      return _PlayOnOpenScreen(song: content);
    }

    if (content is AlbumDetailed || content is PlaylistDetailed) {
      return PlaylistAlbumContent(content: content);
    }

    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text('No detail page for this item')),
    );
  }

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/content':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => ContentRouter(content: args['content']),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}

/// Placeholder shown for one frame while a tapped track is handed to the
/// player, then pops itself so the user stays where they were.
class _PlayOnOpenScreen extends StatefulWidget {
  final SongDetailed song;

  const _PlayOnOpenScreen({required this.song});

  @override
  State<_PlayOnOpenScreen> createState() => _PlayOnOpenScreenState();
}

class _PlayOnOpenScreenState extends State<_PlayOnOpenScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playAndPop());
  }

  Future<void> _playAndPop() async {
    final navigator = Navigator.of(context);
    final playerProvider = context.read<PlayerProvider>();
    final queueProvider = context.read<QueueProvider>();

    final song = SongInfo(
      videoId: widget.song.videoId,
      name: widget.song.name,
      artists: [
        Artist(name: widget.song.artist.name, id: widget.song.artist.artistId ?? ''),
      ],
      thumbnails: widget.song.thumbnails
          .map(
            (t) => Thumbnail(url: t.url, width: t.width, height: t.height),
          )
          .toList(),
      duration: Duration(seconds: widget.song.duration ?? 0),
    );

    try {
      await ContentDetailsService().playSong(
        song,
        playerProvider,
        queueProvider,
        [song],
        playlistId: 'listen_again',
        playlistName: 'Listen again',
      );
    } catch (_) {
      // Playback failures are surfaced by the player itself.
    }

    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}
