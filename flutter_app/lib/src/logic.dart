// Pure finance logic: cycles, recurring-bill expansion, totals.
// Tested in test/logic_test.dart.
// Money is handled in integer cents to avoid floating-point drift.

import 'holidays.dart';
import 'models.dart';

String pad(int n) => n.toString().padLeft(2, '0');
String iso(int y, int m, int d) => '$y-${pad(m)}-${pad(d)}';

typedef YM = ({int y, int m});
typedef YMD = ({int y, int m, int d});

YMD parseISO(String s) {
  final p = s.split('-').map(int.parse).toList();
  return (y: p[0], m: p[1], d: p[2]);
}

YM _ym(String id) {
  final p = id.split('-').map(int.parse).toList();
  return (y: p[0], m: p[1]);
}

YM addMonths(int y, int m, int n) {
  final t = y * 12 + (m - 1) + n;
  return (y: (t / 12).floor(), m: t % 12 + 1);
}

int daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

String todayISO([DateTime? now]) {
  final n = now ?? DateTime.now();
  return iso(n.year, n.month, n.day);
}

// ---- Cycles -----------------------------------------------------------
// A cycle starts on `startDay` and ends the day before the next start.
// Its id is "YYYY-MM" of the month in which it ENDS (23 Oct–22 Nov = "2026-11").
// With startDay = 1 it is simply the calendar month.

String cycleIdOf(String dateISO, int startDay) {
  final p = parseISO(dateISO);
  final YM start = p.d >= startDay ? (y: p.y, m: p.m) : addMonths(p.y, p.m, -1);
  final end = startDay == 1 ? start : addMonths(start.y, start.m, 1);
  return '${end.y}-${pad(end.m)}';
}

({String start, String end}) cycleBounds(String id, int startDay) {
  final e = _ym(id);
  final s = startDay == 1 ? e : addMonths(e.y, e.m, -1);
  final next = addMonths(s.y, s.m, 1);
  final endDate = DateTime.utc(next.y, next.m, startDay - 1);
  return (start: iso(s.y, s.m, startDay), end: iso(endDate.year, endDate.month, endDate.day));
}

String nextCycleId(String id, [int n = 1]) {
  final e = _ym(id);
  final r = addMonths(e.y, e.m, n);
  return '${r.y}-${pad(r.m)}';
}

List<String> cycleRange(String fromId, String toId) {
  final out = <String>[];
  var id = fromId;
  while (id.compareTo(toId) <= 0 && out.length < 240) {
    out.add(id);
    id = nextCycleId(id);
  }
  return out;
}

const _months = {
  'pt': ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'],
  'en': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
};
const _weekdays = {
  'pt': ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'],
  'en': ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
};

String monthShort(int m, [String lang = 'pt']) => (_months[lang] ?? _months['en']!)[m - 1];

String cycleLabel(String id, [String lang = 'pt']) {
  final e = _ym(id);
  final s = monthShort(e.m, lang);
  return '${s[0].toUpperCase()}${s.substring(1)} ${e.y}';
}

String formatDay(String dateISO, [String lang = 'pt']) {
  final p = parseISO(dateISO);
  return '${p.d} ${monthShort(p.m, lang)}';
}

String weekday(String dateISO, [String lang = 'pt']) {
  final p = parseISO(dateISO);
  return (_weekdays[lang] ?? _weekdays['en']!)[DateTime.utc(p.y, p.m, p.d).weekday % 7];
}

// ---- Money ------------------------------------------------------------

final _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

String fmtCents(int c, {bool sign = false}) {
  final abs = c.abs();
  final grouped = (abs ~/ 100).toString().replaceAllMapped(_thousands, (_) => '.');
  final s = '$grouped,${pad(abs % 100)}';
  if (c < 0) return '−$s';
  return sign && c > 0 ? '+$s' : s;
}

int? parseMoney(String str) {
  final n = double.tryParse(str.replaceAll('.', '').replaceFirst(',', '.'));
  return n == null || !n.isFinite ? null : (n * 100).round();
}

// ---- Recurring bills -> movements ------------------------------------

String occurrenceDate(int day, String cycleId, int startDay) {
  final e = _ym(cycleId);
  final s = startDay == 1 ? e : addMonths(e.y, e.m, -1);
  final t = startDay == 1 || day >= startDay ? s : addMonths(s.y, s.m, 1);
  final d = day < daysInMonth(t.y, t.m) ? day : daysInMonth(t.y, t.m);
  return iso(t.y, t.m, d);
}

