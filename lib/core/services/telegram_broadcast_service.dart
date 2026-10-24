import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'download_notification_service.dart';

class TelegramBroadcastService {
  TelegramBroadcastService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  Timer? _timer;
  bool _isRunning = false;
  bool _isPolling = false;

  static const String _botTokenPrefsKey = 'telegram_broadcast_bot_token';
  static const String _chatIdPrefsKey = 'telegram_broadcast_chat_id';
  static const String _enabledPrefsKey = 'telegram_broadcast_enabled';
  static const String _lastUpdateIdKey = 'telegram_broadcast_last_update_id';
  static const String _botTokenEnv = String.fromEnvironment(
    'TELEGRAM_CRASH_BOT_TOKEN',
  );
  static const String _chatIdEnv = String.fromEnvironment(
    'TELEGRAM_CRASH_CHAT_ID',
  );

  static Future<void> saveConfig({
    required String botToken,
    required String chatId,
    required bool enabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_botTokenPrefsKey, botToken.trim());
    await prefs.setString(_chatIdPrefsKey, chatId.trim());
    await prefs.setBool(_enabledPrefsKey, enabled);
  }

  static Future<Map<String, dynamic>> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _botTokenEnv.isNotEmpty
        ? _botTokenEnv
        : prefs.getString(_botTokenPrefsKey) ?? '';
    final chatId = _chatIdEnv.isNotEmpty
        ? _chatIdEnv
        : prefs.getString(_chatIdPrefsKey) ?? '';
    return {
      'botToken': token,
      'chatId': chatId,
      'enabled': prefs.getBool(_enabledPrefsKey) ?? (token.isNotEmpty),
    };
  }

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    await _poll();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
  }

  Future<void> _poll() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      final config = await getConfig();
      final token = config['botToken'] as String;
      final allowedChatId = config['chatId'] as String;
      final enabled = config['enabled'] as bool;
      if (!enabled || token.isEmpty || allowedChatId.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final lastUpdateId = prefs.getInt(_lastUpdateIdKey) ?? 0;
      Future<void> advanceUpdate(int? updateId) async {
        if (updateId != null && updateId > lastUpdateId) {
          await prefs.setInt(_lastUpdateIdKey, updateId);
        }
      }

      final uri = Uri.parse(
        'https://api.telegram.org/bot$token/getUpdates?timeout=1&offset=${lastUpdateId + 1}',
      );
      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        _isPolling = false;
        return;
      }

      final data = jsonDecode(res.body);
      if (data is! Map || data['ok'] != true) {
        _isPolling = false;
        return;
      }
      final result = data['result'];
      if (result is! List || result.isEmpty) {
        _isPolling = false;
        return;
      }

      for (final update in result) {
        if (update is! Map) continue;
        final updateId = update['update_id'];

        final message = update['message'] ?? update['channel_post'];
        if (message is! Map) {
          await advanceUpdate(updateId is int ? updateId : null);
          continue;
        }

        final chat = message['chat'];
        if (chat is! Map || chat['id']?.toString() != allowedChatId) {
          await advanceUpdate(updateId is int ? updateId : null);
          continue;
        }

        final text = message['text']?.toString() ?? '';
        if (text.isEmpty) {
          await advanceUpdate(updateId is int ? updateId : null);
          continue;
        }

        try {
          final shown = await DownloadNotificationService().showTelegramMessage(
            title: 'Telegram',
            body: text,
          );
          if (!shown) break;
          await advanceUpdate(updateId is int ? updateId : null);
        } catch (e) {
          debugPrint('Failed to show telegram broadcast: $e');
          break;
        }
      }
    } catch (e) {
      debugPrint('Telegram broadcast poll error: $e');
    } finally {
      _isPolling = false;
    }
  }

  void dispose() {
    stop();
    _client.close();
  }
}
