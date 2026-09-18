/// The palette and icon set a card can be given.
///
/// Both are closed sets on purpose. A launcher whose cards can be any colour
/// ends up looking like a spreadsheet; the rabbit-ish look comes from a small
/// number of saturated, high-contrast colours that always take black text.
///
/// Pure Dart — no Flutter — so the catalogue and the rules about it are
/// testable, and the model can store a colour as an int and an icon as a key
/// without dragging widgets into it.
library;

import 'icon_catalogue.dart';

class CardColor {
  const CardColor(this.key, this.name, this.value);

  final String key;
  final String name;

  /// Opaque ARGB.
  final int value;
}

/// Saturated flat colours that all carry black text legibly — the rabbitOS
/// stack look. Ordered so consecutive cards land on visibly different hues
/// when a deck is seeded.
///
/// All twelve remain nameable and resolvable, and the colour picker offers
/// them; only the first five are on the editor's shelf. See
/// [starterColorKeys].
const List<CardColor> cardPalette = [
  CardColor('magenta', 'Magenta', 0xFFFF2BB5),
  CardColor('cyan', 'Cyan', 0xFF3FE3F0),
  CardColor('periwinkle', 'Periwinkle', 0xFF8E8CF8),
  CardColor('green', 'Green', 0xFF2BE04B),
  CardColor('red', 'Red', 0xFFFF3123),
  CardColor('orange', 'Orange', 0xFFFF9A0E),
  CardColor('blue', 'Blue', 0xFF37A8FF),
  CardColor('violet', 'Violet', 0xFFC57DFF),
  CardColor('lime', 'Lime', 0xFFC8F02B),
  CardColor('coral', 'Coral', 0xFFFF6B5A),
  CardColor('mint', 'Mint', 0xFF4FE8B0),
  CardColor('butter', 'Butter', 0xFFFFD93D),
];

/// The five icons the starter deck arrives with.
///
/// This is the whole shelf in the card editor. Everything else is a tap away
/// behind the picker, and whatever gets picked is remembered — so the grid
/// grows into what this phone actually uses instead of guessing up front.
const List<String> starterIconKeys = [
  'star',
  'music_note',
  'chat_bubble',
  'sports_esports',
  'build',
];

/// The wider set the icon picker opens on, before anything is typed. A middle
/// step between the five and searching all 2,200.
const List<String> commonIconKeys = [
  ...starterIconKeys,
  'grid_view',
  'favorite',
  'photo_camera',
  'image',
  'movie',
  'call',
  'mail',
  'public',
  'menu_book',
  'map',
  'schedule',
  'alarm',
  'shopping_bag',
  'account_balance_wallet',
  'work',
  'school',
  'fitness_center',
  'restaurant',
  'directions_car',
  'flight',
  'settings',
  'code',
  'terminal',
  'cloud',
  'lock',
  'sticky_note_2',
  'checklist',
  'bolt',
  'lightbulb',
  'palette',
  'folder',
];

const String fallbackIconKey = 'folder';

/// The five colours the starter deck arrives with — the editor's shelf, in the
/// same way [starterIconKeys] is.
List<String> get starterColorKeys =>
    [for (final entry in cardPalette.take(5)) entry.key];

/// Keys written by the first builds, which used names of their own invention
/// rather than Material's. Kept so a card saved then keeps its icon.
const Map<String, String> legacyIconKeys = {
  'apps': 'grid_view',
  'camera': 'photo_camera',
  'music': 'music_note',
  'photo': 'image',
  'chat': 'chat_bubble',
  'globe': 'public',
  'game': 'sports_esports',
  'book': 'menu_book',
  'clock': 'schedule',
  'heart': 'favorite',
  'cog': 'settings',
  'wallet': 'account_balance_wallet',
  'note': 'sticky_note_2',
  'tools': 'build',
};

/// A colour key is either a palette name or a `#rrggbb` literal from the custom
/// picker. Keeping both in one string means storage, and everything that passes
/// a colour around, stays unchanged.
bool isCustomColorKey(String key) => customColorValue(key) != null;

/// The ARGB value a `#rrggbb` (or `#aarrggbb`) key names, or null if [key] is
/// not one.
int? customColorValue(String key) {
  if (!key.startsWith('#')) return null;
  final digits = key.substring(1);
  if (digits.length != 6 && digits.length != 8) return null;
  final parsed = int.tryParse(digits, radix: 16);
  if (parsed == null) return null;
  return digits.length == 6 ? 0xFF000000 | parsed : parsed;
}

String customColorKey(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The colour for [key], falling back to the first palette entry rather than
/// throwing: a stored deck from an older palette must still open.
CardColor colorForKey(String key) {
  final custom = customColorValue(key);
  if (custom != null) return CardColor(key, 'Custom', custom);
  for (final color in cardPalette) {
    if (color.key == key) return color;
  }
  return cardPalette.first;
}

bool isKnownColorKey(String key) =>
    isCustomColorKey(key) || cardPalette.any((color) => color.key == key);

/// Normalises an icon key: translates a legacy name, accepts anything in the
/// catalogue, and falls back for anything else — so a deck written by a future
/// version with icons this build does not have still renders something.
String normaliseIconKey(String? key) {
  if (key == null) return fallbackIconKey;
  final translated = legacyIconKeys[key] ?? key;
  return materialIcons.containsKey(translated) ? translated : fallbackIconKey;
}

/// Icons whose name contains [query], for the picker's search.
List<String> searchIcons(String query) {
  final needle = query.trim().toLowerCase().replaceAll(' ', '_');
  if (needle.isEmpty) return commonIconKeys;
  return [
    for (final key in materialIcons.keys)
      if (key.contains(needle)) key,
  ];
}

/// The colour a card gets when it is created and nobody has picked one, walking
/// the palette so a fresh deck is not eight magenta cards.
CardColor paletteAt(int index) =>
    cardPalette[index.abs() % cardPalette.length];
