import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/connectivity_provider.dart';
import 'connectivity_status_widget.dart';

/// Announces the app going offline and coming back.
///
/// Wrapped around the whole app just under `MaterialApp`, so a connection that
/// drops while the reader is anywhere in the app is reported once, rather than
/// each screen discovering it on its own next request.
class ConnectivityListener extends StatefulWidget {
  final Widget child;

  const ConnectivityListener({super.key, required this.child});

  @override
  State<ConnectivityListener> createState() => _ConnectivityListenerState();
}

class _ConnectivityListenerState extends State<ConnectivityListener> {
  ConnectivityProvider? _connectivity;
  bool? _wasConnected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final connectivity = context.read<ConnectivityProvider>();

    if (identical(connectivity, _connectivity)) {
      return;
    }

    _connectivity?.removeListener(_onConnectivityChanged);
    _connectivity = connectivity..addListener(_onConnectivityChanged);

    // The state the app starts in is adopted silently: a launch with no
    // connection is not news, and the screen that needs the network says so
    // itself. Only a change from here on is worth a snackbar.
    _wasConnected = connectivity.isConnected;
  }

  void _onConnectivityChanged() {
    final connectivity = _connectivity;

    if (connectivity == null || !connectivity.isInitialized) {
      return;
    }

    final isConnected = connectivity.isConnected;

    if (_wasConnected == null || isConnected == _wasConnected) {
      _wasConnected = isConnected;
      return;
    }

    _wasConnected = isConnected;

    // Rebuilds land us here, and a snackbar cannot be shown mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ConnectivitySnackBar.show(context, isConnected);
    });
  }

  @override
  void dispose() {
    _connectivity?.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
