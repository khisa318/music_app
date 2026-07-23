import 'package:flutter/material.dart';
import '../../../onboarding/presentation/screens/intro_screen.dart';
import '../../../main_screen/router/display_route.dart';
import '../../../../core/services/settings_storage_service.dart';

class MusiXColors {
  static const Color primaryPurple = Color(0xFF7B2FF7);
  static const Color secondaryBlue = Color(0xFF00C6FF);
  static const Color backgroundColor = Color(0xFF000000);
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _opacityAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    _checkFirstTime();
  }

  Future<void> _checkFirstTime() async {
    final box = await SettingsStorageService.getBox();
    final bool isFirstTime = (box.get('first_time') as bool?) ?? true;

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              isFirstTime ? const IntroScreen() : const MainScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: MusiXColors.backgroundColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: _getResponsiveLogoSize(size),
                      height: _getResponsiveLogoSize(size),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: MusiXColors.primaryPurple.withValues(
                              alpha: 0.45 * _opacityAnimation.value,
                            ),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                          BoxShadow(
                            color: MusiXColors.secondaryBlue.withValues(
                              alpha: 0.35 * _opacityAnimation.value,
                            ),
                            blurRadius: 60,
                            spreadRadius: 15,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/musix_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),

                    const SizedBox(height: 28),

                    ShaderMask(
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          colors: [
                            MusiXColors.primaryPurple,
                            MusiXColors.secondaryBlue,
                          ],
                        ).createShader(bounds);
                      },
                      child: Text(
                        "MusiX",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _getResponsiveFontSize(size),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      "Feel Every Beat",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _getResponsiveLogoSize(Size size) {
    if (size.width < 600) {
      return 180;
    } else if (size.width < 1200) {
      return 240;
    }
    return 300;
  }

  double _getResponsiveFontSize(Size size) {
    if (size.width < 600) {
      return 42;
    } else if (size.width < 1200) {
      return 52;
    }
    return 62;
  }
}
