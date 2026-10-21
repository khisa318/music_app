import 'package:flutter/material.dart';

import 'animation_1.dart';
import 'animation_2.dart';
import 'animation_3.dart';
import 'animation_4.dart';
import 'animation_5.dart';

/// The animation names a background can be set to, in the order the settings
/// picker shows them.
///
/// 'Default' is the built-in drift painted by `AnimatedAppBackground`; the
/// player screen treats it as its own gradient. Kept in one place so the
/// picker, the player and the app-wide background cannot drift apart.
class BackgroundAnimations {
  const BackgroundAnimations._();

  static const String defaultAnimation = 'Default';

  /// Retained for settings saved before 'static' was folded into 'Default':
  /// `SettingsProvider.loadSettings` normalises it away on read, but the
  /// selector still lists it so an in-flight pick cannot be lost.
  static const String staticAnimation = 'static';

  static const List<String> options = <String>[
    defaultAnimation,
    'Animation 1',
    'Animation 2',
    'Animation 3',
    'Animation 4',
    'Animation 5',
    staticAnimation,
  ];

  static const Map<String, String> descriptions = <String, String>{
    defaultAnimation: 'static_animation_description',
    'Animation 1': 'animation_1_description',
    'Animation 2': 'animation_2_description',
    'Animation 3': 'animation_3_description',
    'Animation 4': 'animation_4_description',
    'Animation 5': 'animation_5_description',
    staticAnimation: 'static_animation_description',
  };
}

/// Whether [animationType] names one of the numbered animation widgets rather
/// than the caller's own default backdrop.
bool isNumberedBackgroundAnimation(String animationType) =>
    backgroundAnimationNames.contains(animationType);

/// The names handled by [buildBackgroundAnimation].
const Set<String> backgroundAnimationNames = <String>{
  'Animation 1',
  'Animation 2',
  'Animation 3',
  'Animation 4',
  'Animation 5',
};

/// Builds the animated background widget for [animationType], or null when the
/// caller should paint its own default.
///
/// Returns null for 'Default' and 'static' so the app-wide background keeps
/// using its purpose-built painter (and the player its own gradient) rather
/// than one of the standalone animation widgets. [isAnimating] is threaded
/// through so the reduce-effects setting can freeze them.
Widget? buildBackgroundAnimation({
  required String animationType,
  required Color backgroundColor,
  required Color accentColor,
  required bool isAnimating,
}) {
  switch (animationType) {
    case 'Animation 1':
      return Animation1(
        backgroundColor: backgroundColor,
        accentColor: accentColor,
        isAnimating: isAnimating,
      );
    case 'Animation 2':
      return Animation2(
        backgroundColor: backgroundColor,
        accentColor: accentColor,
        isAnimating: isAnimating,
      );
    case 'Animation 3':
      return Animation3(
        backgroundColor: backgroundColor,
        accentColor: accentColor,
        isAnimating: isAnimating,
      );
    case 'Animation 4':
      return Animation4(
        backgroundColor: backgroundColor,
        accentColor: accentColor,
        isAnimating: isAnimating,
      );
    case 'Animation 5':
      return Animation5(
        backgroundColor: backgroundColor,
        accentColor: accentColor,
        isAnimating: isAnimating,
      );
    default:
      return null;
  }
}
