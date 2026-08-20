import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:jiosaavn/jiosaavn.dart';
import 'package:path_provider/path_provider.dart';
import 'package:terminate_restart/terminate_restart.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'core/constants/app_text_styles.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'core/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'core/providers/download_provider.dart';
import 'core/providers/player_provider.dart';
import 'features/playlists/data/providers/playlist_album_library_provider.dart';
import 'features/home/data/providers/home_screen_provider.dart';
import 'core/providers/queued_provider.dart';
import 'core/providers/settings_provider.dart';
import 'features/trending/data/provider/trending_provider.dart';
import 'core/providers/favorite_artist_provider.dart';
import 'core/providers/favorite_song_provider.dart';
import 'features/library/data/providers/library_provider.dart';
import 'core/providers/lyrics_provider.dart';
import 'features/ota/data/providers/ota_provider.dart';
import 'core/providers/video_info_provider.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/providers/stats_provider.dart';
import 'core/services/intent_service.dart';
import 'core/services/crash_log_service.dart';
import 'core/services/download_notification_service.dart';
import 'core/services/smtc_service.dart';
import 'core/services/windows_file_service.dart';

String _ytMusicHlFromLanguage(String language) {
  switch (language) {
    case 'Hindi':
      return 'hi';
    case 'Spanish':
      return 'es';
    case 'French':
      return 'fr';
    case 'German':
      return 'de';
    case 'Russian':
      return 'ru';
    case 'Ukrainian':
      return 'uk';
    case 'Bengali':
      return 'bn';
    case 'Japanese':
      return 'ja';
    case 'Chinese':
      return 'zh';
    case 'Urdu':
      return 'ur';
    case 'Telugu':
      return 'te';
    case 'Tamil':
      return 'ta';
    case 'Marathi':
      return 'mr';
    case 'Turkish':
      return 'tr';
    case 'Gujarati':
      return 'gu';
    case 'Kannada':
      return 'kn';
    case 'Korean':
      return 'ko';
    case 'Indonesian':
      return 'id';
    case 'Portuguese':
      return 'pt';
    case 'Vietnamese':
      return 'vi';
    case 'Arabic':
      return 'ar';
    case 'English':
    default:
      return 'en';
  }
}

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
      if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
      MediaKit.ensureInitialized();

      TerminateRestart.instance.initialize();
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

      final connectivityProvider = ConnectivityProvider();
      GetIt.I.registerSingleton<ConnectivityProvider>(connectivityProvider);
      GetIt.I.registerSingleton<Talker>(talker);

      final crashLogService = CrashLogService();
      await crashLogService.init();
      GetIt.I.registerSingleton<CrashLogService>(crashLogService);

      try {
        if (settingsProvider.loggingOnStartup) {
          crashLogService.startLogging();
          talker.info('Continuous logging started (startup setting enabled)');
        }
      } catch (_) {}

      FlutterError.onError = (FlutterErrorDetails details) {
        talker.handle(
          details.exception,
          details.stack ?? StackTrace.current,
          'FlutterError.onError',
        );
        try {
          GetIt.I<CrashLogService>().recordError(
            details.exception,
            details.stack ?? StackTrace.current,
            'FlutterError.onError',
          );
        } catch (_) {}
        FlutterError.presentError(details);
      };

      GetIt.I.registerSingleton<YoutubeExplode>(YoutubeExplode());
      GetIt.I.registerSingleton<JioSaavnClient>(JioSaavnClient());

      final ytMusic = YTMusic();
      final ytMusicHl = _ytMusicHlFromLanguage(settingsProvider.language);
      try {
        await ytMusic
            .initialize(hl: ytMusicHl)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                talker.warning(
                  'YTMusic initialization timed out - continuing in offline mode',
                );
                return ytMusic;
              },
            );
        talker.info('YTMusic initialized successfully (hl=$ytMusicHl)');
      } catch (e, st) {
        talker.error(
          'YTMusic initialization failed: $e - continuing in offline mode',
        );
        talker.handle(e, st, 'YTMusic initialization failed');
      }
      GetIt.I.registerSingleton<YTMusic>(ytMusic);
      GetIt.I.registerSingleton<VideoInfoProvider>(VideoInfoProvider());

      await EasyLocalization.ensureInitialized();

      if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
        try {
          final notificationService = DownloadNotificationService();
          await notificationService.initialize();
          talker.info('Download notifications initialized');
        } catch (e, st) {
          talker.handle(e, st, 'Download notifications initialization failed');
        }
      }

      if (Platform.isAndroid) {
        try {
          final session = await AudioSession.instance;
          await session.configure(const AudioSessionConfiguration.music());
          talker.info('Android audio session initialized');
        } catch (e, st) {
          talker.handle(e, st, 'Audio session initialization failed');
        }
      }

      if (Platform.isWindows) {
        try {
          await SmtcService.ensureInitialized();
          talker.info('Windows SMTC initialized');
        } catch (e, st) {
          talker.handle(e, st, 'Windows SMTC initialization failed');
        }
      }

      try {
        await MetadataGod.initialize();
        talker.info('Metadata service initialized');
      } catch (e, st) {
        talker.handle(e, st, 'Metadata service initialization failed');
      }

      final downloadProvider = DownloadProvider();
      final queueProvider = QueueProvider();
      final statsProvider = StatsProvider();

      talker.info('MusiX app starting');

      runApp(
        TalkerWrapper(
          talker: talker,
          options: const TalkerWrapperOptions(enableErrorAlerts: true),
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: connectivityProvider),
              ChangeNotifierProvider(
                lazy: false,
                create: (_) => HomeScreenProvider()..initialize(),
              ),
              ChangeNotifierProvider(create: (_) => TrendingProvider()),
              ChangeNotifierProvider.value(value: queueProvider),
              ChangeNotifierProvider.value(value: downloadProvider),
              ChangeNotifierProvider.value(value: statsProvider),
              ChangeNotifierProvider(create: (_) => FavoriteSongProvider()),
              ChangeNotifierProvider(
                create: (context) => PlayerProvider(
                  Provider.of<QueueProvider>(context, listen: false),
                  Provider.of<DownloadProvider>(context, listen: false),
                  GetIt.I<VideoInfoProvider>(),
                  Provider.of<StatsProvider>(context, listen: false),
                  Provider.of<FavoriteSongProvider>(context, listen: false),
                ),
              ),

              ChangeNotifierProvider(
                lazy: false,
                create: (_) => PlaylistAlbumLibraryProvider()..loadAll(),
              ),
              ChangeNotifierProvider.value(value: settingsProvider),
              ChangeNotifierProvider(
                lazy: false,
                create: (_) => FavoriteArtistProvider()..loadFavoriteArtists(),
              ),
              ChangeNotifierProvider(
                create: (context) => LibraryProvider(
                  Provider.of<PlayerProvider>(context, listen: false),
                  Provider.of<DownloadProvider>(context, listen: false),
                  Provider.of<FavoriteSongProvider>(context, listen: false),
                  Provider.of<SettingsProvider>(context, listen: false),
                ),
              ),
              ChangeNotifierProvider(
                create: (context) => LyricsProvider(
                  Provider.of<PlayerProvider>(context, listen: false),
                ),
              ),
              ChangeNotifierProvider(create: (_) => OTAProvider()),
              ChangeNotifierProvider.value(value: GetIt.I<VideoInfoProvider>()),
            ],
            child: EasyLocalization(
              supportedLocales: const [
                Locale('en'),
                Locale('hi'),
                Locale('es'),
                Locale('fr'),
                Locale('de'),
                Locale('ru'),
                Locale('uk'),
                Locale('bn'),
                Locale('ja'),
                Locale('zh'),
                Locale('ur'),
                Locale('te'),
                Locale('ta'),
                Locale('mr'),
                Locale('tr'),
                Locale('gu'),
                Locale('kn'),
                Locale('ko'),
                Locale('id'),
                Locale('pt'),
                Locale('vi'),
                Locale('ar'),
              ],
              path: 'assets/translations',
              fallbackLocale: const Locale('en'),
              child: const MusiXApp(),
            ),
          ),
        ),
      );
    },
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

class MusiXApp extends StatefulWidget {
  const MusiXApp({super.key});

  @override
  State<MusiXApp> createState() => _MusiXAppState();
}

class _MusiXAppState extends State<MusiXApp> with WidgetsBindingObserver {
  IntentService? _intentService;
  WindowsFileService? _windowsFileService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      _intentService = IntentService(
        Provider.of<PlayerProvider>(context, listen: false),
        Provider.of<QueueProvider>(context, listen: false),
      );
      _intentService?.init();
    }
    if (Platform.isWindows) {
      _windowsFileService = WindowsFileService(
        Provider.of<PlayerProvider>(context, listen: false),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _windowsFileService?.init();
      });
    }
  }

  @override
  void dispose() {
    _intentService?.dispose();
    _windowsFileService?.dispose();
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
      navigatorObservers: [],
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      title: 'MusiX',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settingsProvider.themeMode,
      builder: AppTextStyles.appBuilder,
      home: const SplashScreen(),
    );
  }
}
