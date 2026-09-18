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

/// One app placed on one tab.
class Tile implements GridItem {
  Tile({
    required this.appId,
    this.row = GridItem.unplaced,
    this.col = GridItem.unplaced,
    this.colSpan = 1,
    this.rowSpan = 1,
  });

  /// The app this stands for: `package/activity`, or a saved shortcut's id.
  final String appId;

  @override
  String get id => appId;

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
        appId: appId,
        row: row,
        col: col,
        colSpan: colSpan,
        rowSpan: rowSpan,
      );

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'row': row,
        'col': col,
        if (colSpan != 1) 'colSpan': colSpan,
        if (rowSpan != 1) 'rowSpan': rowSpan,
      };

  static Tile? fromJson(Object? json) {
    if (json is! Map) return null;
    final appId = json['appId'];
    if (appId is! String || appId.isEmpty) return null;
    return Tile(
      appId: appId,
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
  TabPage({required this.id, required this.name, required this.tiles});

  final String id;
  String name;
  final List<Tile> tiles;

  bool get isEmpty => tiles.isEmpty;

  Tile? tileFor(String appId) {
    for (final tile in tiles) {
      if (tile.appId == appId) return tile;
    }
    return null;
  }

  bool holds(String appId) => tileFor(appId) != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
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
      tiles: [
        for (final entry in (json['tiles'] as List? ?? const []))
          if (Tile.fromJson(entry) case final tile?)
            // One placement per app per tab. Two tiles for one app on one page
            // would both launch the same thing and only one could be the one
            // you meant to move.
            if (seen.add(tile.appId)) tile,
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
    tab.tiles.add(Tile(appId: appId));
    return true;
  }

  bool remove(String tabId, String appId) {
    final tab = this[tabId];
    if (tab == null) return false;
    final before = tab.tiles.length;
    tab.tiles.removeWhere((tile) => tile.appId == appId);
    return tab.tiles.length != before;
  }

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
    if (!remove(fromTabId, appId)) return false;
    to.tiles.add(Tile(appId: appId));
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
