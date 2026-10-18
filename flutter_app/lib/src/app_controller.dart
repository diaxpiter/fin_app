// UI state (selected cycle, filter, tab) on top of the Store, plus the
// derived model every screen reads. Not persisted.

import 'package:flutter/material.dart';

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
  int tab = 0;

  String get today => todayISO(_clock());

  Model get model {
    final state = store.state;
    final t = today;
    final cycles = computeCycles(state, t);
    if (_cycle == null || !cycles.any((c) => c.id == _cycle)) {
      // today's cycle, unless it is empty: then the next cycle that has movements
      final todayId = cycleIdOf(t, state.config.cycleStartDay);
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
  }) {
    _cycle = cycleIdOf(date, store.state.config.cycleStartDay);
    tab = 0;
    store.addMovement(date: date, description: description, category: category, cents: cents, estado: estado);
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
