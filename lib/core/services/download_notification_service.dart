import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadNotificationService {
  static final DownloadNotificationService _instance =
      DownloadNotificationService._internal();

  factory DownloadNotificationService() => _instance;

  DownloadNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Progress notification channel
  static const String _progressChannelId = 'musix_download_progress';
  static const String _progressChannelName = 'Download Progress';
  static const String _progressChannelDescription =
      'Shows active music download progress';

  // Completion notification channel
  static const String _completeChannelId = 'musix_download_complete';
  static const String _completeChannelName = 'Download Notifications';
  static const String _completeChannelDescription =
      'Shows completed and failed downloads';

  Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const LinuxInitializationSettings linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const WindowsInitializationSettings windowsSettings =
        WindowsInitializationSettings(
          appName: 'MusiX',
          iconPath: 'assets/default_artwork.png',
          appUserModelId: 'com.anand.musix',
          guid: '27D44D0C-A542-5B90-BCDB-AC3126048BA2',
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  /// Asks the user for notification permission.
  ///
  /// Deliberately NOT part of [initialize]. This blocks until the user answers
  /// a system dialog, so calling it before the first frame freezes the app on
  /// the splash with nothing on screen to answer with. Onboarding calls this
  /// instead, once there is a UI behind it.
  ///
  /// Bounded by a timeout because a permission dialog that never appears would
  /// otherwise strand the user on a dead screen. Declining is a perfectly good
  /// outcome: downloads still work, they just show no progress notification.
  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final status = await Permission.notification.status
          .timeout(const Duration(seconds: 5));

      if (!status.isDenied) {
        return status.isGranted;
      }

      final result = await Permission.notification
          .request()
          .timeout(const Duration(seconds: 30));

      return result.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _createNotificationChannels() async {
    const AndroidNotificationChannel progressChannel =
        AndroidNotificationChannel(
          _progressChannelId,
          _progressChannelName,
          description: _progressChannelDescription,
          importance: Importance.low,
          showBadge: false,
          enableVibration: false,
          playSound: false,
        );

    const AndroidNotificationChannel completeChannel =
        AndroidNotificationChannel(
          _completeChannelId,
          _completeChannelName,
          description: _completeChannelDescription,
          importance: Importance.defaultImportance,
          showBadge: false,
          enableVibration: true,
          playSound: true,
        );

    final AndroidFlutterLocalNotificationsPlugin? android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await android?.createNotificationChannel(progressChannel);
    await android?.createNotificationChannel(completeChannel);
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap here.
  }

  Future<void> showDownloadProgress({
    required int notificationId,
    required String title,
    required String artist,
    required double progress,
    required bool isPaused,
  }) async {
    final int progressPercent = (progress * 100).round().clamp(0, 100);

    final String notificationTitle = isPaused
        ? 'Download paused'
        : 'Downloading';

    final String statusText = isPaused ? 'Paused' : '$progressPercent%';

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _progressChannelId,
          _progressChannelName,
          channelDescription: _progressChannelDescription,
          importance: Importance.low,
          priority: Priority.low,

          showProgress: true,
          maxProgress: 100,
          progress: progressPercent,
          indeterminate: false,

          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,

          showWhen: false,
          channelShowBadge: false,

          enableVibration: false,
          playSound: false,

          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    const LinuxNotificationDetails linuxDetails = LinuxNotificationDetails();

    const WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails();

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );

    await _notifications.show(
      id: notificationId,
      title: notificationTitle,
      body: '$title\n$artist • $statusText',
      notificationDetails: details,
    );
  }

  Future<void> showDownloadComplete({
    required int notificationId,
    required String title,
    required String artist,
  }) async {
    // First remove the ongoing progress notification.
    await _notifications.cancel(id: notificationId);

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _completeChannelId,
          _completeChannelName,
          channelDescription: _completeChannelDescription,

          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,

          ongoing: false,
          autoCancel: true,

          showWhen: true,
          channelShowBadge: false,

          enableVibration: true,
          playSound: true,

          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    const LinuxNotificationDetails linuxDetails = LinuxNotificationDetails();

    const WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails();

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );

    await _notifications.show(
      id: notificationId,
      title: 'Download complete',
      body: '$title\n$artist',
      notificationDetails: details,
    );
  }

  Future<void> showDownloadFailed({
    required int notificationId,
    required String title,
    required String artist,
  }) async {
    await _notifications.cancel(id: notificationId);

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _completeChannelId,
          _completeChannelName,
          channelDescription: _completeChannelDescription,

          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,

          ongoing: false,
          autoCancel: true,

          showWhen: true,
          channelShowBadge: false,

          enableVibration: true,
          playSound: true,

          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );

    const LinuxNotificationDetails linuxDetails = LinuxNotificationDetails();

    const WindowsNotificationDetails windowsDetails =
        WindowsNotificationDetails();

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );

    await _notifications.show(
      id: notificationId,
      title: 'Download failed',
      body: '$title\n$artist',
      notificationDetails: details,
    );
  }

  Future<void> cancelNotification(int notificationId) async {
    await _notifications.cancel(id: notificationId);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
