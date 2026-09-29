import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:audio_session/audio_session.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:jiosaavn/jiosaavn.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:terminate_restart/terminate_restart.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'core/constants/app_text_styles.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/providers/download_provider.dart';
import 'core/providers/favorite_artist_provider.dart';
import 'core/providers/favorite_song_provider.dart';
import 'core/providers/lyrics_provider.dart';
import 'core/providers/player_provider.dart';
import 'core/providers/queued_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/stats_provider.dart';
import 'core/providers/video_info_provider.dart';

import 'core/services/crash_log_service.dart';
import 'core/services/download_notification_service.dart';
import 'core/services/intent_service.dart';

import 'core/theme/app_theme.dart';

import 'features/home/data/providers/home_screen_provider.dart';
import 'features/home/data/providers/covers_and_remixes_provider.dart';
import 'features/library/data/providers/library_provider.dart';
import 'features/ota/data/providers/ota_provider.dart';
import 'features/playlists/data/providers/playlist_album_library_provider.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'features/trending/data/provider/trending_provider.dart';

Future<void> main() async {
  final talker = TalkerFlutter.init();

  FlutterError.onError = (FlutterErrorDetails details) {
    talker.handle(
      details.exception,
      details.stack ?? StackTrace.current,
      'FlutterError.onError',
    );

    FlutterError.presentError(details);
  };

  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // ------------------------------------------------------------
      // ORIENTATION
      // ------------------------------------------------------------

      if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }

      // ------------------------------------------------------------
      // MEDIA KIT
      // ------------------------------------------------------------

      MediaKit.ensureInitialized();

      // ------------------------------------------------------------
      // TERMINATE / RESTART
      // ------------------------------------------------------------

      TerminateRestart.instance.initialize();

      // ------------------------------------------------------------
      // HIVE
      // ------------------------------------------------------------

      final appSupportDir = await getApplicationSupportDirectory();

      final hiveDir = Directory('${appSupportDir.path}/musicx');

      if (!await hiveDir.exists()) {
        await hiveDir.create(recursive: true);
      }

      Hive.init(hiveDir.path);

      Hive.registerAdapter(SongInfoDTOAdapter());
      Hive.registerAdapter(ArtistDTOAdapter());
      Hive.registerAdapter(ThumbnailDTOAdapter());
      Hive.registerAdapter(HomeSectionDTOAdapter());
      Hive.registerAdapter(AlbumDetailedDTOAdapter());
      Hive.registerAdapter(PlaylistDetailedDTOAdapter());
      Hive.registerAdapter(ArtistBasicDTOAdapter());
      Hive.registerAdapter(ThumbnailFullDTOAdapter());

      // ------------------------------------------------------------
      // SETTINGS
      // ------------------------------------------------------------

      final settingsProvider = SettingsProvider();

      GetIt.I.registerSingleton<SettingsProvider>(settingsProvider);

      const hiveBoxNames = [
        'liked_songs',
        'favorite_artists',
        'audio_url_cache',
        'saved_playlists',
        'saved_albums',
        'created_playlists',
        'playlist_songs',
        'last_played',
        'queue_storage',
        'video_info_cache',
        'playback_stats',
        'recent_playlists',
      ];

      await Hive.openBox<dynamic>('app_settings');

      await Future.wait([
        settingsProvider.loadSettings(),

        Future.wait(hiveBoxNames.map((name) => Hive.openBox<String>(name))),
      ]);

      // ------------------------------------------------------------
      // CONNECTIVITY
      // ------------------------------------------------------------

      final connectivityProvider = ConnectivityProvider();

      GetIt.I.registerSingleton<ConnectivityProvider>(connectivityProvider);

      // ------------------------------------------------------------
      // TALKER
      // ------------------------------------------------------------

      GetIt.I.registerSingleton<Talker>(talker);

      // ------------------------------------------------------------
      // CRASH LOGGING
      // ------------------------------------------------------------

      final crashLogService = CrashLogService();

      await crashLogService.init();

      GetIt.I.registerSingleton<CrashLogService>(crashLogService);

      try {
        if (settingsProvider.loggingOnStartup) {
          crashLogService.startLogging();

          talker.info(
            'Continuous logging started '
            '(startup setting enabled)',
          );
        }
      } catch (_) {}

      // ------------------------------------------------------------
      // GLOBAL FLUTTER ERROR HANDLER
      // ------------------------------------------------------------

      FlutterError.onError = (FlutterErrorDetails details) {
        talker.handle(
          details.exception,
          details.stack ?? StackTrace.current,
          'FlutterError.onError',
        );

        try {
          if (GetIt.I.isRegistered<CrashLogService>()) {
            GetIt.I<CrashLogService>().recordError(
              details.exception,
              details.stack ?? StackTrace.current,
              'FlutterError.onError',
            );
          }
        } catch (_) {}

        FlutterError.presentError(details);
      };

      // ------------------------------------------------------------
      // YOUTUBE EXPLODE
      // ------------------------------------------------------------

      final youtubeExplode = YoutubeExplode();

      GetIt.I.registerSingleton<YoutubeExplode>(youtubeExplode);

      talker.info('YoutubeExplode initialized');

      // ------------------------------------------------------------
      // JIOSAAVN
      // ------------------------------------------------------------

      final jioSaavnClient = JioSaavnClient();

      GetIt.I.registerSingleton<JioSaavnClient>(jioSaavnClient);

      // ------------------------------------------------------------
      // YOUTUBE MUSIC
      // ENGLISH
      // ------------------------------------------------------------

      final ytMusic = YTMusic();

      try {
        await ytMusic
            .initialize(hl: 'en')
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                talker.warning(
                  'YTMusic initialization timed out. '
                  'Continuing in offline mode.',
                );

                return ytMusic;
              },
            );

        talker.info('YTMusic initialized successfully');
      } catch (e, st) {
        talker.error('YTMusic initialization failed: $e');

        talker.handle(e, st, 'YTMusic initialization failed');
      }

      GetIt.I.registerSingleton<YTMusic>(ytMusic);

      // ------------------------------------------------------------
      // VIDEO INFO PROVIDER
      // ------------------------------------------------------------

      final videoInfoProvider = VideoInfoProvider();

      GetIt.I.registerSingleton<VideoInfoProvider>(videoInfoProvider);

      // ------------------------------------------------------------
      // EASY LOCALIZATION
      // ------------------------------------------------------------

      await EasyLocalization.ensureInitialized();

      // ------------------------------------------------------------
      // DOWNLOAD NOTIFICATIONS
      // ------------------------------------------------------------

      if (Platform.isAndroid) {
        try {
          final notificationService = DownloadNotificationService();

          await notificationService.initialize();

          talker.info('Download notifications initialized');
        } catch (e, st) {
          talker.handle(e, st, 'Download notifications initialization failed');
        }
      }

      // ------------------------------------------------------------
      // ANDROID AUDIO SESSION
      // ------------------------------------------------------------

      if (Platform.isAndroid) {
        try {
          final session = await AudioSession.instance;

          await session.configure(const AudioSessionConfiguration.music());

          talker.info('Android audio session initialized');
        } catch (e, st) {
          talker.handle(e, st, 'Audio session initialization failed');
        }
      }

      // ------------------------------------------------------------
      // METADATA
      // ------------------------------------------------------------

      try {
        await MetadataGod.initialize();

        talker.info('Metadata service initialized');
      } catch (e, st) {
        talker.handle(e, st, 'Metadata service initialization failed');
      }

      // ------------------------------------------------------------
      // PROVIDERS
      // ------------------------------------------------------------

      final downloadProvider = DownloadProvider();

      final queueProvider = QueueProvider();

      final statsProvider = StatsProvider();

      talker.info('MusiX app starting');

      // ------------------------------------------------------------
      // RUN APP
      // ------------------------------------------------------------

      runApp(
        TalkerWrapper(
          talker: talker,

          options: const TalkerWrapperOptions(enableErrorAlerts: true),

          child: MultiProvider(
            providers: [
              // --------------------------------------------------
              // CONNECTIVITY
              // --------------------------------------------------
              ChangeNotifierProvider.value(value: connectivityProvider),

              // --------------------------------------------------
              // HOME
              // --------------------------------------------------
              ChangeNotifierProvider(
                lazy: false,
                create: (_) => HomeScreenProvider()..initialize(),
              ),

              // --------------------------------------------------
              // COVERS AND REMIXES
              // --------------------------------------------------
              ChangeNotifierProvider(create: (_) => CoversAndRemixesProvider()),

              // --------------------------------------------------
              // TRENDING
              // --------------------------------------------------
              ChangeNotifierProvider(create: (_) => TrendingProvider()),

              // --------------------------------------------------
              // QUEUE
              // --------------------------------------------------
              ChangeNotifierProvider.value(value: queueProvider),

              // --------------------------------------------------
              // DOWNLOADS
              // --------------------------------------------------
              ChangeNotifierProvider.value(value: downloadProvider),

              // --------------------------------------------------
              // STATS
              // --------------------------------------------------
              ChangeNotifierProvider.value(value: statsProvider),

              // --------------------------------------------------
              // FAVORITE SONGS
              // --------------------------------------------------
              ChangeNotifierProvider(create: (_) => FavoriteSongProvider()),

              // --------------------------------------------------
              // PLAYER
              // --------------------------------------------------
              ChangeNotifierProvider(
                create: (context) => PlayerProvider(
                  Provider.of<QueueProvider>(context, listen: false),
                  Provider.of<DownloadProvider>(context, listen: false),
                  GetIt.I<VideoInfoProvider>(),
                  Provider.of<StatsProvider>(context, listen: false),
                  Provider.of<FavoriteSongProvider>(context, listen: false),
                ),
              ),

              // --------------------------------------------------
              // PLAYLIST / ALBUM LIBRARY
              // --------------------------------------------------
              ChangeNotifierProvider(
                lazy: false,
                create: (_) => PlaylistAlbumLibraryProvider()..loadAll(),
              ),

              // --------------------------------------------------
              // SETTINGS
              // --------------------------------------------------
              ChangeNotifierProvider.value(value: settingsProvider),

              // --------------------------------------------------
              // FAVORITE ARTISTS
              // --------------------------------------------------
              ChangeNotifierProvider(
                lazy: false,
                create: (_) => FavoriteArtistProvider()..loadFavoriteArtists(),
              ),

              // --------------------------------------------------
              // LIBRARY
              // --------------------------------------------------
              ChangeNotifierProvider(
                create: (context) => LibraryProvider(
                  Provider.of<PlayerProvider>(context, listen: false),
                  Provider.of<DownloadProvider>(context, listen: false),
                  Provider.of<FavoriteSongProvider>(context, listen: false),
                  Provider.of<SettingsProvider>(context, listen: false),
                ),
              ),

              // --------------------------------------------------
              // LYRICS
              // --------------------------------------------------
              ChangeNotifierProvider(
                create: (context) => LyricsProvider(
                  Provider.of<PlayerProvider>(context, listen: false),
                ),
              ),

              // --------------------------------------------------
              // OTA
              // --------------------------------------------------
              ChangeNotifierProvider(create: (_) => OTAProvider()),

              // --------------------------------------------------
              // VIDEO INFO
              // --------------------------------------------------
              ChangeNotifierProvider.value(value: videoInfoProvider),
            ],

            // ----------------------------------------------------
            // LOCALIZATION
            // ----------------------------------------------------
            child: EasyLocalization(
              supportedLocales: const [Locale('en')],

              path: 'assets/translations',

              fallbackLocale: const Locale('en'),

              child: const MusiXApp(),
            ),
          ),
        ),
      );
    },

    // --------------------------------------------------------------
    // GLOBAL ZONE ERROR HANDLER
    // --------------------------------------------------------------
    (error, stackTrace) {
      talker.handle(error, stackTrace, 'Uncaught zone error');

      try {
        if (GetIt.I.isRegistered<CrashLogService>()) {
          GetIt.I<CrashLogService>().recordError(
            error,
            stackTrace,
            'Uncaught zone error',
          );
        }
      } catch (_) {}
    },
  );
}

// ==================================================================
// MUSIX APP
// ==================================================================

class MusiXApp extends StatefulWidget {
  const MusiXApp({super.key});

  @override
  State<MusiXApp> createState() => _MusiXAppState();
}

class _MusiXAppState extends State<MusiXApp> with WidgetsBindingObserver {
  IntentService? _intentService;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // ------------------------------------------------------------
    // ANDROID INTENTS
    // ------------------------------------------------------------

    if (Platform.isAndroid) {
      _intentService = IntentService(
        Provider.of<PlayerProvider>(context, listen: false),
        Provider.of<QueueProvider>(context, listen: false),
      );

      _intentService?.init();
    }
  }

  @override
  void dispose() {
    _intentService?.dispose();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      navigatorKey: settingsProvider.navigatorKey,

      navigatorObservers: const [],

      localizationsDelegates: context.localizationDelegates,

      supportedLocales: context.supportedLocales,

      locale: const Locale('en'),

      title: 'MusiX',

      theme: AppTheme.lightTheme,

      darkTheme: AppTheme.darkTheme,

      themeMode: settingsProvider.themeMode,

      builder: AppTextStyles.appBuilder,

      home: const SplashScreen(),
    );
  }
}
