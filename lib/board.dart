/// Tabs, and what is on each of them.
///
/// A tab is a page of the grid and nothing more. That is deliberately less than
/// a folder: you can see every tab's name at once without opening anything, so
/// deciding where an app lives costs a glance rather than a search.
///
/// The same app may sit on several tabs. It is one app either way — a tile is a
/// placement, not a copy — so "on the home tab and the work tab" is a sentence
/// about where you look for it rather than about how many of it there are.
///
/// Pure Dart, so the rules — a tab cannot be empty of identity, the last tab
/// cannot be removed, a tile cannot be on the same tab twice — are testable
/// without a screen.
library;

import 'grid.dart';

/// What a tile stands for.
enum TileKind {
  /// An app or a pinned shortcut, launched when tapped.
  app,

  /// A picture, which does nothing when tapped.
  ///
  /// Its own kind rather than an app with a picture for an icon, because the
  /// two differ in every way that matters once placed: an image tile has no
  /// label, no launch, nothing to uninstall, and survives the app list changing
  /// under it.
  image,
}

/// One thing placed on one tab: an app, or a picture.
class Tile implements GridItem {
  Tile({
    required this.id,
    this.kind = TileKind.app,
    this.mediaId,
    this.iconMediaId,
    this.row = GridItem.unplaced,
    this.col = GridItem.unplaced,
    this.colSpan = 1,
    this.rowSpan = 1,
  });

  /// An app tile. Its id is the app's, so one app is one tile per tab.
  Tile.app(
    String appId, {
    this.iconMediaId,
    this.row = GridItem.unplaced,
    this.col = GridItem.unplaced,
    this.colSpan = 1,
    this.rowSpan = 1,
  })  : id = appId,
        kind = TileKind.app,
        mediaId = null;

  /// A picture tile. Its id is its own, so the same picture can be placed twice.
  Tile.image(
    String this.mediaId, {
    String? id,
    this.row = GridItem.unplaced,
    this.col = GridItem.unplaced,
    this.colSpan = 1,
    this.rowSpan = 1,
  })  : id = id ?? 'img-${DateTime.now().microsecondsSinceEpoch}',
        kind = TileKind.image,
        iconMediaId = null;

  /// What this tile is on the grid. For an app tile that is the app's id, which
  /// is what keeps one app to one tile per tab; for a picture it is its own.
  @override
  final String id;

  final TileKind kind;

  bool get isImage => kind == TileKind.image;

  /// The app this stands for, or null on a picture tile.
  ///
  /// A getter rather than a field: an app tile's id *is* its app id, and storing
  /// both invites them to disagree.
  String? get appId => kind == TileKind.app ? id : null;

  /// The picture shown, for an image tile.
  final String? mediaId;

  /// A picture to draw instead of the app's own icon, for an app tile.
  ///
  /// Separate from [mediaId] so a tile cannot be half one kind and half the
  /// other: an image tile is a picture, an app tile may wear one.
  final String? iconMediaId;

  /// Every picture this tile needs kept, for reaping the ones nothing uses.
  Iterable<String> get mediaIds => [?mediaId, ?iconMediaId];

  @override
  int row;
  @override
  int col;
  @override
  int colSpan;
  @override
  int rowSpan;

  @override
  bool get placed => row >= 0 && col >= 0;

  Tile copy() => Tile(
        id: id,
        kind: kind,
        mediaId: mediaId,
        iconMediaId: iconMediaId,
        row: row,
        col: col,
        colSpan: colSpan,
        rowSpan: rowSpan,
      );

  Tile withIcon(String? iconMediaId) => Tile(
        id: id,
        kind: kind,
        mediaId: mediaId,
        iconMediaId: iconMediaId,
        row: row,
        col: col,
        colSpan: colSpan,
        rowSpan: rowSpan,
      );

  Map<String, dynamic> toJson() => {
        // Still written as appId, and still read as one below. A board saved
        // before pictures existed holds nothing else, and renaming the key would
        // have emptied every tab on the first launch after the update.
        'appId': id,
        'row': row,
        'col': col,
        if (colSpan != 1) 'colSpan': colSpan,
        if (rowSpan != 1) 'rowSpan': rowSpan,
        if (kind == TileKind.image) 'kind': 'image',
        if (mediaId != null) 'mediaId': mediaId,
        if (iconMediaId != null) 'iconMediaId': iconMediaId,
      };

