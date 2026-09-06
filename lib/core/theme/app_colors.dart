import 'package:flutter/material.dart';

/// Semantic Design System Colors for Document Scanner following Material 3 guidelines.
abstract final class AppColors {
  // Primary Brand & Scanner Laser Accent
  static const Color primary = Color(0xFF006494);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFCBE6FF);
  static const Color onPrimaryContainer = Color(0xFF001E30);

  // Scanner Laser & Edge Detection Highlighter
  static const Color scannerLaser = Color(0xFF00C853);
  static const Color scannerLaserGlow = Color(0x6600E676);
  static const Color cropHandle = Color(0xFF00E676);
  static const Color cropHandleInactive = Color(0x80FFFFFF);
  static const Color cropOverlayScrim = Color(0x99000000);

  // Secondary
  static const Color secondary = Color(0xFF50606E);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFD3E5F5);
  static const Color onSecondaryContainer = Color(0xFF0C1D29);

  // Tertiary
  static const Color tertiary = Color(0xFF65587B);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFECDCFF);
  static const Color onTertiaryContainer = Color(0xFF211634);

  // Neutral & Surfaces (Light)
  static const Color lightBackground = Color(0xFFF8F9FD);
  static const Color lightSurface = Color(0xFFF8F9FD);
  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFF2F4F8);
  static const Color lightSurfaceContainer = Color(0xFFECEEF2);
  static const Color lightSurfaceContainerHigh = Color(0xFFE6E8EC);
  static const Color lightSurfaceContainerHighest = Color(0xFFE0E2E7);
  static const Color lightOnSurface = Color(0xFF191C1E);
  static const Color lightOnSurfaceVariant = Color(0xFF41474D);
  static const Color lightOutline = Color(0xFF72787E);
  static const Color lightOutlineVariant = Color(0xFFC1C7CE);

  // Neutral & Surfaces (Dark)
  static const Color darkBackground = Color(0xFF101417);
  static const Color darkSurface = Color(0xFF101417);
  static const Color darkSurfaceContainerLowest = Color(0xFF0B0E11);
  static const Color darkSurfaceContainerLow = Color(0xFF191C1F);
  static const Color darkSurfaceContainer = Color(0xFF1D2024);
  static const Color darkSurfaceContainerHigh = Color(0xFF272B2E);
  static const Color darkSurfaceContainerHighest = Color(0xFF323639);
  static const Color darkOnSurface = Color(0xFFE0E3E7);
  static const Color darkOnSurfaceVariant = Color(0xFFC1C7CE);
  static const Color darkOutline = Color(0xFF8B9198);
  static const Color darkOutlineVariant = Color(0xFF41474D);

  // Camera Overlay Glassmorphism
  static const Color cameraOverlayDark = Color(0xCC101417);
  static const Color cameraControlGlass = Color(0x33FFFFFF);
  static const Color cameraShutterRing = Color(0xFFFFFFFF);
}
