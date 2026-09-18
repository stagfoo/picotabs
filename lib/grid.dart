/// Grid coordinate maths for a page of tiles.
///
/// Ported from picopages, where the shape of it was settled by use. The one
/// decision everything else follows from: a tile has a real, stored (row, col)
/// rather than a position implied by its place in a list.
///
/// That is what a flow or packing layout cannot do. Move a tile away from a
/// spot in one of those and everything reflows to close the gap, so "leave this
/// cell empty" is not a thing you can say. Here it is the default.
///
/// There is no maximum row. The grid grows downward as far as tiles are placed.
///
/// Pure Dart — no Flutter — so every rule about fitting, moving and resizing is
/// checked without laying anything out.
library;

/// A cell, as (row, column).
typedef Cell = (int, int);

/// Anything that can sit on the grid.
///
/// An interface rather than a concrete class because a page holds apps today
/// and will hold folders and widgets later, and none of the geometry cares
/// which it is moving.
abstract class GridItem {
  String get id;
  int get row;
  set row(int value);
  int get col;
  set col(int value);
  int get colSpan;
  set colSpan(int value);
  int get rowSpan;
  set rowSpan(int value);

  /// Where an item sits before it has been given a real position.
  static const unplaced = -1;

  bool get placed => row >= 0 && col >= 0;
}

class GridPlacement {
  const GridPlacement({this.crossAxisCount = 4});

  final int crossAxisCount;

  /// Every cell a footprint covers.
  Set<Cell> cellsFor(int row, int col, int colSpan, int rowSpan) {
    final cells = <Cell>{};
    for (var r = row; r < row + rowSpan; r++) {
      for (var c = col; c < col + colSpan; c++) {
        cells.add((r, c));
      }
    }
    return cells;
  }

  bool _fits(Set<Cell> occupied, int row, int col, int colSpan, int rowSpan) {
    if (row < 0 || col < 0) return false;
    if (col + colSpan > crossAxisCount) return false;
    return cellsFor(row, col, colSpan, rowSpan)
        .every((cell) => !occupied.contains(cell));
  }

  Set<Cell> _occupiedExcept(List<GridItem> items, String exceptId) {
    final occupied = <Cell>{};
    for (final other in items) {
      if (other.id == exceptId || !other.placed) continue;
      occupied.addAll(
        cellsFor(other.row, other.col, other.colSpan, other.rowSpan),
      );
    }
    return occupied;
  }

  /// Whether [item] could become [newColSpan] x [newRowSpan] where it stands.
  ///
  /// Resizing needs the same collision check as moving — it is easy to guard
  /// one and forget the other, and growing a tile straight into its neighbour
  /// breaks the same invariant either way.
  bool canResize(
    List<GridItem> items,
    GridItem item,
    int newColSpan,
    int newRowSpan,
  ) {
    if (newColSpan < 1 || newRowSpan < 1) return false;
    if (item.col + newColSpan > crossAxisCount) return false;
    final wanted = cellsFor(item.row, item.col, newColSpan, newRowSpan);
    final occupied = _occupiedExcept(items, item.id);
    return wanted.every((cell) => !occupied.contains(cell));
  }

  /// Gives a real position to anything that has not got one, first fit.
  ///
  /// Placed items are left exactly where they are: an app arriving because it
  /// was installed must not rearrange a page somebody built.
  List<GridItem> assignMissingPositions(List<GridItem> items) {
    final occupied = <Cell>{};
    for (final item in items) {
      if (item.placed) {
        occupied.addAll(
          cellsFor(item.row, item.col, item.colSpan, item.rowSpan),
        );
      }
    }

    final placed = <GridItem>[];
    for (final item in items.where((item) => !item.placed)) {
      var row = 0;
      var col = 0;
      while (!_fits(occupied, row, col, item.colSpan, item.rowSpan)) {
        col++;
        if (col >= crossAxisCount) {
          col = 0;
          row++;
        }
      }
      item.row = row;
      item.col = col;
      occupied.addAll(cellsFor(row, col, item.colSpan, item.rowSpan));
      placed.add(item);
    }
    return placed;
  }

  /// Moves [item] one step in a direction, jumping past anything in the way.
  ///
  /// Not a swap and not a single-cell nudge. It scans cell by cell in the
  /// direction asked for and lands on the first spot the item's own footprint
  /// actually fits in, however far that is — so a tile boxed in on one side
  /// does not need everything around it relocated first just to get past.
  ///
  /// Returns what it moved, or nothing if the scan ran off the grid. Left,
  /// right and up are bounded and can fail; down cannot, because the grid grows
  /// and the occupied set is finite, so a free row always exists eventually.
  List<GridItem> moveByDelta(
    List<GridItem> items,
    GridItem item,
    int dRow,
    int dCol,
  ) {
    if (dRow == 0 && dCol == 0) return const [];
    final occupied = _occupiedExcept(items, item.id);

    var row = item.row;
    var col = item.col;
    while (true) {
      row += dRow;
      col += dCol;
      if (row < 0 || col < 0 || col + item.colSpan > crossAxisCount) {
        return const [];
      }
      if (_fits(occupied, row, col, item.colSpan, item.rowSpan)) {
        item.row = row;
        item.col = col;
        return [item];
      }
    }
  }

  /// Puts [item] exactly where it is dropped, if it fits there.
  ///
  /// The direct counterpart to [moveByDelta]: dragging asks for one specific
  /// cell and either gets it or does not, where a directional nudge is happy to
  /// travel. Refusing beats sliding somewhere else — a tile that lands
  /// somewhere you did not point at reads as the drag having gone wrong.
  bool placeAt(List<GridItem> items, GridItem item, int row, int col) {
    final occupied = _occupiedExcept(items, item.id);
    if (!_fits(occupied, row, col, item.colSpan, item.rowSpan)) return false;
    item.row = row;
    item.col = col;
    return true;
  }

  /// The first row with nothing on it, which is how tall a page has to be.
  int rowsUsed(List<GridItem> items) {
    var rows = 0;
    for (final item in items) {
      if (!item.placed) continue;
      final bottom = item.row + item.rowSpan;
      if (bottom > rows) rows = bottom;
    }
    return rows;
  }

  /// Every cell on a page that has nothing in it, down to [rowsUsed].
  ///
  /// Used to show the gaps while arranging: an empty cell is a real place you
  /// can put something, and it is worth being able to see them.
  Set<Cell> gaps(List<GridItem> items) {
    final occupied = <Cell>{};
    for (final item in items) {
      if (!item.placed) continue;
      occupied.addAll(
        cellsFor(item.row, item.col, item.colSpan, item.rowSpan),
      );
    }
    final out = <Cell>{};
    for (var row = 0; row < rowsUsed(items); row++) {
      for (var col = 0; col < crossAxisCount; col++) {
        if (!occupied.contains((row, col))) out.add((row, col));
      }
    }
    return out;
  }
}