  static Tile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['appId'];
    if (id is! String || id.isEmpty) return null;
    final mediaId = json['mediaId'] as String?;
    // An image tile with no picture is not a tile: it would draw as a blank
    // square with nothing to tap, so it is dropped rather than shown.
    final isImage = json['kind'] == 'image';
    if (isImage && (mediaId == null || mediaId.isEmpty)) return null;
    return Tile(
      id: id,
      kind: isImage ? TileKind.image : TileKind.app,
      mediaId: mediaId,
      iconMediaId: json['iconMediaId'] as String?,
      row: (json['row'] as num?)?.toInt() ?? GridItem.unplaced,
      col: (json['col'] as num?)?.toInt() ?? GridItem.unplaced,
      // Clamped on the way in: a span of zero would be a tile with no cells,
      // which lays out as nothing and cannot be pressed to fix.
      colSpan: ((json['colSpan'] as num?)?.toInt() ?? 1).clamp(1, 8),
      rowSpan: ((json['rowSpan'] as num?)?.toInt() ?? 1).clamp(1, 8),
    );
  }
}

class TabPage {
  TabPage({
    required this.id,
    required this.name,
    required this.tiles,
    this.backgroundMediaId,
  });

  final String id;
  String name;
  final List<Tile> tiles;

  /// A picture drawn behind this tab's grid, or null for the plain ground.
  ///
  /// Per tab rather than one for the launcher: a tab is a page, and pages are
  /// what a background belongs to. Setting the same one on every tab gives the
  /// single-background behaviour back, where one global picture could not be
  /// talked out of being global.
  String? backgroundMediaId;

  bool get isEmpty => tiles.isEmpty;

  Tile? operator [](String id) {
    for (final tile in tiles) {
      if (tile.id == id) return tile;
    }
    return null;
  }

  /// The tile for [appId], if this tab holds that app.
  ///
  /// Only ever finds app tiles: a picture's id is its own, and no app id looks
  /// like one.
  Tile? tileFor(String appId) {
    for (final tile in tiles) {
      if (tile.appId == appId) return tile;
    }
    return null;
  }

  bool holds(String appId) => tileFor(appId) != null;

  /// Every picture this tab needs kept.
  Iterable<String> get mediaIds => [
        for (final tile in tiles) ...tile.mediaIds,
        ?backgroundMediaId,
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (backgroundMediaId != null) 'background': backgroundMediaId,
        'tiles': [for (final tile in tiles) tile.toJson()],
      };

  static TabPage? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final seen = <String>{};
    return TabPage(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : id,
      backgroundMediaId: json['background'] as String?,
      tiles: [
        for (final entry in (json['tiles'] as List? ?? const []))
          if (Tile.fromJson(entry) case final tile?)
            // One placement per id per tab. Two tiles for one app on one page
            // would both launch the same thing and only one could be the one
            // you meant to move. Pictures get their own ids, so placing the same
            // picture twice is two tiles and stays allowed.
            if (seen.add(tile.id)) tile,
      ],
    );
  }
}

class Board {
  Board({required this.tabs});

  final List<TabPage> tabs;

  static const maxTabs = 8;

