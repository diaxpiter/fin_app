// Persistence: one JSON document in shared_preferences (localStorage on web,
// NSUserDefaults on iOS, SharedPreferences on Android, a file on desktop).
// With an account, AccountController also syncs it, encrypted (account.dart).

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import 'import_csv.dart';
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
      } catch (_) {
        // Keep the copy we can't read (a newer app version may): the save below would destroy it.
        prefs?.setString(_unreadableKey, raw);
      }
    }
    // a new user starts with an empty plan, not with the example data
    return Store._(prefs, emptyState()).._save();
  }

  static const _unreadableKey = 'fin_app_v1.unreadable';

  /// Saved data this version could not read, kept so it can be exported; null when there is none.
  String? get unreadableCopy => _prefs?.getString(_unreadableKey);

  /// In-memory store for tests.
  factory Store.memory([AppState? state]) => Store._(null, state ?? seedState());

  bool _persist = true;

  /// False on a shared device: the data then lives only in memory and in the encrypted vault.
  set persist(bool v) {
    _persist = v;
    _save();
  }

  void _save() => _persist ? _prefs?.setString(_key, jsonEncode(_state.toJson())) : _prefs?.remove(_key);

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
    String? account,
    String? toAccount,
  }) {
    final id = 'm:${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${_rand.nextInt(1 << 20).toRadixString(36)}';
    _state.movements.add(Movement(
        id: id,
        date: date,
        description: description,
        category: category,
        cents: cents,
        estado: estado,
        account: account,
        toAccount: toAccount));
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

  /// Sets "how much is in the account today" (default: the first account); the opening balance is derived from it.
  void setBalanceToday(int cents, {String? account}) {
    final id = account ?? _state.defaultAccount;
    final i = _state.accounts.indexWhere((a) => a.id == id);
    if (i < 0) return;
    _state.accounts[i] = _state.accounts[i].copyWith(openingBalance: openingBalanceFor(_state, id, cents));
    _commit();
  }

  /// Sets (or, with null, removes) a category's spending limit per cycle.
  void setBudget(String category, int? cents) {
    final i = _state.categories.indexWhere((c) => c.name == category);
    if (i < 0) return;
    _state.categories[i] = _state.categories[i].withBudget(cents);
    _commit();
  }

  // ---- categories ----

  static const maxCategoryName = 24;

  /// Adds a category of [type] ('Entrada' | 'Saída'); false when the name is empty, too long or taken.
  bool addCategory(String name, String type, String color) {
    final n = name.trim();
    if (n.isEmpty || n.length > maxCategoryName || (type != 'Entrada' && type != 'Saída')) return false;
    if (_state.categories.any((c) => c.name.toLowerCase() == n.toLowerCase())) return false;
    _state.categories.insert(
        _state.categories.lastIndexWhere((c) => c.type == type) + 1, Category(name: n, type: type, color: color));
    _commit();
    return true;
  }

  /// Who takes over a deleted category's movements: "Outros" for expenses, else the first other of its type.
  /// Null when it can't be deleted (the transfer category, or the last one of its type).
  String? categoryHeir(String name) {
    final c = _state.categories.where((x) => x.name == name).firstOrNull;
    if (c == null || c.type == transferType) return null;
    final same = _state.categories.where((x) => x.type == c.type && x.name != name);
    return same.where((x) => x.name == 'Outros').firstOrNull?.name ?? same.firstOrNull?.name;
  }

  int categoryUses(String name) =>
      _state.movements.where((m) => m.category == name).length + _state.recurring.where((r) => r.category == name).length;

  /// Deletes a category; what used it moves to [categoryHeir]. False when it can't be deleted.
  bool removeCategory(String name) {
    final heir = categoryHeir(name);
    if (heir == null) return false;
    _state = AppState(
        config: _state.config,
        categories: _state.categories.where((c) => c.name != name).toList(),
        recurring: [for (final r in _state.recurring) r.category == name ? r.withCategory(heir) : r],
        movements: [for (final m in _state.movements) m.category == name ? m.withCategory(heir) : m],
        accounts: _state.accounts,
        goals: _state.goals);
    _commit();
    return true;
  }

  // ---- goals ----

  static String newGoalId() =>
      'g${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 16).toRadixString(36)}';

  /// Saves a goal (new when [id] is null). A new goal without [account] gets its own savings account
  /// holding [alreadySaved]. A per-cycle amount keeps a fixed transfer into it, on payday, in step.
  void saveGoal({
    String? id,
    required String name,
    required int target,
    required int perCycle,
    String? account,
    int alreadySaved = 0,
    String? today,
  }) {
    final existing = _state.goals.where((g) => g.id == id).firstOrNull;
    var acc = existing?.account ?? account;
    if (acc == null) {
      acc = newAccountId();
      _state.accounts.add(Account(id: acc, name: name, kind: AccountKind.savings, openingBalance: alreadySaved));
    }
    final goal = Goal(id: existing?.id ?? newGoalId(), name: name, account: acc, target: target, perCycle: perCycle);
    final i = _state.goals.indexWhere((g) => g.id == goal.id);
    if (i >= 0) {
      _state.goals[i] = goal;
    } else {
      _state.goals.add(goal);
    }
    _syncGoalBill(goal, today);
  }

  /// Deletes a goal and its automatic transfer's future payments. The savings account stays.
  void removeGoal(String id, {String? today}) {
    final g = _state.goals.where((x) => x.id == id).firstOrNull;
    if (g == null) return;
    _state.goals.removeWhere((x) => x.id == id);
    _syncGoalBill(g.copyWith(perCycle: 0), today);
  }

  void _syncGoalBill(Goal g, String? today) {
    if (g.perCycle > 0) {
      saveRecurring(_goalBill(g), today);
    } else if (_state.recurring.any((r) => r.id == g.billId)) {
      removeRecurring(g.billId, today);
    } else {
      _commit();
    }
  }

  /// The transfer from the everyday account into the goal's account, on the salary's day.
  Recurring _goalBill(Goal g) {
    final types = typesOf(_state);
    final pay = ([..._state.recurring.where((r) => types[r.category] == 'Entrada')]..sort((a, b) => b.cents.compareTo(a.cents)))
        .firstOrNull;
    final from = _state.accounts.where((a) => !a.isSavings && a.id != g.account).toList();
    return Recurring(
      id: g.billId,
      description: g.name,
      category: transferType,
      cents: g.perCycle,
      day: pay?.day ?? _state.config.cycleStartDay,
      shift: pay?.shift ?? DayShift.none,
      account: (from.where((a) => a.kind == AccountKind.current).firstOrNull ?? from.firstOrNull)?.id,
      toAccount: g.account,
    );
  }

  /// Sets several budgets at once (one save).
  void setBudgets(Map<String, int> budgets) {
    for (final e in budgets.entries) {
      final i = _state.categories.indexWhere((c) => c.name == e.key);
      if (i >= 0) _state.categories[i] = _state.categories[i].withBudget(e.value);
    }
    _commit();
  }

  // ---- accounts ----

  static String newAccountId() =>
      'a${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 16).toRadixString(36)}';

  /// Adds or updates an account; [balanceToday], when given, sets its balance.
  void saveAccount(Account a, {int? balanceToday}) {
    final i = _state.accounts.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      _state.accounts[i] = a;
    } else {
      _state.accounts.add(a);
    }
    if (balanceToday != null) {
      final j = _state.accounts.indexWhere((x) => x.id == a.id);
      _state.accounts[j] = a.copyWith(openingBalance: openingBalanceFor(_state, a.id, balanceToday));
    }
    _commit();
  }

  /// Whether anything (movements or bills) uses the account.
  bool accountInUse(String id) {
    final isDefault = id == _state.defaultAccount;
    bool on(String? acc, String? to) => (acc ?? (isDefault ? id : null)) == id || to == id;
    return _state.movements.any((m) => on(m.account, m.toAccount)) || _state.recurring.any((r) => on(r.account, r.toAccount));
  }

  /// Deletes an unused account (never the last one). Returns false if it can't.
  bool removeAccount(String id) {
    if (_state.accounts.length <= 1 || accountInUse(id)) return false;
    _state.accounts.removeWhere((a) => a.id == id);
    _commit();
    return true;
  }

  void removeMovement(String id) {
    _state.movements = _state.movements.where((m) => m.id != id).toList();
    _commit();
  }

  /// Every movement as a spreadsheet-ready CSV (amounts: income +, expenses −). Text cells that a
  /// spreadsheet would run as a formula are prefixed with an apostrophe.
  String exportCSV() {
    final types = typesOf(_state);
    String cell(String v) =>
        '"${(RegExp(r'^[=+\-@\t\r]').hasMatch(v) ? "'$v" : v).replaceAll('"', '""')}"';
    String amount(int c) => '${c < 0 ? '-' : ''}${c.abs() ~/ 100}.${pad(c.abs() % 100)}';
    final b = StringBuffer('date,description,category,account,amount,status\n');
    for (final m in sortMovements(_state.movements, types)) {
      final value = isTransfer(m, types) ? m.cents : signed(m, types);
      b.writeln([
        m.date,
        cell(m.description),
        cell(m.category),
        cell(_state.accountById(m.account)?.name ?? ''),
        amount(value),
        m.estado,
      ].join(','));
    }
    return b.toString();
  }

  /// Remembers that the data was exported as a file today.
  void markBackedUp(String today) {
    _state.config = _state.config.copyWith(lastBackup: today);
    _commit();
  }

  /// Saves the ticked rows of a statement import: settles planned bills, adds the rest as paid
  /// movements on [account] (default: the first). Returns how many rows were applied.
  int importMovements(List<ImportItem> items, {String? account}) {
    var n = 0;
    for (final it in items.where((i) => i.include)) {
      if (it.action == ImportAction.markPaid) {
        final m = _state.movements.where((x) => x.id == it.plannedId).firstOrNull;
        if (m == null) continue;
        m.estado = 'Pago';
      } else if (it.action == ImportAction.add) {
        _state.movements.add(Movement(
            id: 'm:${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}',
            date: it.row.date,
            description: it.row.description.isEmpty ? it.category : it.row.description,
            category: it.category,
            cents: it.row.cents.abs(),
            estado: 'Pago',
            account: account));
      } else {
        continue;
      }
      n++;
    }
    if (n > 0) _commit();
    return n;
  }

  String exportJSON() => const JsonEncoder.withIndent('  ').convert(_state.toJson());

  /// Throws [FormatException] when the text is not a valid backup.
  void importJSON(String text) {
    final next = AppState.fromJson(jsonDecode(text));
    computeCycles(next); // throws if the data can't be laid out; then nothing is replaced
    _state = next;
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
    // holidays also move the cycle boundaries when the cycle start shifts, which affects every bill
    final shifting = _state.recurring
        .where((r) => r.shift != DayShift.none || _state.config.cycleShift != DayShift.none)
        .map((r) => r.id)
        .toSet();
    _state.movements = syncRecurring(_state, todayISO(), regenerate: shifting) ?? _state.movements;
    _commit();
  }

  void setStartDay(int day) => _setCycle(_state.config.copyWith(cycleStartDay: day));

  void setCycleShift(DayShift shift) => _setCycle(_state.config.copyWith(cycleShift: shift));

  void _setCycle(Config config) {
    _state.config = config;
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
    _state = AppState(
        config: _state.config,
        categories: _state.categories,
        recurring: list,
        movements: _state.movements,
        accounts: _state.accounts,
        goals: _state.goals);
    _state.movements = syncRecurring(_state, today ?? todayISO(), regenerate: {changedId}) ?? _state.movements;
    _commit();
  }

  /// Swap in data loaded from the account (or a fresh state on sign-out).
  void replaceState(AppState state) {
    _state = state;
    _commit();
  }
}
