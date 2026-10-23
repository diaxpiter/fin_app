// UI state (selected cycle, filter, tab) on top of the Store, plus the
// derived model every screen reads. Not persisted.

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'logic.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';

class Model {
  Model({required this.state, required this.today, required this.cycles, required this.cycle})
      : _colors = {for (final c in state.categories) c.name: hexColor(c.color)},
        _types = typesOf(state);

  final AppState state;
  final String today;
  final List<Cycle> cycles;
  final Cycle cycle;
  final Map<String, Color> _colors;
  final Map<String, String> _types;

  bool isIncome(String category) => _types[category] == 'Entrada';
  bool isTransferCategory(String category) => _types[category] == transferType;
  bool get multiAccount => state.accounts.length > 1;
  Color colorOf(String category) => _colors[category] ?? Palette.fallbackDot;
}

class AppController extends ChangeNotifier {
  AppController(this.store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    store.addListener(notifyListeners);
  }

  final Store store;
  final DateTime Function() _clock;
  String? _cycle;
  String filter = 'Todos';

  /// Movimentos shows only this account (null = all).
  String? accountFilter;

  void setAccountFilter(String? id) {
    accountFilter = id;
    notifyListeners();
  }
  int tab = 0;

  /// Movimentos lists matches from every cycle when this is not empty.
  String search = '';

  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  /// Plano shows the forecast (0) or the fixed bills (1).
  int planView = 0;

  void setPlanView(int v) {
    planView = v;
    notifyListeners();
  }

  String get today => todayISO(_clock());

  /// Device language, used until the user picks one. Tests can override it.
  String deviceLanguage = WidgetsBinding.instance.platformDispatcher.locale.languageCode;

  String get lang => resolveLanguage(store.state.config.language, deviceLanguage);
  S get s => S(lang);

  Money? _money;
  Money get money {
    final cur = store.state.config.currency;
    if (_money == null || _money!.language != lang || _money!.currency != cur) _money = Money(lang, cur);
    return _money!;
  }

  Model get model {
    final state = store.state;
    final t = today;
    final cycles = computeCycles(state, t);
    if (_cycle == null || !cycles.any((c) => c.id == _cycle)) {
      // today's cycle, unless it is empty: then the next cycle that has movements
      final todayId = cycleIdOf(t, state.config.cycle);
      final cur = cycles.where((c) => c.id == todayId).firstOrNull;
      final withItems = cycles.where((c) => c.id.compareTo(todayId) >= 0 && c.items.isNotEmpty).firstOrNull;
      _cycle = (cur != null && cur.items.isNotEmpty) || withItems == null ? todayId : withItems.id;
    }
    return Model(state: state, today: t, cycles: cycles, cycle: cycles.firstWhere((c) => c.id == _cycle));
  }

  void pickCycle(String id) {
    _cycle = id;
    notifyListeners();
  }

  void resetCycle() {
    _cycle = null;
    notifyListeners();
  }

  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void addMovement({
    required String date,
    required String description,
    required String category,
    required int cents,
    required String estado,
    String? account,
    String? toAccount,
  }) {
    _cycle = cycleIdOf(date, store.state.config.cycle);
    tab = 0;
    store.addMovement(
        date: date,
        description: description,
        category: category,
        cents: cents,
        estado: estado,
        account: account,
        toAccount: toAccount);
  }

  @override
  void dispose() {
    store.removeListener(notifyListeners);
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  /// [listen] false for use inside callbacks (no rebuild dependency).
  static AppController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }
}