  TabPage? operator [](String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  int indexOf(String id) => tabs.indexWhere((tab) => tab.id == id);

  /// Which tabs hold [appId], for saying where else an app already is.
  List<TabPage> tabsWith(String appId) =>
      [for (final tab in tabs) if (tab.holds(appId)) tab];

  /// Puts [appId] on [tabId], unplaced, unless it is already there.
  ///
  /// Unplaced rather than at a chosen cell: where it goes is the grid's
  /// decision, made in one place by first fit, so adding one app and adding
  /// forty behave the same way.
  bool add(String tabId, String appId) {
    final tab = this[tabId];
    if (tab == null || tab.holds(appId)) return false;
    tab.tiles.add(Tile.app(appId));
    return true;
  }

  /// Puts a picture on [tabId] as a tile of its own.
  ///
  /// Hands back the tile, because a picture has no id the caller already knows -
  /// unlike an app, where the id was the thing being added.
  Tile? addImage(String tabId, String mediaId) {
    final tab = this[tabId];
    if (tab == null || mediaId.isEmpty) return null;
    final tile = Tile.image(mediaId);
    tab.tiles.add(tile);
    return tile;
  }

  /// Takes the tile with [id] off [tabId] - an app id, or a picture tile's id.
  bool remove(String tabId, String id) {
    final tab = this[tabId];
    if (tab == null) return false;
    final before = tab.tiles.length;
    tab.tiles.removeWhere((tile) => tile.id == id);
    return tab.tiles.length != before;
  }

  /// Replaces the tile with [id] on [tabId], keeping its place on the grid.
  bool replace(String tabId, String id, Tile Function(Tile) change) {
    final tab = this[tabId];
    if (tab == null) return false;
    final index = tab.tiles.indexWhere((tile) => tile.id == id);
    if (index < 0) return false;
    tab.tiles[index] = change(tab.tiles[index]);
    return true;
  }

  /// Every picture any tab still needs, for reaping the rest.
  Set<String> get mediaIds => {for (final tab in tabs) ...tab.mediaIds};

  /// Takes an app off every tab — for when it is uninstalled.
  int removeEverywhere(String appId) {
    var gone = 0;
    for (final tab in tabs) {
      if (remove(tab.id, appId)) gone++;
    }
    return gone;
  }

  TabPage? addTab(String name) {
    if (tabs.length >= maxTabs) return null;
    final clean = name.trim();
    if (clean.isEmpty) return null;
    final tab = TabPage(id: 'tab-${DateTime.now().microsecondsSinceEpoch}',
        name: clean, tiles: []);
    tabs.add(tab);
    return tab;
  }

  /// Removes a tab and everything placed on it.
  ///
  /// Never the last one: a launcher with no tabs has nowhere to show anything
  /// and no control to make a tab with.
  bool removeTab(String id) {
    if (tabs.length <= 1) return false;
    final index = indexOf(id);
    if (index < 0) return false;
    tabs.removeAt(index);
    return true;
  }

  bool renameTab(String id, String name) {
    final clean = name.trim();
    final tab = this[id];
    if (tab == null || clean.isEmpty) return false;
    tab.name = clean;
    return true;
  }

  /// Moves a tab along the bar.
  bool reorderTab(String id, int to) {
    final from = indexOf(id);
    if (from < 0) return false;
    final target = to.clamp(0, tabs.length - 1);
    if (target == from) return false;
    tabs.insert(target, tabs.removeAt(from));
    return true;
  }

  /// Moves an app from one tab to another, keeping nothing about its old spot.
  ///
  /// Arriving unplaced is the point: a cell that was free on one page is
  /// usually taken on another, and a tile that kept its coordinates would land
  /// on top of something.
  bool moveApp(String fromTabId, String toTabId, String appId) {
    if (fromTabId == toTabId) return false;
    final to = this[toTabId];
    if (to == null || to.holds(appId)) return false;
    final from = this[fromTabId]?.tileFor(appId);
    if (!remove(fromTabId, appId)) return false;
    // The custom icon travels with the app: it is a choice about the app, not
    // about where on the grid it happened to be sitting.
    to.tiles.add(Tile.app(appId, iconMediaId: from?.iconMediaId));
    return true;
  }

  List<Map<String, dynamic>> toJson() =>
      [for (final tab in tabs) tab.toJson()];

  static Board fromJson(Object? json) {
    if (json is! List) return seed();
    final tabs = <TabPage>[];
    final seen = <String>{};
    for (final entry in json) {
      final tab = TabPage.fromJson(entry);
      if (tab != null && seen.add(tab.id)) tabs.add(tab);
    }
    // A board with no tabs cannot be navigated or repaired from inside the
    // launcher, so an unreadable one becomes a fresh one rather than nothing.
    return tabs.isEmpty ? seed() : Board(tabs: tabs);
  }

  static Board seed() => Board(
        tabs: [
          TabPage(id: 'tab-home', name: 'Home', tiles: []),
          TabPage(id: 'tab-all', name: 'All', tiles: []),
        ],
      );
}
