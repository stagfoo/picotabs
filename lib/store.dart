/// Keeps the board between launches.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'board.dart';

class BoardStore {
  static const _key = 'picotabs.board.v1';

  Future<Board> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return Board.seed();
    try {
      return Board.fromJson(jsonDecode(raw));
    } on FormatException {
      // A board that will not parse is a board you no longer have, and there
      // is no way to repair one from inside a launcher that cannot draw.
      return Board.seed();
    }
  }

  Future<void> save(Board board) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(board.toJson()));
  }
}
