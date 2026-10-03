import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_dimens.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/errors/network_failure.dart';

enum AppSnackBarType { info, success, error, warning }

/// The retry button inside a snackbar.
///
/// SnackBar's own `action` slot is laid out with an unbounded width, so a
/// translated label as long as "إعادة المحاولة" claims the whole bar and leaves
/// the message a few pixels. Being a child of the content row instead means the
/// label gets a cap and the message keeps the rest.
class _SnackBarActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  /// Wide enough for most one-word labels, narrow enough that the message
  /// beside it stays readable on a small screen.
  static const double _maxLabelWidth = 128;

  const _SnackBarActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: _maxLabelWidth),
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingSm),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: AppTextStyles.actionLabel().copyWith(color: Colors.white),
      ),
    ),
  );
}

class AppSnackBar {
  AppSnackBar._();

  static Color _bgColor(AppSnackBarType type, {Color? accentColor}) {
    switch (type) {
      case AppSnackBarType.success:
        return accentColor ?? const Color(0xFF2E7D32); // deep green
      case AppSnackBarType.error:
        return const Color(0xFFC62828); // dark red
      case AppSnackBarType.warning:
        return const Color(0xFFE65100); // deep orange
      case AppSnackBarType.info:
        return accentColor ?? const Color(0xFF37474F); // blue-grey
    }
  }

  static IconData _icon(AppSnackBarType type) {
    switch (type) {
      case AppSnackBarType.success:
        return Icons.check_circle_rounded;
      case AppSnackBarType.error:
        return Icons.error_rounded;
      case AppSnackBarType.warning:
        return Icons.warning_amber_rounded;
      case AppSnackBarType.info:
        return Icons.info_rounded;
    }
  }

  static void show(
    BuildContext context,
    String message, {
    AppSnackBarType type = AppSnackBarType.info,
    Color? accentColor,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final bg = _bgColor(type, accentColor: accentColor);
    final effectiveDuration =
        duration ??
        (type == AppSnackBarType.error || type == AppSnackBarType.warning
            ? const Duration(seconds: 4)
            : const Duration(seconds: 3));

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(_icon(type), color: Colors.white, size: AppDimens.iconMd),
              SizedBox(width: AppDimens.spacingMd),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.bodyMd().copyWith(
                    color: Colors.white,
                    fontWeight: AppTextStyles.weightMedium,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onAction != null && actionLabel != null)
                _SnackBarActionButton(label: actionLabel, onPressed: onAction),
            ],
          ),
          backgroundColor: bg,
          duration: effectiveDuration,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(AppDimens.paddingLg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          elevation: AppDimens.elevationMedium,
        ),
      );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    Color? accentColor,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    type: AppSnackBarType.success,
    accentColor: accentColor,
    duration: duration,
    actionLabel: actionLabel,

    onAction: onAction,
  );

  static void showError(
    BuildContext context,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    type: AppSnackBarType.error,
    duration: duration,
    actionLabel: actionLabel,

    onAction: onAction,
  );

  static void showWarning(
    BuildContext context,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    type: AppSnackBarType.warning,
    duration: duration,
    actionLabel: actionLabel,

    onAction: onAction,
  );

  static void showInfo(
    BuildContext context,
    String message, {
    Color? accentColor,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    message,
    type: AppSnackBarType.info,
    accentColor: accentColor,
    duration: duration,
    actionLabel: actionLabel,

    onAction: onAction,
  );

  /// Reports a failed request in the reader's terms rather than the
  /// transport's.
  ///
  /// [onRetry] is offered only when [NetworkFailure.canRetry] allows it, so a
  /// rejected request never shows a retry button that cannot help.
  static void showNetworkError(
    BuildContext context,
    Object error, {
    VoidCallback? onRetry,
    Duration? duration,
  }) {
    final failure = NetworkFailure.classify(error);

    show(
      context,
      failure.messageKey.tr(),
      type: AppSnackBarType.error,
      duration: duration,
      actionLabel: 'retry'.tr(),
      onAction: onRetry != null && failure.canRetry ? onRetry : null,
    );
  }
}
