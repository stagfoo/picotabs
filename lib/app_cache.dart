/// A snapshot of the installed app list, kept on disk.
///
/// Asking the platform for every launchable activity is the slowest thing the
/// launcher does, and it is on the path to the first useful frame: until it
/// returns, the cards are empty and there is nothing to search. The snapshot
/// means a cold start draws the real deck immediately and the platform is asked
/// afterwards, with the answer only redrawing anything if it differs.
///
/// The snapshot is a cache, never the truth. It is refreshed whenever a package
/// changes, when the launcher is resumed, and on demand.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class AppSnapshot {
  const AppSnapshot({required this.apps, required this.capturedAt});

  final List<LaunchableApp> apps;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
        'schemaVersion': AppCache.schemaVersion,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'apps': [for (final app in apps) app.toJson()],
      };

  /// Null rather than an exception for anything unreadable — a cache that
  /// cannot be parsed is a cache miss, not a failure worth surfacing.
  static AppSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['schemaVersion'];
    if (version is! int || version > AppCache.schemaVersion) return null;
    final rawApps = json['apps'];
    if (rawApps is! List) return null;
    try {
      for (final entry in rawApps) {
        // An entry needs something to launch: a package for an app or a pinned
        // shortcut, an intent for a legacy one. Neither means the snapshot is
        // corrupt, and refetching from the platform is always safe.
        if (entry is! Map) return null;
        final hasPackage = (entry['packageName'] as String?)?.isNotEmpty ?? false;
        final hasIntent = (entry['intentUri'] as String?)?.isNotEmpty ?? false;
        if (!hasPackage && !hasIntent) return null;
      }
      return AppSnapshot(
        apps: [
          for (final entry in rawApps)
            if (entry is Map) LaunchableApp.fromJson(entry.cast<String, dynamic>()),
        ],
        capturedAt:
            DateTime.tryParse('${json['capturedAt']}')?.toLocal() ?? DateTime.now(),
      );
    } on TypeError {
      return null;
    }
  }
}

class AppCache {
  static const schemaVersion = 1;
  static const _key = 'picotabs.apps.v1';

  Future<AppSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return AppSnapshot.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(List<LaunchableApp> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(
        AppSnapshot(apps: apps, capturedAt: DateTime.now()).toJson(),
      ),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Whether a freshly fetched list differs from what is already on screen.
///
/// A refresh that found nothing new must not call setState: the launcher
/// refreshes on every resume, and rebuilding the whole deck each time you come
/// home would undo the point of caching it.
bool appListsDiffer(List<LaunchableApp> a, List<LaunchableApp> b) {
  if (identical(a, b)) return false;
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    // Label included: renaming an app, or a locale change, has to redraw even
    // though the set of packages is unchanged.
    if (a[i].id != b[i].id || a[i].label != b[i].label) return true;
  }
  return false;
}