// `overrides` maps "recId:cycleId" -> cents. Bills with a [DayShift] move off
// weekends and [holidays] ('PT', or 'none' for weekends only).
List<Movement> expandRecurring(List<Recurring> recurring, List<String> cycleIds, int startDay,
    [Map<String, int> overrides = const {}, String holidays = 'PT']) {
  final out = <Movement>[];
  for (final cycleId in cycleIds) {
    for (final r in recurring) {
      if (r.from != null && cycleId.compareTo(r.from!) < 0) continue;
      if (r.to != null && cycleId.compareTo(r.to!) > 0) continue;
      final key = '${r.id}:$cycleId';
      final date = shiftToBusinessDay(occurrenceDate(r.day, cycleId, startDay), r.shift, holidays);
      out.add(Movement(
        id: 'gen:$key',
        date: date,
        // moved across the cycle boundary (e.g. paid early): still counts in its own cycle
        cycle: cycleIdOf(date, startDay) == cycleId ? null : cycleId,
        description: r.description,
        category: r.category,
        cents: overrides[key] ?? r.cents,
        estado: 'Previsto',
        gen: true,
        account: r.account,
        toAccount: r.toAccount,
      ));
    }
  }
  return out;
}

// Fixed bills are materialised as planned movements this many cycles ahead
// (the current one included), so they show up in Movimentos and Previsão.
const recurringHorizon = 12;

String? _genCycle(Movement m) => m.gen ? m.id.substring(m.id.lastIndexOf(':') + 1) : null;
String? _genRecurringId(Movement m) => m.gen ? m.id.split(':')[1] : null;

/// Brings the planned movements in line with the fixed bills, from today's
/// cycle up to [recurringHorizon] cycles ahead. Returns null when nothing changed.
///
/// - Missing occurrences are added; existing ones are left alone (so a value
///   the user changed, or a movement marked Pago, is never overwritten).
/// - Bills in [regenerate] first lose their future occurrences that are still
///   Previsto (use it after editing or deleting a bill, or changing the start day).
/// - A cycle that already has a movement with the same description and
///   category (e.g. typed in by hand) doesn't get a duplicate.
List<Movement>? syncRecurring(AppState state, String today, {Set<String> regenerate = const {}}) {
  final s = state.config.cycleStartDay;
  final cur = cycleIdOf(today, s);
  var changed = false;

  final movements = state.movements.where((m) {
    final rid = _genRecurringId(m);
    final drop = rid != null &&
        regenerate.contains(rid) &&
        m.estado == 'Previsto' &&
        !m.edited &&
        _genCycle(m)!.compareTo(cur) >= 0;
    if (drop) changed = true;
    return !drop;
  }).toList();

  final ids = movements.map((m) => m.id).toSet();
  String key(Movement m) => '${cycleOfMovement(m, s)}|${m.description}|${m.category}';
  final seen = movements.map(key).toSet();
  final added = expandRecurring(state.recurring, cycleRange(cur, nextCycleId(cur, recurringHorizon - 1)), s, const {},
          state.config.holidays)
      .where((m) => !ids.contains(m.id) && !seen.contains(key(m)));
  for (final m in added) {
    movements.add(m);
    changed = true;
  }
  return changed ? movements : null;
}

// ---- Matching a payment to a planned bill ------------------------------

String _norm(String s) => s.trim().toLowerCase();

/// Planned (Previsto) movements in the same cycle and category that a new
/// payment probably settles, best match first. A description that matches
/// (or contains / is contained in) the planned one counts; an empty
/// description, or one equal to the category name, matches any of them.
List<Movement> matchPlanned(AppState state,
    {required String date, required String description, required String category}) {
  final s = state.config.cycleStartDay;
  final cycle = cycleIdOf(date, s);
  final d = _norm(description);
  final anyInCategory = d.isEmpty || d == _norm(category);
  final hits = state.movements.where((m) {
    if (m.estado != 'Previsto' || m.category != category || cycleOfMovement(m, s) != cycle) return false;
    final p = _norm(m.description);
    return anyInCategory || p == d || p.contains(d) || d.contains(p);
  }).toList()
    ..sort((a, b) {
      final exact = (_norm(b.description) == d ? 1 : 0) - (_norm(a.description) == d ? 1 : 0);
      return exact != 0 ? exact : a.date.compareTo(b.date);
    });
  return hits;
}

// ---- Totals -----------------------------------------------------------

/// The cycle a movement counts in: its own date's, unless it was moved across a boundary.
String cycleOfMovement(Movement m, int startDay) => m.cycle ?? cycleIdOf(m.date, startDay);

