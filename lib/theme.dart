/// The look: pale paper, ink text, one accent per tab.
///
/// Light rather than dark because the grid is mostly app icons, and app icons
/// are designed to sit on a light launcher far more often than a dark one — a
/// dark ground makes every rounded-square icon look like it is floating on its
/// own little card.
library;

import 'package:flutter/material.dart';

import 'card_style.dart';

class Paper {
  static const ground = Color(0xFFF4F1EA);
  static const surface = Color(0xFFFFFFFF);
  static const edge = Color(0xFFE2DCCF);
  static const ink = Color(0xFF221F1A);
  static const dim = Color(0xFF7C756A);

  /// The cell outline shown while arranging. Only ever visible then: a grid
  /// drawn all the time is a spreadsheet.
  static const gap = Color(0x14221F1A);
}

class Metrics {
  /// Four across, matching picopages. Locked, because a tile's stored column
  /// only means anything against a fixed count — change it and every saved
  /// layout shifts.
  static const columns = 4;

  static const gutter = 10.0;
  static const tileRadius = 18.0;
  static const tabBarHeight = 46.0;
}

Color colorOf(String key) => Color(colorForKey(key).value);

/// What to draw on top of [background].
///
/// The threshold is the WCAG contrast crossover: black reads on a background
/// above about 0.179 relative luminance, white below it.
Color onPaperFor(Color background) =>
    background.computeLuminance() > 0.179 ? Paper.ink : Paper.surface;

Color onPaperForKey(String key) => onPaperFor(colorOf(key));

TextStyle text({
  required double size,
  int weight = 400,
  Color color = Paper.ink,
  double? letterSpacing,
  double? height,
}) =>
    TextStyle(
      fontFamily: 'Lexend',
      fontSize: size,
      color: color,
      fontWeight: FontWeight.values.firstWhere(
        (candidate) => candidate.value == weight,
        orElse: () => FontWeight.normal,
      ),
      fontVariations: [FontVariation('wght', weight.toDouble())],
      letterSpacing: letterSpacing,
      height: height,
    );

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Paper.ground,
      colorScheme: const ColorScheme.light(
        surface: Paper.ground,
        primary: Color(0xFFCB5B2E),
        onPrimary: Colors.white,
      ),
      fontFamily: 'Lexend',
    );
