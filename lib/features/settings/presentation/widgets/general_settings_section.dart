import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../core/providers/settings_provider.dart';
import '../../../../shared/components/app_snackbar.dart';
import '../../../ota/data/providers/ota_provider.dart';
import '../screens/crash_logs_screen.dart';
import '../screens/language_selection_screen.dart';
import '../screens/manage_data_screen.dart';
import 'custom_dropdown.dart';
import 'settings_item.dart';
import 'settings_surface.dart';

class GeneralSettingsSection extends StatelessWidget {
  const GeneralSettingsSection({super.key});

  static const MethodChannel _batteryOptimizationChannel = MethodChannel(
    'com.anand.noize/battery_optimization',
  );

  Future<void> _openDisableRestrictionsSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _batteryOptimizationChannel.invokeMethod<bool>(
        'openDisableRestrictionsSettings',
      );
    } catch (e) {
      debugPrint('Failed to open battery restriction settings: $e');
    }
  }

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
          title: 'general_settings'.tr(),
          icon: Icons.tune_rounded,
          isDarkMode: isDarkMode,
          accentColor: accentColor,
          children: [
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (Platform.isAndroid || Platform.isIOS) {
                    try {
                      PermissionStatus status =
                          await Permission.notification.status;
                      if (!status.isGranted &&
                          settingsProvider.notificationsEnabled) {
                        settingsProvider.notificationsEnabled = false;
                      }
                    } catch (e) {
                      debugPrint(
                        'Notification permission check failed: $e',
                      );

                      if (!Platform.isAndroid && !Platform.isIOS) {
                        settingsProvider.notificationsEnabled = false;
                      }
                    }
                  }
                });

                Future<void> handleNotificationToggle(bool value) async {
                  if (!value) {
                    settingsProvider.notificationsEnabled = false;
                    return;
                  }

                  if (Platform.isAndroid || Platform.isIOS) {
                    try {
                      PermissionStatus status =
                          await Permission.notification.status;

                      if (status.isGranted) {
                        settingsProvider.notificationsEnabled = true;
                      } else {
                        PermissionStatus requestStatus = await Permission
                            .notification
                            .request();

                        if (requestStatus.isGranted) {
                          settingsProvider.notificationsEnabled = true;
                        } else {
                          settingsProvider.notificationsEnabled = false;
                          if (!context.mounted) return;
                          AppSnackBar.showWarning(
                            context,
                            'notification_permission_required_to_enable_notifications'
                                .tr(),
                            action: SnackBarAction(
                              label: 'settings'.tr(),
                              textColor: accentColor,
                              onPressed: openAppSettings,
                            ),
                          );
                        }
                      }
                    } on MissingPluginException catch (e) {
                      debugPrint(
                        'Notification permission API not available: $e',
                      );
                      settingsProvider.notificationsEnabled = true;
                    } catch (e) {
                      debugPrint(
                        'Error while checking/requesting notification permission: $e',
                      );
                      settingsProvider.notificationsEnabled = false;
                    }
                  } else {
                    settingsProvider.notificationsEnabled = true;
                  }
                }

                return SettingsToggleItem(
                  icon: Icons.notifications_rounded,
                  title: 'notifications_card_title'.tr(),
                  value: settingsProvider.notificationsEnabled,
                  onChanged: handleNotificationToggle,
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            if (Platform.isAndroid)
              _BatteryOptimizationStatusTile(
                isDarkMode: isDarkMode,
                accentColor: accentColor,
                onOpenSettings: _openDisableRestrictionsSettings,
              ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.language_rounded,
                  title: 'language_card_title'.tr(),
                  subtitle: settingsProvider.language,
                  trailing: SettingsChevron(isDarkMode: isDarkMode),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LanguageSelectionScreen(),
                      ),
                    );
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsToggleItem(
                  icon: Icons.system_update_rounded,
                  title: 'automatic_update_checks'.tr(),
                  value: settingsProvider.updateCheckEnabled,
                  onChanged: (value) {
                    settingsProvider.updateCheckEnabled = value;
                  },
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return SettingsItem(
                  icon: Icons.alt_route_rounded,
                  title: 'update_channel'.tr(),
                  showChevron: false,
                  trailing: CustomDropdown<String>(
                    value: settingsProvider.updateChannel,
                    items: const ['stable', 'beta'],
                    onChanged: (value) {
                      if (value != null) {
                        settingsProvider.updateChannel = value;
                        final otaProvider = Provider.of<OTAProvider>(
                          context,
                          listen: false,
                        );
                        otaProvider.setUpdateChannel(value);
                        if (settingsProvider.updateCheckEnabled) {
                          otaProvider.checkForUpdates();
                        }
                      }
                    },
                    isDarkMode: isDarkMode,
                    accentColor: accentColor,
                  ),
                  isDarkMode: isDarkMode,
                  accentColor: accentColor,
                );
              },
            ),

            SettingsItem(
              icon: Icons.storage_rounded,
              title: 'manage_data'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ManageDataScreen()),
                );
              },
              isDarkMode: isDarkMode,
              accentColor: accentColor,
            ),

            SettingsItem(
              icon: Icons.bug_report_rounded,
              title: 'crash_logs_title'.tr(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CrashLogsScreen(),
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
}

class _BatteryOptimizationStatusTile extends StatefulWidget {
  final bool isDarkMode;
  final Color accentColor;
  final Future<void> Function() onOpenSettings;

  const _BatteryOptimizationStatusTile({
    required this.isDarkMode,
    required this.accentColor,
    required this.onOpenSettings,
  });

  @override
  State<_BatteryOptimizationStatusTile> createState() =>
      _BatteryOptimizationStatusTileState();
}

class _BatteryOptimizationStatusTileState
    extends State<_BatteryOptimizationStatusTile>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isDisabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final value = await GeneralSettingsSection._batteryOptimizationChannel
          .invokeMethod<bool>('isBatteryOptimizationDisabled')
          .timeout(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        _isDisabled = value ?? false;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Battery optimization status refresh failed: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _isLoading
        ? '...'
        : _isDisabled
        ? 'battery_optimization_status_disabled'.tr()
        : 'battery_optimization_status_enabled'.tr();

    return SettingsItem(
      icon: Icons.battery_charging_full_rounded,
      title: 'battery_optimization_card_title'.tr(),
      subtitle: statusText,
      trailing: SettingsChevron(isDarkMode: widget.isDarkMode),
      onTap: () async {
        try {
          await widget.onOpenSettings();
          await _refreshStatus();
        } catch (e) {
          debugPrint('Error opening battery optimization settings: $e');
        }
      },
      isDarkMode: widget.isDarkMode,
      accentColor: widget.accentColor,
    );
  }
}
