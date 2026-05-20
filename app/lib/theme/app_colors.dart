import 'package:flutter/material.dart';

/// AppColors defines the complete premium clean theme color system
/// and visual gradients used throughout the CIRO Fire Crisis Response application.
class AppColors {
  // Clean Light Backgrounds (Steve Jobs + Elon Musk aesthetic)
  static const Color background = Color(0xFFF5F5F5); // User requested #F5F5F5
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFAFAFA);

  // Brand & Accent Colors
  static const Color primary = Color(
    0xFFD32F2F,
  ); // User requested #D32F2F (red for crisis)
  static const Color secondary = Color(0xFFFF8A00); // Bright Amber/Yellow
  static const Color tertiary = Color(
    0xFF1976D2,
  ); // Deep Blue for Orchestrator Logic

  // Status Colors
  static const Color success = Color(0xFF4CAF50); // Green
  static const Color warning = Color(0xFFFFC107); // Warning Yellow
  static const Color error = Color(0xFFD32F2F); // Crimson Red
  static const Color info = Color(0xFF2196F3); // Cool Blue

  // Text Colors (Dark text for light theme)
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF5A5A5A);
  static const Color textMuted = Color(0xFF9E9E9E);

  // Agent Specific Chip Colors (rule-08)
  static const Color agentFusion = Color(0xFF00BCD4); // Cyan
  static const Color agentClassifier = Color(0xFFD32F2F); // Vivid Red
  static const Color agentAllocator = Color(0xFFFFC107); // Yellow
  static const Color agentSimulator = Color(0xFF9C27B0); // Purple
  static const Color agentRecovery = Color(0xFF4CAF50); // Green

  // Sleek Premium Gradients (rule-06)
  static const LinearGradient appBarGradient = LinearGradient(
    colors: [
      Color(0xFFD32F2F), // Primary Red
      Color(0xFFB71C1C), // Darker Red
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient fireAlertGradient = LinearGradient(
    colors: [
      Color(0xFFD32F2F), // Crimson/Red
      Color(0xFFFF8A00), // Warm Orange
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF9F9F9)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient purpleAccentGradient = LinearGradient(
    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyberGradient = LinearGradient(
    colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color? get textMain => null;

  static Color? get accent => null;
}
