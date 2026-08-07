import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design System Theme for Portal Messenger
/// Enforces Liquid Glass aesthetics, HSL color tokens, and iOS Telegram visual standards.
class PortalTheme {
  // --- Dark Canvas Color Palette (Telegram iOS Dark Slate Graphite) ---
  static const Color bgCanvas = Color(0xFF141416);
  static const Color bgSurface = Color(0xFF1E1E22);
  static const Color bgElevated = Color(0xFF26262B);
  static const Color bgCard = Color(0xFF1C1C20);
  static const Color bgInput = Color(0xFF222227);

  // Accents (Telegram iOS Vibrant Blue)
  static const Color primary = Color(0xFF3390EC);
  static const Color primaryElectric = Color(0xFF3390EC);
  static const Color cyanAccent = Color(0xFF2AABEE);
  static const Color emeraldAccent = Color(0xFF1FDB92);
  static const Color roseAccent = Color(0xFFF74375);

  // Glassmorphism borders & fills
  static const Color glassBorder = Color(0x1AFFFFFF);
  static const Color glassBorderActive = Color(0x33FFFFFF);
  static const Color glassFill = Color(0x1A26262B);
  static const Color glassFillElevated = Color(0x3326262B);

  // Message Bubble Colors
  static const Color messageBubbleSent = Color(0xFF2AABEE);
  static const Color messageBubbleReceived = Color(0xFF212126);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textMuted = Color(0xFF636366);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryElectric, cyanAccent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static TextStyle displayHeader({double fontSize = 28, Color color = textPrimary}) {
    return GoogleFonts.outfit(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: -0.5,
      height: 1.2,
    );
  }

  static TextStyle titleHeader({double fontSize = 18, Color color = textPrimary}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: -0.3,
    );
  }

  static TextStyle bodyText({double fontSize = 15, Color color = textPrimary, FontWeight weight = FontWeight.w400}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
      height: 1.4,
    );
  }

  static TextStyle subText({double fontSize = 13, Color color = textSecondary}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      color: color,
    );
  }

  static TextStyle badgeText({Color color = textPrimary}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: 0.6,
    );
  }

  static BoxDecoration glassBox({
    double borderRadius = 20,
    Color fillColor = glassFill,
    Color borderColor = glassBorder,
    double borderWidth = 1.0,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      color: fillColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: shadows ??
          [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
    );
  }

  static Widget liquidGlassWidget({
    required Widget child,
    double borderRadius = 20,
    double blurSigma = 10,
    Color fillColor = glassFill,
    Color borderColor = glassBorder,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: glassBox(
              borderRadius: borderRadius,
              fillColor: fillColor,
              borderColor: borderColor,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgCanvas,
      primaryColor: primaryElectric,
      colorScheme: const ColorScheme.dark(
        primary: primaryElectric,
        secondary: cyanAccent,
        surface: bgSurface,
        error: roseAccent,
      ),
    );
  }
}
