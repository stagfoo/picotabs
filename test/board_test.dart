import 'package:flutter_test/flutter_test.dart';
import 'package:picotabs/board.dart';

Board board() => Board.seed();

void main() {
  group('an app on a tab', () {
    test('goes on unplaced, for the grid to position', () {
      // Where it lands is one decision made in one place, so adding one app
      // and adding forty behave the same way.
      final b = board();
      expect(b.add('tab-home', 'com.a/M'), isTrue);

      final tile = b['tab-home']!.tileFor('com.a/M')!;
      expect(tile.placed, isFalse);
    });

    test('cannot be added to the same tab twice', () {
      // Two tiles for one app on one page would both launch the same thing,
      // and only one could be the one you meant to move.
      final b = board();
      b.add('tab-home', 'com.a/M');
      expect(b.add('tab-home', 'com.a/M'), isFalse);
      expect(b['tab-home']!.tiles, hasLength(1));
    });

    test('can be on several tabs at once', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.add('tab-all', 'com.a/M');

      expect(b.tabsWith('com.a/M').map((t) => t.id), ['tab-home', 'tab-all']);
    });

    test('taken off one tab stays on the others', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.add('tab-all', 'com.a/M');

      expect(b.remove('tab-home', 'com.a/M'), isTrue);
      expect(b.tabsWith('com.a/M').map((t) => t.id), ['tab-all']);
    });

    test('goes from everywhere when it is uninstalled', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.add('tab-all', 'com.a/M');

      expect(b.removeEverywhere('com.a/M'), 2);
      expect(b.tabsWith('com.a/M'), isEmpty);
    });

    test('added to a tab that does not exist changes nothing', () {
      final b = board();
      expect(b.add('tab-ghost', 'com.a/M'), isFalse);
    });
  });

  group('moving an app between tabs', () {
    test('arrives unplaced rather than keeping its old cell', () {
      // A cell free on one page is usually taken on another, so a tile that
      // kept its coordinates would land on top of something.
      final b = board();
      b.add('tab-home', 'com.a/M');
      b['tab-home']!.tileFor('com.a/M')!
        ..row = 3
        ..col = 2;

      expect(b.moveApp('tab-home', 'tab-all', 'com.a/M'), isTrue);

      expect(b['tab-home']!.holds('com.a/M'), isFalse);
      expect(b['tab-all']!.tileFor('com.a/M')!.placed, isFalse);
    });

    test('to a tab that already has it is refused, and takes nothing away', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.add('tab-all', 'com.a/M');

      expect(b.moveApp('tab-home', 'tab-all', 'com.a/M'), isFalse);
      expect(b['tab-home']!.holds('com.a/M'), isTrue,
          reason: 'a refused move must not be a delete');
    });

    test('to the tab it is already on is not a move', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      expect(b.moveApp('tab-home', 'tab-home', 'com.a/M'), isFalse);
      expect(b['tab-home']!.holds('com.a/M'), isTrue);
    });
  });

  group('tabs', () {
    test('can be added and named', () {
      final b = board();
      final tab = b.addTab('  Work  ');
      expect(tab?.name, 'Work', reason: 'trimmed');
      expect(b.tabs, hasLength(3));
    });

    test('cannot be nameless', () {
      expect(board().addTab('   '), isNull);
    });

    test('stop at a number you can still see across the top', () {
      final b = board();
      while (b.tabs.length < Board.maxTabs) {
        expect(b.addTab('t${b.tabs.length}'), isNotNull);
      }
      expect(b.addTab('one too many'), isNull);
      expect(b.tabs, hasLength(Board.maxTabs));
    });

    test('removing one takes what was on it', () {
      final b = board();
      b.add('tab-all', 'com.a/M');
      expect(b.removeTab('tab-all'), isTrue);
      expect(b['tab-all'], isNull);
      expect(b.tabsWith('com.a/M'), isEmpty);
    });

    test('the last one cannot be removed', () {
      // A launcher with no tabs has nowhere to show anything, and no control
      // left to make a tab with.
      final b = board();
      b.removeTab('tab-all');
      expect(b.tabs, hasLength(1));
      expect(b.removeTab('tab-home'), isFalse);
      expect(b.tabs, hasLength(1));
    });

    test('can be renamed, but not to nothing', () {
      final b = board();
      expect(b.renameTab('tab-home', 'Daily'), isTrue);
      expect(b['tab-home']!.name, 'Daily');
      expect(b.renameTab('tab-home', '  '), isFalse);
      expect(b['tab-home']!.name, 'Daily');
    });

    test('can be reordered along the bar', () {
      final b = board();
      expect(b.reorderTab('tab-all', 0), isTrue);
      expect(b.tabs.map((t) => t.id), ['tab-all', 'tab-home']);
    });

    test('reordering to where it already is does nothing', () {
      final b = board();
      expect(b.reorderTab('tab-home', 0), isFalse);
    });

    test('reordering past the end clamps rather than throwing', () {
      final b = board();
      expect(b.reorderTab('tab-home', 99), isTrue);
      expect(b.tabs.last.id, 'tab-home');
    });
  });

  group('storage', () {
    test('round-trips tabs, tiles and their spans', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b['tab-home']!.tileFor('com.a/M')!
        ..row = 2
        ..col = 1
        ..colSpan = 2
        ..rowSpan = 3;
      b.renameTab('tab-all', 'Everything');

      final back = Board.fromJson(b.toJson());
      final tile = back['tab-home']!.tileFor('com.a/M')!;

      expect(back.tabs, hasLength(2));
      expect(back['tab-all']!.name, 'Everything');
      expect((tile.row, tile.col, tile.colSpan, tile.rowSpan), (2, 1, 2, 3));
    });

    test('a span of zero is refused on load', () {
      // It would lay out as nothing, which cannot then be pressed to fix.
      final restored = Board.fromJson([
        {
          'id': 'tab-home',
          'name': 'Home',
          'tiles': [
            {'appId': 'com.a/M', 'row': 0, 'col': 0, 'colSpan': 0, 'rowSpan': 0},
          ],
        },
      ]);
      final tile = restored['tab-home']!.tileFor('com.a/M')!;
      expect(tile.colSpan, 1);
      expect(tile.rowSpan, 1);
    });

    test('a duplicate placement is dropped on load', () {
      final restored = Board.fromJson([
        {
          'id': 'tab-home',
          'name': 'Home',
          'tiles': [
            {'appId': 'com.a/M', 'row': 0, 'col': 0},
            {'appId': 'com.a/M', 'row': 1, 'col': 1},
          ],
        },
      ]);
      expect(restored['tab-home']!.tiles, hasLength(1));
    });

    test('a tile with no app is not a tile', () {
      final restored = Board.fromJson([
        {'id': 'tab-home', 'name': 'Home', 'tiles': [
          {'row': 0, 'col': 0},
          {'appId': '', 'row': 0, 'col': 1},
        ]},
      ]);
      expect(restored['tab-home']!.tiles, isEmpty);
    });

    test('nonsense loads as a fresh board rather than nothing', () {
      // There is no way to repair a board with no tabs from inside the
      // launcher, so an unreadable one has to become a usable one.
      expect(Board.fromJson('not a board').tabs, hasLength(2));
      expect(Board.fromJson(const []).tabs, hasLength(2));
      expect(Board.fromJson([
        {'name': 'no id'},
      ]).tabs, hasLength(2));
    });

    test('two tabs claiming the same id keep only the first', () {
      final restored = Board.fromJson([
        {'id': 'tab-home', 'name': 'First', 'tiles': []},
        {'id': 'tab-home', 'name': 'Second', 'tiles': []},
      ]);
      expect(restored.tabs, hasLength(1));
      expect(restored['tab-home']!.name, 'First');
    });
  });
}
