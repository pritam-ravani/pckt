import 'package:flutter/material.dart';

/// Brand + semantic colors. Category colors are tuned to stay distinct
/// from each other on both the dark and light surfaces.
abstract final class Palette {
  // Brand
  static const mint = Color(0xFF3DDC97);
  static const violet = Color(0xFF8B7CF6);
  static const coral = Color(0xFFFF6B6B);
  static const amber = Color(0xFFFFB547);

  // Dark surfaces
  static const ink = Color(0xFF0B0C10);
  static const inkRaised = Color(0xFF14161C);
  static const inkHigh = Color(0xFF1C1F27);
  static const inkLine = Color(0xFF262A33);

  // Light surfaces
  static const paper = Color(0xFFF6F6F2);
  static const paperRaised = Color(0xFFFFFFFF);
  static const paperHigh = Color(0xFFEDEDE7);
  static const paperLine = Color(0xFFE2E2DA);

  static const income = mint;
  static const expense = coral;

  /// Validated categorical set (dataviz validator: lightness band, chroma,
  /// CVD + normal-vision separation, 3:1 contrast — passes on both surfaces).
  /// Order is fixed; colors follow the category, never its rank.
  static const categories = <Color>[
    Color(0xFF3B82F6), // blue
    Color(0xFFE0662C), // orange
    Color(0xFF14A37F), // teal
    Color(0xFFBD8400), // amber
    Color(0xFFD9559B), // pink
    Color(0xFF5E9E1A), // green
    Color(0xFF8577EE), // violet
    Color(0xFF1AA0C4), // cyan
  ];

  /// Catch-all buckets ("Other", transfers, people) — deliberately not a hue.
  static const neutral = Color(0xFF8A90A0);

  /// Gradient used on the hero card.
  static const heroGradient = [Color(0xFF6D5DF6), Color(0xFF3B2FB8), Color(0xFF1E1A5E)];
}
