import 'package:flutter/material.dart';

class MainScreenColors {
  static const primaryPurple = Color(0xFFC042FF);
  static const secondaryPink = Color(0xFFFF4FE3);
  static const skyBlue = Color(0xFF7A5CFF);
  static const backgroundColor = Color(0xFF140D21);
  static const textColor = Color(0xFFFFFFFF);

  static const darkPrimaryPurple = Color(0xFFC042FF);
  static const darkSecondaryPink = Color(0xFFFF4FE3);
  static const darkBackgroundColor = Color(0xFF140D21);
  static const darkSurfaceColor = Color(0xFF211334);
  static const darkTextColor = Color(0xFFFFFFFF);
  static const surfaceColor = Color(0xFF2A2A2A);
  static const darkTirtiaryColor = Color(0xFF63FF6C);

  static const lightPrimaryPurple = Color(0xFFC042FF);
  static const lightSecondaryPink = Color(0xFFFF4FE3);
  static const lightBackgroundColor = Color(0xFFF8F1FF);
  static const lightSurfaceColor = Color(0xFFFFFFFF);
  static const lightTextColor = Color(0xFF000000);
  static const lightTirtiaryColor = Color(0xFF63FF6C);

  static const List<Color> accentColors = [
    secondaryPink,
    skyBlue,
    Color(0xFFFF6363),
    Color(0xFF6C63FF),
    Color(0xFFB863FF),
    Color(0xFFFF63FF),
    Color(0xFFB8860B),
    Color(0xFF3F51B5),
    Color(0xFFFF7F50),
    Color(0xFF808000),
  ];

  static Color getPrimaryColor(bool isDarkMode) =>
      isDarkMode ? darkPrimaryPurple : lightPrimaryPurple;

  static Color getSecondaryColor(bool isDarkMode) =>
      isDarkMode ? darkSecondaryPink : lightSecondaryPink;

  static Color getTirtiaryColor(bool isDarkMode) =>
      isDarkMode ? darkTirtiaryColor : lightTirtiaryColor;

  static Color getBackgroundColor(bool isDarkMode) =>
      isDarkMode ? darkBackgroundColor : lightBackgroundColor;

  static Color getSurfaceColor(bool isDarkMode) =>
      isDarkMode ? darkSurfaceColor : lightSurfaceColor;

  static Color getTextColor(bool isDarkMode) =>
      isDarkMode ? darkTextColor : lightTextColor;
}
