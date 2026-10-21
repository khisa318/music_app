import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// The app-wide animated background: a slow drift of coloured glows and
/// floating particles over a theme-aware base gradient.
///
/// Mounted exactly once, behind the navigator, by [MusiXApp]'s `MaterialApp`
/// builder. Every screen reveals it by using a transparent scaffold, which is
/// what [AppTheme] sets `scaffoldBackgroundColor` to. Keeping the background in
/// one place means the whole app shares a single animation ticker instead of
/// each screen spinning up its own.
class AnimatedAppBackground extends StatefulWidget {
  const AnimatedAppBackground({super.key});

  @override
  State<AnimatedAppBackground> createState() => _AnimatedAppBackgroundState();
}

class _AnimatedAppBackgroundState extends State<AnimatedAppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    // Deliberately slow. The background is meant to breathe, not demand
    // attention, and a long period keeps the per-frame work cheap.
    // The ticker is started from build() so the "reduce effects" setting can
    // keep it fully stopped instead of painting a still frame every 16ms.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool reduced = context.select<SettingsProvider, bool>(
      (settings) => settings.reduceEffectsEnabled,
    );

    if (reduced) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _AnimatedBackgroundPainter(
            animation: reduced ? null : _controller,
            reduced: reduced,
            isDarkMode: theme.brightness == Brightness.dark,
            accent: theme.extension<MusiXAccent>()?.color,
          ),
        ),
      ),
    );
  }
}

class _AnimatedBackgroundPainter extends CustomPainter {
  _AnimatedBackgroundPainter({
    required this.animation,
    required this.reduced,
    required this.isDarkMode,
    this.accent,
  }) : super(repaint: animation);

  /// Null while effects are reduced: the still frame is painted once and
  /// never repainted, instead of re-painting every tick of the controller.
  final Animation<double>? animation;

  /// True when the user asked for reduced effects: paint a calm still image
  /// (no drifting particles) and let the ticker stay stopped.
  final bool reduced;

  final bool isDarkMode;
  final Color? accent;

  static final math.Random _random = math.Random(7);

  static final List<_Particle> _particles = List<_Particle>.generate(
    14,
    (_) => _Particle(
      x: _random.nextDouble(),
      y: _random.nextDouble(),
      radius: 1.2 + _random.nextDouble() * 3.2,
      speed: 0.25 + _random.nextDouble() * 0.65,
      phase: _random.nextDouble() * 2 * math.pi,
    ),
    growable: false,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation?.value ?? 0;

    _paintBase(canvas, size);
    _paintBlobs(canvas, size, t);
    _paintSunlight(canvas, size, t);
    if (!reduced) {
      _paintParticles(canvas, size, t);
    }
  }

  void _paintBase(Canvas canvas, Size size) {
    const darkStops = <double>[0, 0.35, 0.65, 1];
    const darkColors = <Color>[
      Color(0xFF04060F),
      Color(0xFF0B0714),
      Color(0xFF140D21),
      Color(0xFF0B0714),
    ];
    const lightColors = <Color>[
      Color(0xFFF7F0FF),
      Color(0xFFFFFFFF),
      Color(0xFFF1E9FF),
    ];

    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDarkMode ? darkColors : lightColors,
        stops: isDarkMode ? darkStops : null,
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  void _paintBlobs(Canvas canvas, Size size, double t) {
    final blobs = _blobSpecs();
    final intensity = isDarkMode ? 1.0 : 0.55;

    for (var i = 0; i < blobs.length; i++) {
      final blob = blobs[i];
      final phase = t * 2 * math.pi + i * 1.9;
      final center = Offset(
        size.width * (0.5 + 0.32 * math.sin(phase * blob.speed + i)),
        size.height * (0.5 + 0.30 * math.cos(phase * blob.speed + i * 1.3)),
      );
      final pulse = 0.85 + 0.15 * math.sin(phase * 1.4 + i);
      final radius = size.shortestSide * blob.radius * pulse;
      final alpha = (blob.alpha * intensity).clamp(0.0, 1.0);

      if (radius <= 0 || alpha <= 0) {
        continue;
      }

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            blob.color.withValues(alpha: alpha),
            blob.color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintSunlight(Canvas canvas, Size size, double t) {
    final wave = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final alpha = (isDarkMode ? 0.10 : 0.05) * (0.6 + 0.4 * wave);
    final center = Offset(size.width * 0.62, size.height * 0.05);
    final radius = size.shortestSide * 0.8;
    final glow = accent ?? const Color(0xFF7A5CFF);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          glow.withValues(alpha: alpha),
          glow.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  void _paintParticles(Canvas canvas, Size size, double t) {
    final color = isDarkMode
        ? const Color(0xFF9DBBFF)
        : const Color(0xFF7A5CFF);
    final baseAlpha = isDarkMode ? 0.30 : 0.14;

    for (final particle in _particles) {
      final y = ((particle.y - t * particle.speed) % 1.0 + 1.0) % 1.0;
      final x = particle.x + 0.012 * math.sin(t * 2 * math.pi + particle.phase);
      final center = Offset(size.width * x, size.height * y);
      final radius = particle.radius;

      canvas.drawCircle(
        center,
        radius * 2.2,
        Paint()..color = color.withValues(alpha: baseAlpha * 0.35),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: baseAlpha),
      );
    }
  }

  List<_Blob> _blobSpecs() {
    final glow = accent ?? const Color(0xFFC042FF);

    if (isDarkMode) {
      return [
        const _Blob(Color(0xFF7A5CFF), 0.38, 0.62, 0.60),
        const _Blob(Color(0xFFC042FF), 0.30, 0.55, 0.45),
        const _Blob(Color(0xFFFF4FE3), 0.20, 0.48, 0.52),
        const _Blob(Color(0xFF63FF6C), 0.06, 0.34, 0.40),
        _Blob(glow, 0.16, 0.42, 0.50),
      ];
    }

    return [
      const _Blob(Color(0xFF7A5CFF), 0.16, 0.60, 0.60),
      const _Blob(Color(0xFFC042FF), 0.12, 0.55, 0.45),
      const _Blob(Color(0xFFFF4FE3), 0.10, 0.50, 0.52),
      _Blob(glow, 0.10, 0.45, 0.50),
    ];
  }

  @override
  bool shouldRepaint(_AnimatedBackgroundPainter oldDelegate) {
    return oldDelegate.reduced != reduced ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.accent != accent;
  }
}

class _Blob {
  const _Blob(this.color, this.alpha, this.radius, this.speed);

  final Color color;
  final double alpha;
  final double radius;
  final double speed;
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phase,
  });

  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;
}
