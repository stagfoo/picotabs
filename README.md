# picotabs

An Android home launcher: tabs across the top, a grid of apps under each.

## The grid

Lifted from [picopages](https://github.com/stagfoo/picopages), where the shape
of it was settled by use. One decision everything else follows from: **a tile
has a real, stored `(row, col)`** rather than a position implied by its place in
a list.

That is the thing a flow or packing layout cannot do. Move a tile away from a
spot in one of those and everything reflows to close the gap, so "leave this
cell empty" is not a sentence you can say. Here it is the default — the hole
stays until you put something in it.

The rest follows:

- **Moving jumps to the nearest free spot** in the direction asked for, however
  far that is, rather than swapping or nudging one cell. A tile boxed in on one
  side should not need everything around it relocated first just to get past.
- **Dropping refuses rather than sliding.** A drag asked for one specific cell;
  landing anywhere else reads as the drag having gone wrong. A directional nudge
  is happy to travel, a drop is not.
- **Resizing gets the same collision check as moving** — the same invariant, and
  the easy one to guard on one path and forget on the other.
- **Down never fails.** The grid grows, and the occupied set is finite, so a
  free row always exists eventually. Left, right and up are bounded and can.

Four columns, locked. A tile's stored column only means anything against a fixed
count — change it and every saved layout shifts.

## Tabs

A tab is a page of that grid and nothing more. Deliberately less than a folder:
every tab's name is visible at once, so deciding where an app lives costs a
glance rather than opening things to look inside them.

The same app can be on several tabs. It is one app either way — a tile is a
placement, not a copy — so "on Home and on Work" is a sentence about where you
look for it, not about how many of it there are. Taking it off one leaves the
others alone; uninstalling it takes it off all of them.

Eight tabs maximum, which is roughly what fits across the top without scrolling
becoming the way you find things.

## Using it

- **Tap** a tile to launch, **long-press** for its menu.
- **Tap the tab you are already on** to rename, reorder or delete it. (Not a
  long-press: that fights the bar's own scrolling.)
- **Arrange** makes tiles wobble and drag, and shows the empty cells — an empty
  cell is a real place you can put something, and worth being able to see.
- **Resize** is a sheet rather than a pinch. A pinch on a tile competes with the
  page's scroll *and* with the drag that moves it, and loses often enough to
  feel broken; a list of the tiles with their sizes is duller and works.

While arranging, the page's horizontal swipe is switched off. Dragging a tile
sideways and swiping between tabs both want the same gesture, and the tile has
to win or you cannot move one sideways at all.

## Layout

```
lib/grid.dart     the coordinate maths — pure Dart, 27 tests
lib/board.dart    tabs, tiles and the rules about them — pure Dart, 24 tests
lib/store.dart    the board between launches
lib/home_screen.dart   the tab bar and the page under it
```

Neither `grid.dart` nor `board.dart` imports Flutter, which is why 51 tests
cover the parts that decide how it behaves without laying anything out.
