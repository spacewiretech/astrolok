import 'package:flutter/material.dart';

/// The app palette.
///
/// PLACEHOLDER VALUES. Every screen references these names rather than raw hex, so replacing
/// them with the real ones read off the Figma exports is an edit to this file alone. The
/// current set is a night-sky scheme chosen only so the unskinned screens are legible.
abstract final class AppColors {
  /// Primary action colour — buttons, focused fields, selected states.
  static const brand = Color(0xFF6C3CE9);

  /// Deep background behind the hero artwork.
  static const night = Color(0xFF120B2E);

  /// Accent for prices, ratings and highlights.
  static const gold = Color(0xFFF5B740);

  static const heading = Color(0xFF16103A);
  static const body = Color(0xFF453F63);
  static const muted = Color(0xFF8B85A6);

  static const surface = Color(0xFFFFFFFF);
  static const scaffold = Color(0xFFFBF9FF);

  /// Card and sheet fills.
  static const cardSoft = Color(0xFFF4F1FE);
  static const divider = Color(0xFFE8E3F5);

  /// Resting outline on inputs and OTP boxes; [brand] replaces it on focus.
  static const border = Color(0xFFD6D0E4);

  static const success = Color(0xFF12B76A);
  static const danger = Color(0xFFE5342B);
  static const warning = Color(0xFFF5B740);

  /// Behind modal bottom sheets.
  static const scrim = Color(0x66120B2E);

  /// Lifts sheets and cards off the background.
  static const floatingShadow = BoxShadow(
    color: Color(0x14120B2E),
    blurRadius: 24,
    offset: Offset(0, 8),
  );
}
