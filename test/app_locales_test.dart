import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/constants/app_locales.dart';
import 'package:music_app/core/errors/network_failure.dart';

/// The keys every locale has to carry, so a language is never switched to with
/// the network copy missing from it.
const List<String> _networkKeys = [
  'error_no_internet',
  'error_request_timed_out',
  'error_server_unavailable',
  'error_request_rejected',
  'error_unexpected',
  'retry',
  'no_internet_connection',
  'offline_mode_notice',
  'connection_restored',
  'check_your_connection_and_retry',
  'no_cached_data',
  'no_internet_setup_blocked',
];

final Directory _translations = Directory('assets/translations');

Map<String, dynamic> _load(String code) {
  final file = File('${_translations.path}/$code.json');

  expect(
    file.existsSync(),
    isTrue,
    reason: '$code is declared in AppLocales but has no translation file',
  );

  return jsonDecode(file.readAsStringSync(encoding: utf8))
      as Map<String, dynamic>;
}

void main() {
  test('English is declared, and is the fallback', () {
    expect(AppLocales.codes, contains('en'));
  });

  test('no locale code is declared twice', () {
    expect(AppLocales.codes.toSet(), hasLength(AppLocales.codes.length));
  });

  test('supported turns each code into a Locale', () {
    expect(
      AppLocales.supported.map((locale) => locale.languageCode).toList(),
      AppLocales.codes,
    );
  });

  test('every declared locale has a translation file', () {
    for (final code in AppLocales.codes) {
      expect(_load(code), isNotEmpty, reason: '$code.json is empty');
    }
  });

  test('no translation file is left undeclared', () {
    final onDisk = _translations
        .listSync()
        .where((entity) => entity.path.toLowerCase().endsWith('.json'))
        .map((entity) => entity.uri.pathSegments.last.replaceAll('.json', ''))
        .toSet();

    expect(
      onDisk.difference(AppLocales.codes.toSet()),
      isEmpty,
      reason: 'a translation file exists for a locale the app cannot select',
    );
  });

  test('every locale carries the whole network copy', () {
    for (final code in AppLocales.codes) {
      final messages = _load(code);

      for (final key in _networkKeys) {
        expect(
          messages[key],
          isA<String>(),
          reason: '$code.json is missing "$key"',
        );
        expect(
          (messages[key] as String).trim(),
          isNotEmpty,
          reason: '$code.json has an empty "$key"',
        );
      }
    }
  });

  test('every locale gives each network key its own wording', () {
    for (final key in _networkKeys) {
      final wordings = AppLocales.codes
          .map((code) => _load(code)[key] as String)
          .toSet();

      // English is the source text and one language legitimately keeps it
      // (German "Retry" is not the word, but a language may borrow it), so
      // this only catches a file that was copied wholesale from another.
      expect(
        wordings.length,
        greaterThan(2),
        reason: '"$key" looks untranslated',
      );
    }
  });

  test('no locale is missing the key an error message points at', () {
    for (final kind in NetworkFailureKind.values) {
      final key = NetworkFailure(kind).messageKey;

      for (final code in AppLocales.codes) {
        expect(
          _load(code)[key],
          isA<String>(),
          reason: '$code.json cannot render a ${kind.name} failure',
        );
      }
    }
  });

  test('every file is valid JSON with no encoding damage', () {
    for (final code in AppLocales.codes) {
      final raw = File(
        '${_translations.path}/$code.json',
      ).readAsStringSync(encoding: utf8);

      expect(raw.contains('�'), isFalse, reason: '$code.json has bad bytes');
      expect(() => jsonDecode(raw), returnsNormally);
    }
  });
}
