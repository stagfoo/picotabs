import 'dart:async';

import 'package:flutter/material.dart';

import 'app_cache.dart';
import 'app_icon.dart';
import 'app_picker_screen.dart';
import 'board.dart';
import 'grid.dart';
import 'launcher_bridge.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';

/// The launcher: tabs across the top, a page of tiles under each.
///
/// A tab is a page and nothing more. That is deliberately less than a folder —
/// every tab's name is visible at once, so deciding where an app lives costs a
/// glance rather than opening things to look inside them.
///
/// The grid underneath is picopages': every tile has a real, stored (row, col)
/// rather than a position implied by list order, which is what makes a
/// deliberately empty cell a thing you can have.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _store = BoardStore();
  final _appCache = AppCache();
  static const _grid = GridPlacement(crossAxisCount: Metrics.columns);

  Board _board = Board.seed();
  Map<String, LaunchableApp> _apps = const {};
  TabController? _tabs;
  bool _loading = true;

  /// Arranging: tiles wobble, drag moves them, and the empty cells show.
  bool _organising = false;
  String? _dragging;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshApps());
  }

  Future<void> _load() async {
    try {
      final board = await _store.load();
      final cached = await _appCache.load();
      if (!mounted) return;
      setState(() {
        _board = board;
        _apps = _index(cached?.apps ?? const []);
        _loading = false;
      });
      _rebuildTabs();
      _placeEverything();
      await _refreshApps();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshApps() async {
    try {
      final apps = await LauncherBridge.instance.listApps();
      if (!mounted) return;
      final index = _index(apps);

      // An app that is gone is taken off every tab it was on. Leaving it would
      // be a tile that cannot say what it is and does nothing when pressed.
      var changed = false;
      for (final tab in _board.tabs) {
        for (final tile in [...tab.tiles]) {
          if (!index.containsKey(tile.appId)) {
            changed |= _board.remove(tab.id, tile.appId);
          }
        }
      }

      setState(() => _apps = index);
      await _appCache.save(apps);
      if (changed) await _save();
    } catch (_) {
      // A refresh that fails leaves the last list in place, which beats an
      // empty launcher.
    }
  }

  static Map<String, LaunchableApp> _index(List<LaunchableApp> apps) =>
      {for (final app in apps) app.id: app};

  Future<void> _save() => _store.save(_board);

  void _rebuildTabs() {
    final was = _tabs?.index ?? 0;
    _tabs?.dispose();
    _tabs = TabController(
      length: _board.tabs.length,
      vsync: this,
      initialIndex: was.clamp(0, _board.tabs.length - 1),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  /// Gives every tile that has not got a position one, first fit.
  void _placeEverything() {
    for (final tab in _board.tabs) {
      _grid.assignMissingPositions(tab.tiles.cast<GridItem>());
    }
  }

  TabPage get _here => _board.tabs[(_tabs?.index ?? 0).clamp(0, _board.tabs.length - 1)];

  // ------------------------------------------------------------------ edits

  Future<void> _addApps() async {
    final tab = _here;
    final chosen = await showAppPicker(
      context,
      placeName: tab.name,
      accent: const Color(0xFFCB5B2E),
      installed: _apps.values.toList(),
      alreadyHere: {for (final tile in tab.tiles) tile.appId},
      alsoIn: {
        for (final app in _apps.keys)
          if (_board.tabsWith(app).where((t) => t.id != tab.id).isNotEmpty)
            app: [
              for (final other in _board.tabsWith(app))
                if (other.id != tab.id) other.name,
            ],
      },
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    for (final appId in chosen) {
      _board.add(tab.id, appId);
    }
    _grid.assignMissingPositions(tab.tiles.cast<GridItem>());
    setState(() {});
    await _save();
  }

  Future<void> _tileMenu(Tile tile) async {
    final app = _apps[tile.appId];
    final elsewhere =
        _board.tabsWith(tile.appId).where((t) => t.id != _here.id).toList();

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Paper.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(app?.label ?? tile.appId,
                  style: text(size: 15, weight: 600)),
              subtitle: Text(
                elsewhere.isEmpty
                    ? 'Only on ${_here.name}'
                    : 'Also on ${elsewhere.map((t) => t.name).join(', ')}',
                style: text(size: 11, color: Paper.dim),
              ),
            ),
            const Divider(height: 1, color: Paper.edge),
            ListTile(
              leading: const Icon(Icons.open_with_rounded, color: Paper.dim),
              title: Text('Arrange', style: text(size: 14)),
              subtitle: Text('Drag tiles, pinch a tile to resize',
                  style: text(size: 11, color: Paper.dim)),
              onTap: () => Navigator.pop(context, 'organise'),
            ),
            for (final other in _board.tabs)
              if (other.id != _here.id && !other.holds(tile.appId))
                ListTile(
                  leading:
                      const Icon(Icons.drive_file_move_outlined, color: Paper.dim),
                  title: Text('Move to ${other.name}', style: text(size: 14)),
                  onTap: () => Navigator.pop(context, 'move:${other.id}'),
                ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded,
                  color: Color(0xFFC0503A)),
              title: Text('Take off ${_here.name}', style: text(size: 14)),
              subtitle: Text(
                elsewhere.isEmpty
                    ? 'From the launcher, not from the phone'
                    : 'It stays on the other tabs',
                style: text(size: 11, color: Paper.dim),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'organise') {
      setState(() => _organising = true);
      return;
    }
    if (choice == 'remove') {
      _board.remove(_here.id, tile.appId);
    } else if (choice.startsWith('move:')) {
      final target = choice.substring(5);
      _board.moveApp(_here.id, target, tile.appId);
      _grid.assignMissingPositions(_board[target]!.tiles.cast<GridItem>());
    }
    setState(() {});
    await _save();
  }

  Future<void> _tabMenu(TabPage tab) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Paper.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tab.name, style: text(size: 15, weight: 600)),
              subtitle: Text('${tab.tiles.length} apps',
                  style: text(size: 11, color: Paper.dim)),
            ),
            const Divider(height: 1, color: Paper.edge),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Paper.dim),
              title: Text('Rename', style: text(size: 14)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            if (_board.indexOf(tab.id) > 0)
              ListTile(
                leading: const Icon(Icons.west_rounded, color: Paper.dim),
                title: Text('Move left', style: text(size: 14)),
                onTap: () => Navigator.pop(context, 'left'),
              ),
            if (_board.indexOf(tab.id) < _board.tabs.length - 1)
              ListTile(
                leading: const Icon(Icons.east_rounded, color: Paper.dim),
                title: Text('Move right', style: text(size: 14)),
                onTap: () => Navigator.pop(context, 'right'),
              ),
            if (_board.tabs.length > 1)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFC0503A)),
                title: Text('Delete tab', style: text(size: 14)),
                subtitle: Text('And the ${tab.tiles.length} tiles on it',
                    style: text(size: 11, color: Paper.dim)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'rename':
        final name = await _askForName('Rename tab', tab.name);
        if (name == null || !mounted) return;
        _board.renameTab(tab.id, name);
      case 'left':
        _board.reorderTab(tab.id, _board.indexOf(tab.id) - 1);
      case 'right':
        _board.reorderTab(tab.id, _board.indexOf(tab.id) + 1);
      case 'delete':
        _board.removeTab(tab.id);
    }
    setState(_rebuildTabs);
    await _save();
  }

  Future<void> _addTab() async {
    if (_board.tabs.length >= Board.maxTabs) {
      _toast('${Board.maxTabs} tabs is as many as fit across the top.');
      return;
    }
    final name = await _askForName('New tab', '');
    if (name == null || !mounted) return;
    final tab = _board.addTab(name);
    if (tab == null) return;
    setState(_rebuildTabs);
    _tabs?.animateTo(_board.tabs.length - 1);
    await _save();
  }

  Future<String?> _askForName(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Paper.surface,
        title: Text(title, style: text(size: 16, weight: 600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: text(size: 15),
          decoration: InputDecoration(
            hintText: 'Home, Work, Games',
            hintStyle: text(size: 14, color: Paper.dim),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: text(size: 13, color: Paper.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Save', style: text(size: 13, weight: 600)),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Paper.ink,
        content: Text(message, style: text(size: 12, color: Paper.surface)),
      ),
    );
  }

  void _launch(Tile tile) {
    final app = _apps[tile.appId];
    if (app == null) {
      _toast('Not installed any more');
      return;
    }
    LauncherBridge.instance.open(app);
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final controller = _tabs;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Home is where back goes on a launcher; the only thing it can leave
        // is arranging.
        if (!didPop && _organising) setState(() => _organising = false);
      },
      child: Scaffold(
        backgroundColor: Paper.ground,
        body: SafeArea(
          child: _loading || controller == null
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFCB5B2E)),
                )
              : Column(
                  children: [
                    _tabBar(controller),
                    Expanded(
                      child: TabBarView(
                        controller: controller,
                        // Arranging and swiping between pages both want a
                        // horizontal drag, and the tile has to win or you
                        // cannot move one sideways at all.
                        physics: _organising
                            ? const NeverScrollableScrollPhysics()
                            : const AlwaysScrollableScrollPhysics(),
                        children: [
                          for (final tab in _board.tabs) _page(tab),
                        ],
                      ),
                    ),
                    _actions(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _tabBar(TabController controller) {
    return SizedBox(
      height: Metrics.tabBarHeight,
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorColor: const Color(0xFFCB5B2E),
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Paper.ink,
              unselectedLabelColor: Paper.dim,
              labelStyle: text(size: 13, weight: 600, letterSpacing: 0.2),
              unselectedLabelStyle: text(size: 13),
              onTap: (index) {
                // A second tap on the tab you are already on opens its menu —
                // there is nowhere else to put it, and a long press there
                // fights the bar's own scrolling.
                if (index == controller.index && !controller.indexIsChanging) {
                  unawaited(_tabMenu(_board.tabs[index]));
                }
              },
              tabs: [
                for (final tab in _board.tabs)
                  Tab(height: Metrics.tabBarHeight, text: tab.name),
              ],
            ),
          ),
          IconButton(
            tooltip: 'New tab',
            onPressed: _addTab,
            icon: const Icon(Icons.add_rounded, size: 20, color: Paper.dim),
          ),
        ],
      ),
    );
  }

  Widget _page(TabPage tab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = Metrics.columns;
        const gutter = Metrics.gutter;
        final cell =
            (constraints.maxWidth - (columns - 1) * gutter - gutter * 2) / columns;
        final step = cell + gutter;

        final rows = _grid.rowsUsed(tab.tiles.cast<GridItem>());
        // A row of headroom while arranging, so there is somewhere to drag a
        // tile *to* at the bottom of a full page.
        final height = (rows + (_organising ? 1 : 0)) * step;

        if (tab.tiles.isEmpty && !_organising) return _empty(tab);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(gutter),
          child: SizedBox(
            height: height <= 0 ? step : height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (_organising)
                  for (final gap in _grid.gaps(tab.tiles.cast<GridItem>()))
                    Positioned(
                      left: gap.$2 * step,
                      top: gap.$1 * step,
                      width: cell,
                      height: cell,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Paper.gap, width: 1.5),
                          borderRadius:
                              BorderRadius.circular(Metrics.tileRadius),
                        ),
                      ),
                    ),
                for (final tile in tab.tiles)
                  AnimatedPositioned(
                    key: ValueKey(tile.appId),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    left: tile.col * step,
                    top: tile.row * step,
                    width: tile.colSpan * cell + (tile.colSpan - 1) * gutter,
                    height: tile.rowSpan * cell + (tile.rowSpan - 1) * gutter,
                    child: _tile(tab, tile, step),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tile(TabPage tab, Tile tile, double step) {
    final app = _apps[tile.appId];
    final dragging = _dragging == tile.appId;

    final body = _TileBody(
      app: app,
      appId: tile.appId,
      wobbling: _organising && !dragging,
      big: tile.colSpan > 1 || tile.rowSpan > 1,
    );

    if (!_organising) {
      return GestureDetector(
        onTap: () => _launch(tile),
        onLongPress: () => _tileMenu(tile),
        child: body,
      );
    }

    // While arranging, a plain drag moves the tile. The page's own horizontal
    // swipe is switched off above so the two cannot fight over it.
    return GestureDetector(
      onTap: () => _tileMenu(tile),
      onPanStart: (_) => setState(() => _dragging = tile.appId),
      onPanUpdate: (details) => _dragTile(tab, tile, details.delta, step),
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _endDrag,
      child: body,
    );
  }

  /// Drags a tile a cell at a time, only landing where it actually fits.
  void _dragTile(TabPage tab, Tile tile, Offset delta, double step) {
    _dragOffset += delta;
    final cols = (_dragOffset.dx / step).round();
    final rows = (_dragOffset.dy / step).round();
    if (cols == 0 && rows == 0) return;

    final items = tab.tiles.cast<GridItem>();
    // Refused rather than slid elsewhere: a drop asked for one specific cell,
    // and landing anywhere else reads as the drag having gone wrong.
    if (_grid.placeAt(items, tile, tile.row + rows, tile.col + cols)) {
      _dragOffset -= Offset(cols * step, rows * step);
      setState(() {});
    }
  }

  Offset _dragOffset = Offset.zero;

  void _endDrag() {
    if (_dragging == null) return;
    setState(() {
      _dragging = null;
      _dragOffset = Offset.zero;
    });
    unawaited(_save());
  }

  Widget _empty(TabPage tab) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nothing on ${tab.name} yet',
                textAlign: TextAlign.center,
                style: text(size: 13, color: Paper.dim)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _addApps,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('Add apps', style: text(size: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Paper.edge)),
      ),
      child: Row(
        children: [
          if (_organising) ...[
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text('Drag tiles to move them',
                  style: text(size: 12, color: Paper.dim)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _organising = false),
              child: Text('Done', style: text(size: 14, weight: 600)),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: _addApps,
              icon: const Icon(Icons.apps_rounded, size: 18),
              label: Text('Add apps', style: text(size: 13)),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Arrange',
              onPressed: () => setState(() => _organising = true),
              icon: const Icon(Icons.open_with_rounded,
                  size: 20, color: Paper.dim),
            ),
            IconButton(
              tooltip: 'Resize tiles',
              onPressed: _resizeSheet,
              icon: const Icon(Icons.aspect_ratio_rounded,
                  size: 20, color: Paper.dim),
            ),
          ],
        ],
      ),
    );
  }

  /// Resizing lives in a sheet rather than on a pinch.
  ///
  /// A pinch on a tile competes with the page's scroll and with the drag that
  /// moves it, and loses often enough to feel broken. A list of the tiles with
  /// their sizes is duller and works every time.
  Future<void> _resizeSheet() async {
    final tab = _here;
    if (tab.tiles.isEmpty) {
      _toast('Nothing on ${tab.name} to resize.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Paper.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            builder: (context, scroll) => ListView(
              controller: scroll,
              children: [
                for (final tile in tab.tiles)
                  ListTile(
                    leading: SizedBox(
                      width: 34,
                      height: 34,
                      child: _apps[tile.appId] == null
                          ? const Icon(Icons.help_outline_rounded,
                              color: Paper.dim)
                          : AppIconImage(app: _apps[tile.appId]!, size: 34),
                    ),
                    title: Text(
                      _apps[tile.appId]?.label ?? tile.appId,
                      style: text(size: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${tile.colSpan} × ${tile.rowSpan}',
                        style: text(size: 11, color: Paper.dim)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final size in const [(1, 1), (2, 1), (2, 2)])
                          TextButton(
                            onPressed: () {
                              final items = tab.tiles.cast<GridItem>();
                              if (!_grid.canResize(
                                  items, tile, size.$1, size.$2)) {
                                _toast('No room for ${size.$1} × ${size.$2} there.');
                                return;
                              }
                              tile.colSpan = size.$1;
                              tile.rowSpan = size.$2;
                              refresh(() {});
                              setState(() {});
                              unawaited(_save());
                            },
                            child: Text('${size.$1}×${size.$2}',
                                style: text(
                                  size: 12,
                                  weight: tile.colSpan == size.$1 &&
                                          tile.rowSpan == size.$2
                                      ? 600
                                      : 400,
                                )),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tile: the icon, its name, and a wobble while arranging.
class _TileBody extends StatefulWidget {
  const _TileBody({
    required this.app,
    required this.appId,
    required this.wobbling,
    required this.big,
  });

  final LaunchableApp? app;
  final String appId;
  final bool wobbling;
  final bool big;

  @override
  State<_TileBody> createState() => _TileBodyState();
}

class _TileBodyState extends State<_TileBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    if (widget.wobbling) _wobble.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_TileBody old) {
    super.didUpdateWidget(old);
    if (widget.wobbling && !_wobble.isAnimating) {
      _wobble.repeat(reverse: true);
    } else if (!widget.wobbling && _wobble.isAnimating) {
      _wobble.stop();
      _wobble.value = 0;
    }
  }

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;

    final tile = LayoutBuilder(
      builder: (context, constraints) {
        final icon = (constraints.biggest.shortestSide * 0.52).clamp(28.0, 72.0);
        return Container(
          decoration: BoxDecoration(
            color: Paper.surface,
            borderRadius: BorderRadius.circular(Metrics.tileRadius),
            border: Border.all(color: Paper.edge),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (app == null)
                Icon(Icons.help_outline_rounded, size: icon, color: Paper.dim)
              else
                AppIconImage(app: app, size: icon),
              const SizedBox(height: 6),
              Text(
                app?.label ?? widget.appId.split('/').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text(size: 10, color: Paper.dim),
              ),
            ],
          ),
        );
      },
    );

    if (!widget.wobbling) return tile;

    return AnimatedBuilder(
      animation: _wobble,
      builder: (context, child) => Transform.rotate(
        // Small: enough to say "these can be moved", not so much that the
        // labels become hard to read while you are deciding where to put them.
        angle: (_wobble.value - 0.5) * 0.024,
        child: child,
      ),
      child: tile,
    );
  }
}
