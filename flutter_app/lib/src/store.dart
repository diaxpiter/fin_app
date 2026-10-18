// Persistence: one JSON document in shared_preferences (localStorage on web,
// NSUserDefaults on iOS, SharedPreferences on Android, a file on desktop).
// Data never leaves the device. Swap this class to change the backend.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'seed.dart';

class Store extends ChangeNotifier {
  Store._(this._prefs, this._state);

  static const _key = 'fin_app_v1';
  final SharedPreferences? _prefs;
  AppState _state;
  AppState get state => _state;

  static Future<Store> open() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {/* storage unavailable: run in memory */}
    final raw = prefs?.getString(_key);
    if (raw != null) {
      try {
        return Store._(prefs, AppState.fromJson(jsonDecode(raw)));
      } catch (_) {/* fall through to seed */}
    }
    return Store._(prefs, seedState()).._save();
  }

  /// In-memory store for tests.
  factory Store.memory([AppState? state]) => Store._(null, state ?? seedState());

  void _save() => _prefs?.setString(_key, jsonEncode(_state.toJson()));

  void _commit() {
    _save();
    notifyListeners();
  }

  static final _rand = Random();

  String addMovement({
    required String date,
    required String description,
    required String category,
    required int cents,
    required String estado,
  }) {
    final id = 'm:${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${_rand.nextInt(1 << 20).toRadixString(36)}';
    _state.movements.add(Movement(
        id: id, date: date, description: description, category: category, cents: cents, estado: estado));
    _commit();
    return id;
  }

  void setEstado(String id, String estado) {
    for (final m in _state.movements) {
      if (m.id == id) {
        m.estado = estado;
        _commit();
        return;
      }
    }
  }

  void removeMovement(String id) {
    _state.movements = _state.movements.where((m) => m.id != id).toList();
    _commit();
  }

  String exportJSON() => const JsonEncoder.withIndent('  ').convert(_state.toJson());

  /// Throws [FormatException] when the text is not a valid backup.
  void importJSON(String text) {
    _state = AppState.fromJson(jsonDecode(text));
    _commit();
  }

  void resetToSeed() {
    _state = seedState();
    _commit();
  }

  void setStartDay(int day) {
    _state.config = Config(cycleStartDay: day, openingBalance: _state.config.openingBalance);
    _commit();
  }

  /// Swap in data loaded from the account (or a fresh state on sign-out).
  void replaceState(AppState state) {
    _state = state;
    _commit();
  }
}
