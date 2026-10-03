import 'dart:ui';

/// The languages the app ships a translation file for.
///
/// One list, used by `EasyLocalization` to decide what it may switch to and by
/// the language picker to decide what it may ask for. They used to be two
/// separate hand-kept lists that disagreed, which is how a language ended up
/// being offered in the picker while EasyLocalization still considered it
/// undeclared.
class AppLocales {
  AppLocales._();

  /// Locale codes, each with a matching `assets/translations/<code>.json`.
  static const List<String> codes = [
    'en',
    'ar',
    'bn',
    'de',
    'es',
    'fr',
    'gu',
    'hi',
    'id',
    'ja',
    'kn',
    'ko',
    'mr',
    'pt',
    'ru',
    'ta',
    'te',
    'tr',
    'uk',
    'ur',
    'vi',
    'zh',
  ];

  static List<Locale> get supported =>
      codes.map(Locale.new).toList(growable: false);
}
