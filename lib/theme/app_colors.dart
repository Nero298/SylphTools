import 'package:flutter/material.dart';

extension ThemeExt on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get bg => Theme.of(this).scaffoldBackgroundColor;
  Color get bgSidebar => isDark ? AppColors.darkBgSidebar : AppColors.lightBgSidebar;
  Color get bgPanel => Theme.of(this).colorScheme.surface;
  Color get bgInput => isDark ? AppColors.darkBgInput : AppColors.lightBgInput;
  Color get bgMsgAi => isDark ? AppColors.darkBgMsgAi : AppColors.lightBgMsgAi;
  Color get bgHover => isDark ? AppColors.darkBgHover : AppColors.lightBgHover;
  Color get border => Theme.of(this).dividerColor;
  Color get borderFaint => isDark ? AppColors.darkBorderFaint : AppColors.lightBorderFaint;
  
  Color get text => isDark ? AppColors.darkText : AppColors.lightText;
  Color get textM => isDark ? AppColors.darkTextM : AppColors.lightTextM;
  Color get textD => isDark ? AppColors.darkTextD : AppColors.lightTextD;
}

/// SylphTools design tokens — deep blue / cyan palette.
class AppColors {
  AppColors._();

  // ── Common Colors ──────────────────────────────────────────────
  static const accent    = Color(0xFF0EA5E9); // sky blue
  static const accentDim = Color(0xFF0284C7); // deeper blue
  static const accentHi  = Color(0xFF22D3EE); // cyan highlight
  static const green  = Color(0xFF3FB950);
  static const red    = Color(0xFFF85149);
  static const orange = Color(0xFFE3B341);

  // ── Dark Theme Colors ──────────────────────────────────────────
  static const darkBg        = Color(0xFF040B14); // near-black navy
  static const darkBgSidebar = Color(0xFF040B14);
  static const darkBgPanel   = Color(0xFF0A1628); // deep navy panel
  static const darkBgInput   = Color(0xFF0F1E33);
  static const darkBgMsgAi   = Color(0xFF0A1628);
  static const darkBgHover   = Color(0xFF122542);
  static const darkBorder    = Color(0xFF1B3358);
  static const darkBorderFaint = Color(0xFF12253F);
  static const darkText      = Color(0xFFE3F2FD);
  static const darkTextM     = Color(0xFF7FA8C9);
  static const darkTextD     = Color(0xFF3E5C7A);

  // ── Light Theme Colors ─────────────────────────────────────────
  static const lightBg        = Color(0xFFFFFFFF);
  static const lightBgSidebar = Color(0xFFF0F7FC); // pale ice blue
  static const lightBgPanel   = Color(0xFFF0F7FC);
  static const lightBgInput   = Color(0xFFFFFFFF);
  static const lightBgMsgAi   = Color(0xFFEAF4FA);
  static const lightBgHover   = Color(0xFFDCEEF8);
  static const lightBorder    = Color(0xFFCDE6F4); // soft blue borders
  static const lightBorderFaint = Color(0xFFE8F4FA);
  static const lightText      = Color(0xFF082032); // deep navy text
  static const lightTextM     = Color(0xFF35617D);
  static const lightTextD     = Color(0xFF8FB4C9);

  // ── Label colours ────────────────────────────────────────────
  static const uncensored = Color(0xFFEF4444);
  static const standard   = Color(0xFF22D3EE);
  static const custom     = Color(0xFF22C55E);

  // ── Gradients ────────────────────────────────────────────────
  static const accentGradient = LinearGradient(
    colors: [accentDim, accentHi],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
