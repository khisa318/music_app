import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Sends crash reports to a Telegram bot.
///
/// Reports are deduplicated by a fingerprint of the error and the top of its
/// stack trace. Each unique crash is delivered at most
/// [maxReportsPerFingerprint] times (a single report is normally enough), and
/// an hourly budget protects the bot from crash loops that keep producing new
/// errors.
class TelegramCrashReporter {
  TelegramCrashReporter({required this.logHeader, http.Client? client})
    : _client = client ?? http.Client();

  final String Function() logHeader;
  final http.Client _client;

  static const String _botTokenEnv = String.fromEnvironment(
    'TELEGRAM_CRASH_BOT_TOKEN',
  );
  static const String _chatIdEnv = String.fromEnvironment(
    'TELEGRAM_CRASH_CHAT_ID',
  );

  static const String _botTokenPrefsKey = 'telegram_crash_bot_token';
  static const String _chatIdPrefsKey = 'telegram_crash_chat_id';

  static const int maxReportsPerFingerprint = 2;
  static const int _maxReportsPerHour = 12;

  static const String _countPrefix = 'telegram_crash_count_';
  static const String _sendTimesKey = 'telegram_crash_send_times';

  final Set<String> _inFlight = {};

  Future<String> _getBotToken() async {
    if (_botTokenEnv.isNotEmpty) return _botTokenEnv;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_botTokenPrefsKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return '';
  }

  Future<String> _getChatId() async {
    if (_chatIdEnv.isNotEmpty) return _chatIdEnv;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_chatIdPrefsKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return '';
  }

  Future<bool> get isConfigured async {
    final token = await _getBotToken();
    final chatId = await _getChatId();
    return token.isNotEmpty && chatId.isNotEmpty;
  }

  static Future<void> saveCredentials({
    required String botToken,
    required String chatId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_botTokenPrefsKey, botToken.trim());
    await prefs.setString(_chatIdPrefsKey, chatId.trim());
  }

  static Future<Map<String, String>> getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_botTokenPrefsKey) ?? '';
    final chatId = prefs.getString(_chatIdPrefsKey) ?? '';
    return {'botToken': token, 'chatId': chatId};
  }

  Future<bool> report(Object error, StackTrace stack, {String? context}) async {
    final token = await _getBotToken();
    final chatId = await _getChatId();
    if (token.isEmpty || chatId.isEmpty) return false;

    final fingerprint = _fingerprint(error, stack);
    if (_inFlight.contains(fingerprint)) return false;

    _inFlight.add(fingerprint);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sent = prefs.getInt('$_countPrefix$fingerprint') ?? 0;

      // One report is enough, but allow a second one in case the first arrived
      // while details were still missing.
      if (sent >= maxReportsPerFingerprint) return false;
      if (!_isWithinHourlyBudget(prefs)) return false;

      final delivered = await _send(
        token,
        chatId,
        _buildMessage(error, stack, context: context, occurrence: sent + 1),
      );

      if (delivered) {
        await prefs.setInt('$_countPrefix$fingerprint', sent + 1);
        await _recordSendTime(prefs);
      }

      return delivered;
    } catch (_) {
      return false;
    } finally {
      _inFlight.remove(fingerprint);
    }
  }

  void dispose() {
    _client.close();
  }

  String _fingerprint(Object error, StackTrace stack) {
    final frames = stack
        .toString()
        .split('\n')
        .take(8)
        .map((line) => line.trim())
        .join('\n');
    return sha256
        .convert(utf8.encode('${error.runtimeType}|$error|$frames'))
        .toString();
  }

  bool _isWithinHourlyBudget(SharedPreferences prefs) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 1));
    final recent = _readSendTimes(
      prefs,
    ).where((time) => time.isAfter(cutoff)).toList(growable: false);
    return recent.length < _maxReportsPerHour;
  }

  Future<void> _recordSendTime(SharedPreferences prefs) async {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 1));
    final recent = _readSendTimes(
      prefs,
    ).where((time) => time.isAfter(cutoff)).toList()..add(now);
    await prefs.setString(
      _sendTimesKey,
      jsonEncode(recent.map((time) => time.toIso8601String()).toList()),
    );
  }

  List<DateTime> _readSendTimes(SharedPreferences prefs) {
    final raw = prefs.getString(_sendTimesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<String>()
          .map(DateTime.tryParse)
          .whereType<DateTime>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _buildMessage(
    Object error,
    StackTrace stack, {
    String? context,
    required int occurrence,
  }) {
    final buffer = StringBuffer()
      ..writeln('<b>MusiX crash report</b>')
      ..writeln(
        '<b>Report:</b> $occurrence of $maxReportsPerFingerprint '
        'for this error',
      )
      ..writeln('<b>Time:</b> ${DateTime.now().toIso8601String()}');

    if (context != null && context.isNotEmpty) {
      buffer.writeln('<b>Context:</b> ${_escape(context)}');
    }

    buffer
      ..writeln()
      ..writeln('<b>Error</b>')
      ..writeln('<pre>${_escape(error.toString())}</pre>')
      ..writeln('<b>Stack</b>')
      ..writeln('<pre>${_escape(stack.toString())}</pre>');

    final header = logHeader().trim();
    if (header.isNotEmpty) {
      buffer
        ..writeln('<b>App / device</b>')
        ..writeln('<pre>${_escape(header)}</pre>');
    }

    const limit = 3900;
    final message = buffer.toString();
    if (message.length <= limit) return message;
    return '${message.substring(0, limit)}\n...[truncated]';
  }

  String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  Future<bool> _send(String token, String chatId, String text) async {
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
            body: {
              'chat_id': chatId,
              'text': text,
              'parse_mode': 'HTML',
              'disable_web_page_preview': 'true',
            },
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
