import 'package:flutter/material.dart';

/// AppColors defines the complete premium dark theme color system
/// and visual gradients used throughout the CIRO Fire Crisis Response application.
class AppColors {
  // Dark Backgrounds
  static const Color background = Color(0xFF0C0E14);
  static const Color surface = Color(0xFF151821);
  static const Color surfaceElevated = Color(0xFF1E2230);
  
  // Brand & Accent Colors
  static const Color primary = Color(0xFFFF5232);      // Vivid Neon Orange/Red for Fire Alert
  static const Color secondary = Color(0xFFFF8A00);    // Bright Amber/Yellow
  static const Color tertiary = Color(0xFF8A2BE2);     // Deep Purple for Orchestrator Logic
  
  // Status Colors
  static const Color success = Color(0xFF00E676);      // Neon Green
  static const Color warning = Color(0xFFFFC400);      // Warning Yellow
  static const Color error = Color(0xFFD50000);        // Crimson Red
  static const Color info = Color(0xFF29B6F6);         // Cool Blue
  
  // Text Colors
  static const Color textPrimary = Color(0xFFF5F6F9);
  static const Color textSecondary = Color(0xFF9FA5C0);
  static const Color textMuted = Color(0xFF626880);

  // Agent Specific Chip Colors (rule-08)
  static const Color agentFusion = Color(0xFF00E5FF);      // Cyan
  static const Color agentClassifier = Color(0xFFFF3D00);  // Vivid Red-Orange
  static const Color agentAllocator = Color(0xFFFFEB3B);   // Yellow
  static const Color agentSimulator = Color(0xFFE040FB);   // Neon Magenta
  static const Color agentRecovery = Color(0xFF69F0AE);    // Light Green

  // Sleek Premium Gradients (rule-06)
  static const LinearGradient appBarGradient = LinearGradient(
    colors: [
      Color(0xFF1E102F), // Dark purple hue
      Color(0xFF0C0E14), // Seamless fade to background
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient fireAlertGradient = LinearGradient(
    colors: [
      Color(0xFFFF3D00), // Crimson/Red
      Color(0xFFFF9100), // Warm Orange
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [
      Color(0xFF1E2230),
      Color(0xFF151821),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient purpleAccentGradient = LinearGradient(
    colors: [
      Color(0xFF8E2DE2),
      Color(0xFF4A00E0),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient cyberGradient = LinearGradient(
    colors: [
      Color(0xFF00F2FE),
      Color(0xFF4FACFE),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
