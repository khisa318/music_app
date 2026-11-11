import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'download_notification_service.dart';

/// Handles messages that arrive while the app is in the background or killed.
///
/// Android renders notification payloads itself, so there is nothing to show
/// here. Registering the handler keeps data-only messages working if they are
/// added later. It must be a top-level function annotated for the background
/// isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    'Push message received in background: ${message.messageId ?? 'unknown'}',
  );
}

/// Subscribes the device to the MusiX broadcast topic and shows messages that
/// arrive while the app is open.
///
/// Telegram messages are no longer polled by the app. A Cloud Function receives
/// the Telegram webhook and publishes one FCM message to [broadcastTopic]; FCM
/// delivers it to every installed app.
class PushNotificationService {
  PushNotificationService({
    DownloadNotificationService? notifications,
  }) : _notifications = notifications ?? DownloadNotificationService();

  /// Must match `FCM_BROADCAST_TOPIC` in the Cloud Functions configuration.
  static const String broadcastTopic = 'musix_broadcasts';

  final DownloadNotificationService _notifications;

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Initializes Firebase, subscribes to the broadcast topic, and wires the
  /// foreground message handler.
  ///
  /// Returns false when Firebase is not configured (for example a local build
  /// without `google-services.json`). The app keeps working; it just does not
  /// receive push messages.
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final messaging = FirebaseMessaging.instance;

      // Notification permission is requested during onboarding, where there is
      // UI behind the system dialog. Subscribing does not need the permission,
      // so an existing user whose permission is already granted starts
      // receiving broadcasts immediately.
      await messaging.subscribeToTopic(broadcastTopic);

      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );

      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        _showForegroundMessage,
      );

      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleMessageOpened,
      );

      // A notification tapped while the app was terminated is delivered through
      // this future instead of the stream above.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpened(initialMessage);
      }

      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('Push notifications unavailable: $e');
      return false;
    }
  }

  void _showForegroundMessage(RemoteMessage message) {
    final notification = message.notification;

    final title = notification?.title ?? _dataString(message, 'title');
    final body = notification?.body ?? _dataString(message, 'body');

    if (body.isEmpty) return;

    unawaited(
      _notifications.showBroadcastMessage(
        title: title.isEmpty ? 'MusiX' : title,
        body: body,
      ),
    );
  }

  void _handleMessageOpened(RemoteMessage message) {
    // Broadcasts only carry a title and body today, so there is nothing to
    // navigate to. Keeping the hook means a future `link` field can open it
    // without reworking the delivery path.
    debugPrint('Push message opened: ${message.messageId ?? 'unknown'}');
  }

  String _dataString(RemoteMessage message, String key) {
    final value = message.data[key];
    return value is String ? value : '';
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _foregroundSubscription = null;
    _openedSubscription = null;
    _initialized = false;
  }
}
