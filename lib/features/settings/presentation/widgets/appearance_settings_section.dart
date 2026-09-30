import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:dynamic_color/dynamic_color.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/constants/app_dimens.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/app_colors.dart';
import 'settings_item.dart';
import 'settings_surface.dart';
import '../screens/animation_selector_screen.dart';

class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
      SettingsProvider,
      ({bool isDarkMode, Color accentColor, String language})
    >(
      selector: (context, settingsProvider) => (
        isDarkMode: settingsProvider.themeMode == ThemeMode.dark,
        accentColor: settingsProvider.accentColor,
        language: settingsProvider.language,
      ),
      builder: (context, themeData, child) {
        final isDarkMode = themeData.isDarkMode;
        final accentColor = themeData.accentColor;

        return SettingsGroup(
          title: 'appearance_settings'.tr(),
          icon: Icons.palette_rounded,
          isDarkMode: isDarkMode,
          accentColor: accentColor,
          children: [
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.brightness_6_rounded,
                  title: 'theme_card_title'.tr(),
                  showChevron: false,
                  trailing: _buildThemeSelector(
                    context,
                    settingsProvider,
                    isDarkMode,
                    accentColor,
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.palette_rounded,
                  title: 'accent_color_card_title'.tr(),
                  showChevron: false,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: settingsProvider.adaptiveColorEnabled
                            ? 0.5
                            : 1.0,
                        child: Container(
                          width: AppDimens.iconMd,
                          height: AppDimens.iconMd,
                          decoration: BoxDecoration(
                            color: settingsProvider.accentColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: MainScreenColors.getTextColor(
                                isDarkMode,
                              ).withValues(alpha: 0.25),
                              width: AppDimens.borderWidthThin,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimens.spacingSm),
                      SettingsChevron(
                        isDarkMode: isDarkMode,
                        accentColor: accentColor,
                        muted: settingsProvider.adaptiveColorEnabled,
                      ),
                    ],
                  ),
                  onTap: settingsProvider.adaptiveColorEnabled
                      ? null
                      : () => _showColorPickerDialog(
                          context,
                          settingsProvider,
                          isDarkMode,
                        ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            _AdaptiveColorSettingsItem(
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            ),

            SettingsItem(
              icon: Icons.movie_rounded,
              title: 'animation_type'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AnimationSelectorScreen(),
                  ),
                );
              },
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            ),
          ],
        );
      },
    );
  }

  Widget _buildThemeSelector(
    BuildContext context,
    SettingsProvider settingsProvider,
    bool isDarkMode,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: MainScreenColors.getTextColor(
          isDarkMode,
        ).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppDimens.radiusMdLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildThemeButton(
            label: 'Light',
            selected: settingsProvider.theme == 'Light',
            onTap: () => settingsProvider.theme = 'Light',
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
          _buildThemeButton(
            label: 'Dark',
            selected: settingsProvider.theme == 'Dark',
            onTap: () => settingsProvider.theme = 'Dark',
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
          _buildThemeButton(
            label: 'Auto',
            selected: settingsProvider.theme == 'System Default',
            onTap: () => settingsProvider.theme = 'System Default',
            isDarkMode: isDarkMode,
            accentColor: accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDarkMode,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingMd,
          vertical: AppDimens.spacingXs + 1,
        ),
        decoration: BoxDecoration(
          color: selected ? accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.caption(
            isDarkMode: isDarkMode,
            color: selected
                ? Colors.black
                : MainScreenColors.getTextColor(
                    isDarkMode,
                  ).withValues(alpha: 0.7),
          ).copyWith(
            fontWeight: selected
                ? AppTextStyles.weightSemiBold
                : AppTextStyles.weightRegular,
          ),
        ),
      ),
    );
  }

  void _showColorPickerDialog(
    BuildContext context,
    SettingsProvider settingsProvider,
    bool isDarkMode,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode
              ? MainScreenColors.darkSurfaceColor
              : MainScreenColors.lightSurfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          ),
          title: Text(
            'choose_accent_color_dialog_title'.tr(),
            style: AppTextStyles.heading(isDarkMode: isDarkMode),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double itemWidth =
                    AppDimens.thumbnailLarge; // Minimum width per color item
                final int crossAxisCount = (constraints.maxWidth / itemWidth)
                    .floor()
                    .clamp(2, 8);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: AppDimens.spacingLg,
                    mainAxisSpacing: AppDimens.spacingLg,
                  ),
                  itemCount: MainScreenColors.accentColors.length,
                  itemBuilder: (context, index) {
                    final color = MainScreenColors.accentColors[index];
                    return GestureDetector(
                      onTap: () {
                        settingsProvider.accentColor = color;
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(
                            AppDimens.radiusMd,
                          ),
                          border: Border.all(
                            color: settingsProvider.accentColor == color
                                ? MainScreenColors.getTextColor(isDarkMode)
                                : Colors.transparent,
                            width: AppDimens.borderWidthThick,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AdaptiveColorSettingsItem extends StatefulWidget {
  final bool isDarkMode;
  final Color accentColor;

  const _AdaptiveColorSettingsItem({
    required this.isDarkMode,
    required this.accentColor,
  });

  @override
  State<_AdaptiveColorSettingsItem> createState() =>
      _AdaptiveColorSettingsItemState();
}

class _AdaptiveColorSettingsItemState
    extends State<_AdaptiveColorSettingsItem> {
  Future<dynamic>? _adaptiveColorFuture;

  @override
  void initState() {
    super.initState();
    _adaptiveColorFuture = DynamicColorPlugin.getCorePalette();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        return FutureBuilder<dynamic>(
          future: _adaptiveColorFuture,
          builder: (context, snapshot) {
            final dynamic colorData = snapshot.data;
            final bool available =
                snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData &&
                colorData != null;

            if (!available) return const SizedBox.shrink();

            return SettingsToggleItem(
              icon: Icons.auto_awesome,
              title: 'adaptive_color_title'.tr(),
              value: settingsProvider.adaptiveColorEnabled,
              onChanged: (value) async {
                if (value) {
                  Color? dynamicColor;
                  final core = colorData;
                  try {
                    final int? primaryTonal = core.primary.get(40);
                    if (primaryTonal != null) {
                      dynamicColor = Color(primaryTonal);
                    }
                  } catch (_) {}
                  await settingsProvider.setAdaptiveColorEnabled(
                    true,
                    dynamicColor: dynamicColor,
                  );
                } else {
                  await settingsProvider.setAdaptiveColorEnabled(false);
                }
              },
              isDarkMode: widget.isDarkMode,
              accentColor: widget.accentColor,
            );
          },
        );
      },
    );
  }
}
