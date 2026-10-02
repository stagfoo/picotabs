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

  group('pictures on the grid', () {
    test('a picture goes on as a tile of its own', () {
      final b = board();
      final tile = b.addImage('tab-home', 'm-1')!;
      expect(tile.isImage, isTrue);
      expect(tile.mediaId, 'm-1');
      // No app, so nothing to launch and nothing to look up in the app list.
      expect(tile.appId, isNull);
      expect(tile.placed, isFalse);
    });

    test('the same picture can be placed more than once', () {
      // Unlike an app: two tiles for one app would both launch the same thing,
      // where two of a picture are two pictures.
      final b = board();
      final first = b.addImage('tab-home', 'm-1')!;
      final second = b.addImage('tab-home', 'm-1')!;
      expect(first.id, isNot(second.id));
      expect(b['tab-home']!.tiles, hasLength(2));
    });

    test('a picture needs a picture', () {
      final b = board();
      expect(b.addImage('tab-home', ''), isNull);
      expect(b.addImage('nope', 'm-1'), isNull);
    });

    test('round-trips through storage', () {
      final b = board();
      final tile = b.addImage('tab-home', 'm-1')!;
      tile.row = 2;
      tile.col = 1;
      tile.colSpan = 2;
      tile.rowSpan = 2;

      final back = Board.fromJson(b.toJson())['tab-home']!.tiles.single;
      expect(back.isImage, isTrue);
      expect(back.mediaId, 'm-1');
      expect(back.id, tile.id);
      expect((back.row, back.col, back.colSpan, back.rowSpan), (2, 1, 2, 2));
    });

    test('a stored picture with no picture left is dropped', () {
      // It would draw as a blank square with nothing to tap and no way to say
      // what it was meant to be.
      final tab = TabPage.fromJson({
        'id': 'tab-home',
        'name': 'Home',
        'tiles': [
          {'appId': 'img-1', 'kind': 'image', 'row': 0, 'col': 0},
        ],
      });
      expect(tab!.tiles, isEmpty);
    });

    test('is not swept away with uninstalled apps', () {
      // The sweep asks the app list about every tile. A picture is never in it,
      // so keying that check on the id alone would clear every picture the first
      // time the launcher looked.
      final b = board();
      b.add('tab-home', 'com.a/M');
      final picture = b.addImage('tab-home', 'm-1')!;
      final appTiles = [
        for (final tile in b['tab-home']!.tiles)
          if (tile.appId != null) tile,
      ];
      expect(appTiles, hasLength(1));
      expect(appTiles.single.id, 'com.a/M');
      expect(b['tab-home']!.tiles, contains(picture));
    });
  });

  group('a custom icon', () {
    test('is remembered per tile and round-trips', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.replace('tab-home', 'com.a/M', (t) => t.withIcon('m-icon'));

      final back = Board.fromJson(b.toJson())['tab-home']!.tileFor('com.a/M')!;
      expect(back.iconMediaId, 'm-icon');
      expect(back.isImage, isFalse);
      expect(back.appId, 'com.a/M');
    });

    test('is cleared by setting it to nothing', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.replace('tab-home', 'com.a/M', (t) => t.withIcon('m-icon'));
      b.replace('tab-home', 'com.a/M', (t) => t.withIcon(null));
      expect(b['tab-home']!.tileFor('com.a/M')!.iconMediaId, isNull);
    });

    test('keeps the tile where it was', () {
      // Changing a picture must not move the tile: the grid holds real
      // coordinates, and a replaced tile arriving unplaced would jump.
      final b = board();
      b.add('tab-home', 'com.a/M');
      final tile = b['tab-home']!.tileFor('com.a/M')!;
      tile.row = 3;
      tile.col = 2;
      b.replace('tab-home', 'com.a/M', (t) => t.withIcon('m-icon'));

      final after = b['tab-home']!.tileFor('com.a/M')!;
      expect((after.row, after.col), (3, 2));
    });

    test('travels with the app when it moves tab', () {
      // The icon is a choice about the app, not about where it was sitting.
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.replace('tab-home', 'com.a/M', (t) => t.withIcon('m-icon'));
      expect(b.moveApp('tab-home', 'tab-all', 'com.a/M'), isTrue);
      expect(b['tab-all']!.tileFor('com.a/M')!.iconMediaId, 'm-icon');
    });

    test('replace reports whether it found anything', () {
      final b = board();
      expect(b.replace('tab-home', 'nothing', (t) => t), isFalse);
      expect(b.replace('nope', 'nothing', (t) => t), isFalse);
    });
  });

  group('a tab background', () {
    test('defaults to none and round-trips when set', () {
      final b = board();
      expect(b['tab-home']!.backgroundMediaId, isNull);
      expect(b.toJson().first.containsKey('background'), isFalse);

      b['tab-home']!.backgroundMediaId = 'm-bg';
      final back = Board.fromJson(b.toJson());
      expect(back['tab-home']!.backgroundMediaId, 'm-bg');
    });

    test('is per tab, so one tab does not change another', () {
      final b = board();
      b['tab-home']!.backgroundMediaId = 'm-bg';
      expect(b['tab-all']!.backgroundMediaId, isNull);
    });
  });

  group('pictures nothing points at', () {
    test('the board lists every picture it still needs', () {
      final b = board();
      b.add('tab-home', 'com.a/M');
      b.replace('tab-home', 'com.a/M', (t) => t.withIcon('m-icon'));
      b.addImage('tab-home', 'm-tile');
      b['tab-all']!.backgroundMediaId = 'm-bg';

      expect(b.mediaIds, {'m-icon', 'm-tile', 'm-bg'});
    });

    test('a removed tile stops the board needing its picture', () {
      // This is what the reap reads, so a picture dropping out of it is what
      // actually deletes the file.
      final b = board();
      final tile = b.addImage('tab-home', 'm-tile')!;
      expect(b.mediaIds, contains('m-tile'));
      b.remove('tab-home', tile.id);
      expect(b.mediaIds, isEmpty);
    });

    test('a deleted tab takes its pictures out of the list too', () {
      final b = board();
      b.addImage('tab-home', 'm-tile');
      b['tab-home']!.backgroundMediaId = 'm-bg';
      b.removeTab('tab-home');
      expect(b.mediaIds, isEmpty);
    });
  });

  group('boards saved before pictures existed', () {
    test('load unchanged', () {
      // Every tile in an existing install looks like this. The stored key is
      // still appId for exactly this reason - renaming it would have emptied
      // every tab on the first launch after the update.
      final back = Board.fromJson([
        {
          'id': 'tab-home',
          'name': 'Home',
          'tiles': [
            {'appId': 'com.a/M', 'row': 0, 'col': 0},
            {'appId': 'com.b/M', 'row': 0, 'col': 1, 'colSpan': 2},
          ],
        },
      ]);
      final tiles = back['tab-home']!.tiles;
      expect(tiles, hasLength(2));
      expect(tiles.first.appId, 'com.a/M');
      expect(tiles.first.isImage, isFalse);
      expect(tiles.first.iconMediaId, isNull);
      expect(tiles[1].colSpan, 2);
      expect(back['tab-home']!.backgroundMediaId, isNull);
    });
  });
}
