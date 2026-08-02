import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../routes/app_routes.dart';
import 'app_webview_screen.dart';

class ToolsHubScreen extends StatelessWidget {
  final bool embedded;
  const ToolsHubScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final body = _ToolsHubBody(showBackButton: !embedded);
    if (embedded) return body;
    return Scaffold(backgroundColor: context.bg, body: body);
  }
}

class _ToolsHubBody extends StatelessWidget {
  final bool showBackButton;
  const _ToolsHubBody({required this.showBackButton});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              if (showBackButton)
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: context.text),
                  onPressed: () => Get.back(),
                )
              else
                const SizedBox(width: 16),
              Text(
                'Tools',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.text,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              _ToolCard(
                icon: Icons.code_rounded,
                iconColor: AppColors.accentHi,
                title: 'Lua Tools',
                subtitle:
                    'Obfuscate, deobfuscate, detect & beautify Luau scripts — via LeakD',
                onTap: () => Get.toNamed(AppRoutes.luaTools),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.terminal_rounded,
                iconColor: AppColors.green,
                title: 'Script Runner',
                subtitle:
                    'Run Luau code on-device, with a live GUI preview for scripts that build UI',
                onTap: () => Get.toNamed(AppRoutes.scriptRunner),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.fact_check_rounded,
                iconColor: AppColors.orange,
                title: 'UNC Checker',
                subtitle:
                    'Check UNC-style function availability in this sandbox — on-device',
                onTap: () => Get.toNamed(AppRoutes.uncChecker),
              ),
              const SizedBox(height: 10),
              _ToolCard(
                icon: Icons.image_outlined,
                iconColor: AppColors.custom,
                title: 'Generate Image',
                subtitle: 'AI text-to-image via Perchance — opens in-app',
                onTap: () => Get.to(
                  () => const AppWebViewScreen(
                    url: 'https://perchance.org/ai-text-to-image-generator',
                    title: 'Generate Image',
                    injectedCss: _perchanceThemeCss,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Light CSS nudge to pull Perchance's default light theme closer to
/// SylphTools' dark navy/cyan palette. Best-effort — if Perchance changes
/// its markup this simply stops matching and the page renders unstyled,
/// which is harmless.
const _perchanceThemeCss = '''
  body { background-color: #040B14 !important; }
  input, textarea, select {
    background-color: #0F1E33 !important;
    color: #E3F2FD !important;
    border-color: #1B3358 !important;
  }
''';

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool comingSoon;

  const _ToolCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.bgHover,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: comingSoon ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: context.text,
                          ),
                        ),
                        if (comingSoon) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.orange.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'SOON',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.orange,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: context.textM,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (!comingSoon)
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.textD,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