Map<String, String> typesOf(AppState s) => {for (final c in s.categories) c.name: c.type};
bool _isIncome(Movement m, Map<String, String> types) => types[m.category] == 'Entrada';
bool isTransfer(Movement m, Map<String, String> types) => types[m.category] == transferType && m.toAccount != null;

/// Effect on the total: transfers between own accounts don't change it.
int signed(Movement m, Map<String, String> types) =>
    isTransfer(m, types) ? 0 : (_isIncome(m, types) ? m.cents : -m.cents);

/// Effect on each account the movement touches.
Map<String, int> accountDeltas(Movement m, Map<String, String> types, String defaultAccount) {
  final from = m.account ?? defaultAccount;
  if (isTransfer(m, types)) {
    if (m.toAccount == from) return const {};
    return {from: -m.cents, m.toAccount!: m.cents};
  }
  return {from: _isIncome(m, types) ? m.cents : -m.cents};
}

List<Movement> sortMovements(Iterable<Movement> list, Map<String, String> types) {
  // by date; within a day income first so running balances never dip artificially
  final out = [...list];
  out.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    final byType = (_isIncome(b, types) ? 1 : 0) - (_isIncome(a, types) ? 1 : 0);
    if (byType != 0) return byType;
    return a.description.toLowerCase().compareTo(b.description.toLowerCase());
  });
  return out;
}

class Cycle {
  const Cycle({
    required this.id, required this.label, required this.start, required this.end,
    required this.items, required this.receitas, required this.despesas, required this.sobra,
    required this.pago, required this.porPagar, required this.startBalance, required this.endBalance,
    required this.lowest, required this.lowestDate, required this.savingsRate,
    this.saved = 0, this.accountEnd = const {}, this.accountLowest = const {}, this.accountLowestDate = const {},
  });
  final String id, label, start, end;
  final List<Movement> items;
  final int receitas, despesas, sobra, pago, porPagar, startBalance, endBalance, lowest, savingsRate;
  final String? lowestDate;

  /// Net amount moved into savings / investment accounts this cycle.
  final int saved;

  /// Per account: balance at the end of the cycle, and the lowest end-of-day balance in it (with its date).
  final Map<String, int> accountEnd, accountLowest;
  final Map<String, String> accountLowestDate;
}

List<Cycle> computeCycles(AppState state, [String? today]) {
  final s = state.config.cycleStartDay;
  final types = typesOf(state);

  final ids = {cycleIdOf(today ?? todayISO(), s), for (final m in state.movements) cycleOfMovement(m, s)};
  final sorted = ids.toList()..sort();
  final all = cycleRange(sorted.first, sorted.last);

  final byCycle = {for (final id in all) id: <Movement>[]};
  for (final m in state.movements) {
    byCycle[cycleOfMovement(m, s)]!.add(m);
  }

  var balance = state.config.openingBalance + state.accounts.fold<int>(0, (a, x) => a + x.openingBalance);
  final accBal = {for (final a in state.accounts) a.id: a.openingBalance};
  final savingsAcc = {for (final a in state.accounts) if (a.isSavings) a.id};
  final defaultAcc = state.defaultAccount;
  return all.map((id) {
    final items = sortMovements(byCycle[id]!, types);
    var receitas = 0, despesas = 0, pago = 0, porPagar = 0;
    var saved = 0;
    for (final m in items) {
      if (isTransfer(m, types)) {
        if (savingsAcc.contains(m.toAccount)) saved += m.cents;
        if (savingsAcc.contains(m.account ?? defaultAcc)) saved -= m.cents;
      } else if (_isIncome(m, types)) {
        receitas += m.cents;
      } else {
        despesas += m.cents;
        if (m.estado == 'Pago') {
          pago += m.cents;
        } else {
          porPagar += m.cents;
        }
      }
    }
    final startBalance = balance;
    // lowest END-OF-DAY balance inside the cycle, in total and per account
    var run = startBalance, lowest = startBalance;
    String? lowestDate;
    final accLowest = {...accBal};
    final accLowestDate = <String, String>{};
    final touched = <String>{};
    for (var i = 0; i < items.length; i++) {
      run += signed(items[i], types);
      accountDeltas(items[i], types, defaultAcc).forEach((acc, d) {
        accBal[acc] = (accBal[acc] ?? 0) + d;
        touched.add(acc);
      });
      final last = i == items.length - 1 || items[i + 1].date != items[i].date;
      if (last && (lowestDate == null || run < lowest)) {
        lowest = run;
        lowestDate = items[i].date;
      }
      if (last) {
        for (final acc in touched) {
          if (!accLowestDate.containsKey(acc) || accBal[acc]! < accLowest[acc]!) {
            accLowest[acc] = accBal[acc]!;
            accLowestDate[acc] = items[i].date;
          }
        }
        touched.clear();
      }
    }
    final sobra = receitas - despesas;
    balance += sobra;
    final b = cycleBounds(id, s);
    return Cycle(
      id: id, label: cycleLabel(id), start: b.start, end: b.end, items: items,
      receitas: receitas, despesas: despesas, sobra: sobra, pago: pago, porPagar: porPagar,
      startBalance: startBalance, endBalance: balance,
      lowest: lowestDate == null ? startBalance : lowest, lowestDate: lowestDate,
      savingsRate: receitas > 0 ? (sobra / receitas * 100).round() : 0,
      saved: saved, accountEnd: {...accBal}, accountLowest: accLowest, accountLowestDate: accLowestDate,
    );
  }).toList();
}

