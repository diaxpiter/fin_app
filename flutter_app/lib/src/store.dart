// Persistence: one JSON document in shared_preferences (localStorage on web,
// NSUserDefaults on iOS, SharedPreferences on Android, a file on desktop).
// With an account, AccountController also syncs it, encrypted (account.dart).

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'logic.dart';
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

  /// Replaces a movement with an edited copy (same id).
  void updateMovement(Movement m) {
    final i = _state.movements.indexWhere((x) => x.id == m.id);
    if (i < 0) return;
    _state.movements[i] = m;
    _commit();
  }

  /// Settles a planned movement with what was actually paid.
  void payPlanned(String id, {required int cents, required String date}) {
    final m = _state.movements.where((x) => x.id == id).firstOrNull;
    if (m != null) updateMovement(m.copyWith(cents: cents, date: date, estado: 'Pago'));
  }

  /// Sets "how much is in the account today"; the opening balance is derived from it.
  void setBalanceToday(int cents) {
    _state.config = _state.config.copyWith(openingBalance: openingBalanceFor(_state, cents));
    _commit();
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

  /// null = follow the device language.
  void setLanguage(String? lang) {
    _state.config = _state.config.copyWith(language: lang, clearLanguage: lang == null);
    _commit();
  }

  void setCurrency(String code) {
    _state.config = _state.config.copyWith(currency: code);
    _commit();
  }

  /// Whose holidays count for bills that move off non-business days; replans those bills.
  void setHolidays(String country) {
    _state.config = _state.config.copyWith(holidays: country);
    final shifting = _state.recurring.where((r) => r.shift != DayShift.none).map((r) => r.id).toSet();
    _state.movements = syncRecurring(_state, todayISO(), regenerate: shifting) ?? _state.movements;
    _commit();
  }

  void setStartDay(int day) {
    _state.config = _state.config.copyWith(cycleStartDay: day);
    // planned bills move to the new cycles
    _state.movements = syncRecurring(_state, todayISO(), regenerate: _state.recurring.map((r) => r.id).toSet()) ??
        _state.movements;
    _commit();
  }

  // ---- fixed bills ----

  /// Adds any planned bill occurrences that are missing (e.g. a new month came
  /// into the forecast window). Saves only when something changed.
  void ensureRecurring([String? today]) {
    final next = syncRecurring(_state, today ?? todayISO());
    if (next == null) return;
    _state.movements = next;
    _commit();
  }

  static String newRecurringId() =>
      'r${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 16).toRadixString(36)}';

  /// Adds or replaces (same id) a fixed bill and updates its planned movements.
  void saveRecurring(Recurring r, [String? today]) {
    final i = _state.recurring.indexWhere((x) => x.id == r.id);
    final list = [..._state.recurring];
    if (i >= 0) {
      list[i] = r;
    } else {
      list.add(r);
    }
    _setRecurring(list, r.id, today);
  }

  /// Deletes a fixed bill and its future planned movements (past and paid ones stay).
  void removeRecurring(String id, [String? today]) =>
      _setRecurring(_state.recurring.where((r) => r.id != id).toList(), id, today);

  void _setRecurring(List<Recurring> list, String changedId, String? today) {
    _state = AppState(config: _state.config, categories: _state.categories, recurring: list, movements: _state.movements);
    _state.movements = syncRecurring(_state, today ?? todayISO(), regenerate: {changedId}) ?? _state.movements;
    _commit();
  }

  /// Swap in data loaded from the account (or a fresh state on sign-out).
  void replaceState(AppState state) {
    _state = state;
    _commit();
  }
}
