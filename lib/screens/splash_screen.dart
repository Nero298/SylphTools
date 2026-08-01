import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../services/llm_service.dart';
import '../services/model_manager.dart';
import '../services/chat_storage_service.dart';
import '../services/local_api_server_service.dart';
import '../services/wakelock_service.dart';
import '../services/log_service.dart';
import '../services/background_optimizer_service.dart';
import '../routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final startedAt = DateTime.now();
    // Keep the splash on screen at least this long so it doesn't flash by —
    // real init is usually fast on modern phones, so we pad it out.
    const minVisibleDuration = Duration(milliseconds: 2200);

    try {
      final log = Get.find<LogService>()..init();

      setState(() => _status = 'Setting up storage...');
      log.info('Initializing storage...', source: 'Splash');
      await Get.find<ChatStorageService>().init();

      setState(() => _status = 'Loading model catalog...');
      log.info('Loading model catalog...', source: 'Splash');
      await Get.find<ModelManager>().init();

      setState(() => _status = 'Preparing AI engine...');
      log.info('Preparing AI engine...', source: 'Splash');
      await Get.find<LlmService>().init();

      setState(() => _status = 'Preparing local API...');
      log.info('Preparing local API...', source: 'Splash');
      await Get.find<LocalApiServerService>().init();

      setState(() => _status = 'Setting up background services...');
      log.info('Setting up background services...', source: 'Splash');
      await Get.find<WakelockService>().init();

      setState(() => _status = 'Ready!');
      log.info('All services initialized successfully', source: 'Splash');

      // Pad remaining time so the splash is visible for a comfortable moment.
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = minVisibleDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }

      if (mounted) {
        await BackgroundOptimizerService.checkAndPrompt(context);
      }

      Get.offAllNamed(AppRoutes.home);
    } catch (e) {
      setState(() => _status = 'Error: $e');
      try {
        Get.find<LogService>().error('Init failed: $e', source: 'Splash');
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Soft radial glow centered behind the hero art
          Container(
            width: 460,
            height: 460,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0x400EA5E9),
                  Color(0x1022D3EE),
                  Color(0x000EA5E9),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ).animate().fadeIn(duration: 1000.ms),

          // Faint concentric ring accents for depth (flat, not blurred)
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.accentHi.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
          ).animate().fadeIn(delay: 200.ms, duration: 800.ms),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Hero character art — contained (not cropped) so the full
              // portrait including the hat/top of the head is always visible.
              Container(
                width: 168,
                height: 168,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.accentGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.4),
                      blurRadius: 28,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.darkBg,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/splash_hero.png',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.35),
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 550.ms).scale(
                    begin: const Offset(0.8, 0.8),
                    curve: Curves.easeOutBack,
                    duration: 550.ms,
                  ),

              const SizedBox(height: 26),

              Text(
                'SylphTools',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkText,
                  letterSpacing: -0.9,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(
                    begin: 0.15,
                    end: 0,
                    delay: 200.ms,
                    duration: 500.ms,
                    curve: Curves.easeOut,
                  ),

              const SizedBox(height: 7),

              Text(
                'Uncensored AI, fully on-device 🔓',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.darkTextM,
                  fontWeight: FontWeight.w500,
                ),
              ).animate().fadeIn(delay: 350.ms, duration: 500.ms),

              const SizedBox(height: 52),

              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: const AlwaysStoppedAnimation(AppColors.accentHi),
                  backgroundColor: AppColors.darkBorder,
                ),
              ).animate().fadeIn(delay: 500.ms),

              const SizedBox(height: 14),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _status,
                  key: ValueKey(_status),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.darkTextD,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),
            ],
          ),
        ],
      ),
    );
  }
}