/// Money actually in [account] now: its opening balance + every movement on it marked Pago.
int accountCash(AppState state, String account) {
  final types = typesOf(state);
  var total = state.accountById(account)?.openingBalance ?? 0;
  for (final m in state.movements) {
    if (m.estado == 'Pago') total += accountDeltas(m, types, state.defaultAccount)[account] ?? 0;
  }
  return total;
}

/// The opening balance that makes [account] hold [balanceToday].
int openingBalanceFor(AppState state, String account, int balanceToday) =>
    balanceToday - (accountCash(state, account) - (state.accountById(account)?.openingBalance ?? 0));

/// Money actually in [accounts] (default: everyday money: current + spending accounts).
int cashNow(AppState state, {Iterable<String>? accounts}) {
  final ids = accounts ?? state.accounts.where((a) => !a.isSavings).map((a) => a.id);
  return state.config.openingBalance + ids.fold<int>(0, (sum, id) => sum + accountCash(state, id));
}

/// What can still be spent before the cycle ends: everyday money now, plus planned
/// income and minus planned payments (and planned moves out of everyday accounts) in [c].
int safeToSpend(AppState state, Cycle c) {
  final types = typesOf(state);
  final everyday = {for (final a in state.accounts) if (!a.isSavings) a.id};
  var total = cashNow(state);
  for (final m in c.items.where((x) => x.estado != 'Pago')) {
    accountDeltas(m, types, state.defaultAccount).forEach((acc, d) {
      if (everyday.contains(acc)) total += d;
    });
  }
  return total;
}

/// Days from [today] to [cycleEnd], both included; at least 1.
int daysLeftIn(String cycleEnd, String today) {
  final e = parseISO(cycleEnd), t = parseISO(today);
  final d = DateTime.utc(e.y, e.m, e.d).difference(DateTime.utc(t.y, t.m, t.d)).inDays + 1;
  return d < 1 ? 1 : d;
}

