import 'package:flutter_test/flutter_test.dart';
import 'package:picotabs/board.dart';
import 'package:picotabs/grid.dart';

Tile tile(String id, {int row = -1, int col = -1, int colSpan = 1, int rowSpan = 1}) =>
    Tile.app(id, row: row, col: col, colSpan: colSpan, rowSpan: rowSpan);

const grid = GridPlacement(crossAxisCount: 4);

List<GridItem> items(List<Tile> tiles) => tiles.cast<GridItem>();

void main() {
  group('first fit', () {
    test('fills left to right, then down', () {
      final tiles = [for (var i = 0; i < 5; i++) tile('a$i')];
      grid.assignMissingPositions(items(tiles));

      expect(tiles.map((t) => (t.row, t.col)),
          [(0, 0), (0, 1), (0, 2), (0, 3), (1, 0)]);
    });

    test('leaves a placed tile exactly where it is', () {
      // An app arriving because it was installed must not rearrange a page
      // somebody built.
      final anchored = tile('anchored', row: 5, col: 2);
      final arriving = tile('arriving');

      grid.assignMissingPositions(items([anchored, arriving]));

      expect((anchored.row, anchored.col), (5, 2));
      expect((arriving.row, arriving.col), (0, 0));
    });

    test('goes round a wide tile rather than under it', () {
      final wide = tile('wide', row: 0, col: 0, colSpan: 4);
      final next = tile('next');

      grid.assignMissingPositions(items([wide, next]));

      expect((next.row, next.col), (1, 0));
    });

    test('fits a tall tile only where it has the height', () {
      final tall = tile('tall', rowSpan: 2);
      final blocker = tile('blocker', row: 1, col: 0);

      grid.assignMissingPositions(items([blocker, tall]));

      expect((tall.row, tall.col), (0, 1));
    });

    test('places nothing twice', () {
      final tiles = [for (var i = 0; i < 12; i++) tile('a$i')];
      grid.assignMissingPositions(items(tiles));

      final cells = <Cell>{};
      for (final t in tiles) {
        for (final cell in grid.cellsFor(t.row, t.col, t.colSpan, t.rowSpan)) {
          expect(cells.add(cell), isTrue, reason: 'two tiles on $cell');
        }
      }
    });
  });

  group('moving', () {
    test('a clear step just moves', () {
      final one = tile('one', row: 0, col: 0);
      grid.moveByDelta(items([one]), one, 0, 1);
      expect((one.row, one.col), (0, 1));
    });

    test('jumps clean past whatever is in the way', () {
      // Not a swap and not a nudge: a tile boxed in on one side should not
      // need everything around it relocated first just to get past.
      final mover = tile('mover', row: 0, col: 0);
      final wall = [tile('w1', row: 0, col: 1), tile('w2', row: 0, col: 2)];

      grid.moveByDelta(items([mover, ...wall]), mover, 0, 1);

      expect((mover.row, mover.col), (0, 3));
    });

    test('refuses when the scan runs off the side', () {
      final stuck = tile('stuck', row: 0, col: 3);
      final moved = grid.moveByDelta(items([stuck]), stuck, 0, 1);

      expect(moved, isEmpty);
      expect((stuck.row, stuck.col), (0, 3), reason: 'nothing mutated');
    });

    test('refuses to go above the first row', () {
      final top = tile('top', row: 0, col: 0);
      expect(grid.moveByDelta(items([top]), top, -1, 0), isEmpty);
    });

    test('downward always finds somewhere, because the grid grows', () {
      final mover = tile('mover', row: 0, col: 0);
      final wall = [for (var r = 1; r < 30; r++) tile('w$r', row: r, col: 0)];

      final moved = grid.moveByDelta(items([mover, ...wall]), mover, 1, 0);

      expect(moved, isNotEmpty);
      expect(mover.row, 30);
    });

    test('a wide tile cannot be moved half off the edge', () {
      final wide = tile('wide', row: 0, col: 1, colSpan: 3);
      expect(grid.moveByDelta(items([wide]), wide, 0, 1), isEmpty);
    });

    test('a move of nothing is not a move', () {
      final one = tile('one', row: 2, col: 2);
      expect(grid.moveByDelta(items([one]), one, 0, 0), isEmpty);
      expect((one.row, one.col), (2, 2));
    });
  });

  group('dropping somewhere exact', () {
    test('lands where it was dropped when the spot is free', () {
      final one = tile('one', row: 0, col: 0);
      expect(grid.placeAt(items([one]), one, 3, 2), isTrue);
      expect((one.row, one.col), (3, 2));
    });

    test('refuses rather than sliding somewhere else', () {
      // A directional nudge is happy to travel; a drag asked for one specific
      // cell, and landing anywhere else reads as the drag having gone wrong.
      final one = tile('one', row: 0, col: 0);
      final taken = tile('taken', row: 3, col: 2);

      expect(grid.placeAt(items([one, taken]), one, 3, 2), isFalse);
      expect((one.row, one.col), (0, 0));
    });

    test('refuses a drop that hangs off the edge', () {
      final wide = tile('wide', row: 0, col: 0, colSpan: 2);
      expect(grid.placeAt(items([wide]), wide, 0, 3), isFalse);
    });

    test('a tile may be dropped back on itself', () {
      final one = tile('one', row: 1, col: 1);
      expect(grid.placeAt(items([one]), one, 1, 1), isTrue);
    });
  });

  group('resizing', () {
    test('growing into free space is allowed', () {
      final one = tile('one', row: 0, col: 0);
      expect(grid.canResize(items([one]), one, 2, 2), isTrue);
    });

    test('growing into a neighbour is not', () {
      // The same invariant as moving, and the easy one to guard on one path
      // and forget on the other.
      final one = tile('one', row: 0, col: 0);
      final neighbour = tile('neighbour', row: 0, col: 1);

      expect(grid.canResize(items([one, neighbour]), one, 2, 1), isFalse);
    });

    test('growing off the edge is not', () {
      final one = tile('one', row: 0, col: 3);
      expect(grid.canResize(items([one]), one, 2, 1), isFalse);
    });

    test('shrinking always fits, being a subset of what it had', () {
      final big = tile('big', row: 0, col: 0, colSpan: 3, rowSpan: 3);
      final crowd = [
        tile('a', row: 0, col: 3),
        tile('b', row: 3, col: 0),
      ];
      expect(grid.canResize(items([big, ...crowd]), big, 1, 1), isTrue);
    });

    test('a span of nothing is refused', () {
      final one = tile('one', row: 0, col: 0);
      expect(grid.canResize(items([one]), one, 0, 1), isFalse);
      expect(grid.canResize(items([one]), one, 1, 0), isFalse);
    });
  });

  group('how tall the page is', () {
    test('counts to the bottom of the lowest tile', () {
      final tiles = [
        tile('a', row: 0, col: 0),
        tile('b', row: 2, col: 0, rowSpan: 3),
      ];
      expect(grid.rowsUsed(items(tiles)), 5);
    });

    test('an empty page has no rows', () {
      expect(grid.rowsUsed(const []), 0);
    });

    test('an unplaced tile does not stretch the page', () {
      expect(grid.rowsUsed(items([tile('nowhere')])), 0);
    });
  });

  group('gaps', () {
    test('are the cells nothing is on', () {
      final tiles = [tile('a', row: 0, col: 0), tile('b', row: 0, col: 2)];
      expect(grid.gaps(items(tiles)), {(0, 1), (0, 3)});
    });

    test('include a hole left behind by a tile that moved away', () {
      // The whole reason positions are stored rather than implied: moving a
      // tile leaves a real hole instead of everything closing up.
      final a = tile('a', row: 0, col: 0);
      final b = tile('b', row: 1, col: 0);
      grid.moveByDelta(items([a, b]), a, 1, 0);

      expect(grid.gaps(items([a, b])), contains((0, 0)));
    });

    test('stop at the bottom of the last row used', () {
      final tiles = [tile('a', row: 0, col: 0)];
      expect(grid.gaps(items(tiles)), {(0, 1), (0, 2), (0, 3)});
    });
  });

  group('pictures sit on the grid like anything else', () {
    test('a picture tile is placed, moved and resized the same way', () {
      // The grid was written to an interface for this reason: none of the
      // geometry asks what it is moving.
      final picture = Tile.image('m-1');
      final app = tile('com.a/M');
      final all = items([app, picture]);
      grid.assignMissingPositions(all);

      expect(picture.placed, isTrue);
      expect(grid.canResize(all, picture, 2, 2), isTrue);
      picture.colSpan = 2;
      picture.rowSpan = 2;
      // And an app cannot then be dropped on top of it.
      expect(
        grid.cellsFor(picture.row, picture.col, 2, 2)
            .contains((app.row, app.col)),
        isFalse,
      );
    });

    test('two tiles of the same picture do not collide', () {
      // They have different ids, so the grid sees two items rather than one it
      // keeps rediscovering.
      final a = Tile.image('m-1');
      final b = Tile.image('m-1');
      expect(a.id, isNot(b.id));
      final all = items([a, b]);
      grid.assignMissingPositions(all);
      expect((a.row, a.col), isNot((b.row, b.col)));
    });
  });
}
