import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// Picks apps to put on a card.
///
/// A full screen rather than a bottom sheet. On a screen this short the sheet
/// had to fight the keyboard for room, and the trick it used — folding the
/// title away once the keyboard was up — changed the number of children in the
/// column, which shifted the search field's position in it. Flutter matches
/// unkeyed children by position, so the field's element was rebuilt against the
/// title's, losing focus and closing the keyboard the moment it opened. A full
/// screen has the room, so nothing has to move.
///
/// Multi-select, because adding a place's worth of apps one at a time is the
/// tedious way to build a map.
Future<List<String>?> showAppPicker(
  BuildContext context, {
  required String placeName,
  required Color accent,
  required List<LaunchableApp> installed,
  Set<String> alreadyHere = const {},
  Map<String, List<String>> alsoIn = const {},
}) {
  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (context) => AppPickerScreen(
        placeName: placeName,
        accent: accent,
        installed: installed,
        alreadyHere: alreadyHere,
        alsoIn: alsoIn,
      ),
    ),
  );
}

class AppPickerScreen extends StatefulWidget {
  const AppPickerScreen({
    super.key,
    required this.placeName,
    required this.accent,
    required this.installed,
    this.alreadyHere = const {},
    this.alsoIn = const {},
  });

  final String placeName;
  final Color accent;
  final List<LaunchableApp> installed;

  /// Apps already on this node, shown as unavailable rather than hidden — a
  /// silently missing app reads as a broken search.
  final Set<String> alreadyHere;

  /// The other places an app already sits, by app id.
  ///
  /// Shown, not used to exclude: the same app belonging to several situations
  /// is the point of the map, so this is context for the choice rather than a
  /// warning against it.
  final Map<String, List<String>> alsoIn;

  @override
  State<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends State<AppPickerScreen> {
  final _chosen = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.installed]..sort(compareByLabel);
    final matches = searchApps(sorted, _query);
    final color = widget.accent;
    final onCard = onPaperFor(color);

    return Scaffold(
      backgroundColor: Paper.ground,
      // The Scaffold moves the body clear of the keyboard, so there is no
      // inset arithmetic here and nothing is added to or removed from the tree
      // when the keyboard opens.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 22,
                        color: Paper.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Add to ${widget.placeName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text(size: 16, weight: 600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _chosen.isEmpty
                        ? null
                        : () => Navigator.pop(context, _chosen.toList()),
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: onCard,
                      disabledBackgroundColor: Paper.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 40),
                    ),
                    child: Text(
                      _chosen.isEmpty ? 'Add' : 'Add ${_chosen.length}',
                      style: text(
                        size: 13,
                        weight: 600,
                        color: _chosen.isEmpty
                            ? Paper.dim
                            : onCard,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                autofocus: true,
                style: text(size: 14),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Paper.surface,
                  hintText: 'Search ${widget.installed.length} apps',
                  hintStyle: text(size: 13, color: Paper.dim),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 18,
                    color: Paper.dim,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nothing matches',
                        style: TextStyle(color: Paper.dim),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: matches.length,
                      itemBuilder: (context, index) =>
                          _row(matches[index], color),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(LaunchableApp app, Color color) {
    final chosen = _chosen.contains(app.id);
    final alreadyHere = widget.alreadyHere.contains(app.id);

    return ListTile(
      dense: true,
      enabled: !alreadyHere,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: chosen ? color : Paper.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: chosen ? color : Paper.edge),
        ),
        child: chosen
            ? Icon(Icons.check, size: 17, color: onPaperFor(color))
            : null,
      ),
      title: Text(
        app.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: alreadyHere ? Paper.dim : Paper.ink,
          fontSize: 14,
        ),
      ),
      subtitle: alreadyHere
          ? const Text(
              'already here',
              style: TextStyle(color: Paper.dim, fontSize: 11),
            )
          : (widget.alsoIn[app.id]?.isNotEmpty ?? false)
              ? Text(
                  'also in ${widget.alsoIn[app.id]!.join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Paper.dim, fontSize: 11),
                )
              : null,
      onTap: alreadyHere
          ? null
          : () => setState(() {
              if (!_chosen.remove(app.id)) _chosen.add(app.id);
            }),
    );
  }
}