/// Spending per expense category in [c] (income and transfers left out), biggest first.
List<MapEntry<String, int>> spendByCategory(AppState state, Cycle c) {
  final types = typesOf(state);
  final out = <String, int>{};
  for (final m in c.items) {
    if (types[m.category] == 'Saída') out[m.category] = (out[m.category] ?? 0) + m.cents;
  }
  return out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// A budget worth suggesting for [category]: what it cost on average in the (up to) three cycles
/// before [cycleId] that had any spending, rounded up to 5.00. With no history it uses [cycleId]
/// itself. Null when there is nothing to base it on.
int? suggestedBudget(AppState state, List<Cycle> cycles, String cycleId, String category, {int n = 3}) {
  int spentIn(Cycle c) => spendByCategory(state, c).where((e) => e.key == category).fold(0, (a, e) => a + e.value);
  final i = cycles.indexWhere((c) => c.id == cycleId);
  if (i < 0) return null;
  final past = <int>[];
  for (var j = i - 1; j >= 0 && past.length < n; j--) {
    if (cycles[j].items.isNotEmpty) past.add(spentIn(cycles[j]));
  }
  final basis = past.isEmpty ? [spentIn(cycles[i])] : past;
  final avg = basis.fold<int>(0, (a, b) => a + b) ~/ basis.length;
  return avg <= 0 ? null : (avg + 499) ~/ 500 * 500;
}

// ---- Savings ----------------------------------------------------------

/// Everything the user owns in every account right now (paid movements only).
int netWorth(AppState state) => cashNow(state, accounts: state.accounts.map((a) => a.id));

class GoalProgress {
  const GoalProgress({required this.saved, required this.target, this.cyclesLeft, this.etaCycle});
  final int saved, target;

  /// Contributions still needed at the current pace; null without a per-cycle amount.
  final int? cyclesLeft;
  final String? etaCycle;
  bool get done => saved >= target;
}

/// How far along a goal is, and (with a per-cycle amount) roughly when it will be reached.
GoalProgress goalProgress(AppState state, Goal g, String todayCycle) {
  final saved = accountCash(state, g.account);
  final left = g.target - saved;
  if (left <= 0) return GoalProgress(saved: saved, target: g.target, cyclesLeft: 0);
  if (g.perCycle <= 0) return GoalProgress(saved: saved, target: g.target);
  final n = (left + g.perCycle - 1) ~/ g.perCycle;
  return GoalProgress(saved: saved, target: g.target, cyclesLeft: n, etaCycle: nextCycleId(todayCycle, n));
}

/// Average savings rate (%) of the last three cycles up to [todayCycle] that had income; null without any.
int? recentSavingsRate(List<Cycle> cycles, String todayCycle) {
  final recent = cycles.where((c) => c.id.compareTo(todayCycle) <= 0 && c.receitas > 0).toList();
  if (recent.isEmpty) return null;
  final last = recent.reversed.take(3).toList();
  return (last.fold<int>(0, (a, c) => a + c.savingsRate) / last.length).round();
}

// ---- Everyday helpers ---------------------------------------------------

String addDays(String date, int n) {
  final p = parseISO(date);
  final d = DateTime.utc(p.y, p.m, p.d).add(Duration(days: n));
  return iso(d.year, d.month, d.day);
}

class Frequent {
  const Frequent(this.description, this.category, this.cents);
  final String description, category;
  final int cents;
}

/// The expenses the user pays again and again (paid by hand at least twice in the last [days]),
/// most repeated first, each with its latest amount: one tap fills the new-expense form.
List<Frequent> frequentExpenses(AppState state, String today, {int limit = 5, int days = 120}) {
  final types = typesOf(state);
  final since = addDays(today, -days);
  final groups = <String, List<Movement>>{};
  for (final m in state.movements) {
    if (m.gen || m.estado != 'Pago' || types[m.category] != 'Saída') continue;
    if (m.date.compareTo(since) < 0 || m.date.compareTo(today) > 0 || m.description.trim().isEmpty) continue;
    groups.putIfAbsent('${_norm(m.description)}|${m.category}', () => []).add(m);
  }
  final list = groups.values.where((g) => g.length >= 2).toList()
    ..sort((a, b) {
      final byCount = b.length.compareTo(a.length);
      if (byCount != 0) return byCount;
      return b.map((m) => m.date).reduce((x, y) => x.compareTo(y) >= 0 ? x : y).compareTo(a.map((m) => m.date).reduce((x, y) => x.compareTo(y) >= 0 ? x : y));
    });
  return [
    for (final g in list.take(limit))
      () {
        final last = g.reduce((a, b) => a.date.compareTo(b.date) >= 0 ? a : b);
        return Frequent(last.description, last.category, last.cents);
      }()
  ];
}

class WeekSummary {
  const WeekSummary(this.days, this.spent, this.previous, this.dueCount, this.dueTotal);

  /// Paid spending per day, the last seven days, oldest first (the last one is today).
  final List<int> days;
  final int spent, previous, dueCount, dueTotal;
}

/// The last seven days against the seven before, and what falls due in the next seven.
WeekSummary weekSummary(AppState state, String today) {
  final types = typesOf(state);
  final paid = <String, int>{};
  var dueCount = 0, dueTotal = 0;
  final next = addDays(today, 7);
  for (final m in state.movements) {
    if (types[m.category] != 'Saída') continue;
    if (m.estado == 'Pago') {
      paid[m.date] = (paid[m.date] ?? 0) + m.cents;
    } else if (m.date.compareTo(today) > 0 && m.date.compareTo(next) <= 0) {
      dueCount++;
      dueTotal += m.cents;
    }
  }
  int on(int back) => paid[addDays(today, -back)] ?? 0;
  final days = [for (var i = 6; i >= 0; i--) on(i)];
  return WeekSummary(days, days.fold(0, (a, b) => a + b), [for (var i = 7; i < 14; i++) on(i)].fold(0, (a, b) => a + b), dueCount, dueTotal);
}
