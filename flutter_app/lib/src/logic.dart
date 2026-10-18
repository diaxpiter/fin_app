// Pure finance logic: cycles, recurring-bill expansion, totals.
// Port of ../src/logic.js — keep the two in sync. Tested in test/logic_test.dart.
// Money is handled in integer cents to avoid floating-point drift.

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

const _months = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const _weekdays = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];

String monthShort(int m) => _months[m - 1];

String cycleLabel(String id) {
  final e = _ym(id);
  final s = _months[e.m - 1];
  return '${s[0].toUpperCase()}${s.substring(1)} ${e.y}';
}

String formatDay(String dateISO) {
  final p = parseISO(dateISO);
  return '${p.d} ${monthShort(p.m)}';
}

String weekday(String dateISO) {
  final p = parseISO(dateISO);
  return _weekdays[DateTime.utc(p.y, p.m, p.d).weekday % 7];
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

// `overrides` maps "recId:cycleId" -> cents.
List<Movement> expandRecurring(List<Recurring> recurring, List<String> cycleIds, int startDay,
    [Map<String, int> overrides = const {}]) {
  final out = <Movement>[];
  for (final cycleId in cycleIds) {
    for (final r in recurring) {
      if (r.from != null && cycleId.compareTo(r.from!) < 0) continue;
      if (r.to != null && cycleId.compareTo(r.to!) > 0) continue;
      final key = '${r.id}:$cycleId';
      out.add(Movement(
        id: 'gen:$key',
        date: occurrenceDate(r.day, cycleId, startDay),
        description: r.description,
        category: r.category,
        cents: overrides[key] ?? r.cents,
        estado: 'Previsto',
        gen: true,
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
        _genCycle(m)!.compareTo(cur) >= 0;
    if (drop) changed = true;
    return !drop;
  }).toList();

  final ids = movements.map((m) => m.id).toSet();
  final seen = <String>{for (final m in movements) '${cycleIdOf(m.date, s)}|${m.description}|${m.category}'};
  final added = expandRecurring(state.recurring, cycleRange(cur, nextCycleId(cur, recurringHorizon - 1)), s)
      .where((m) => !ids.contains(m.id) && !seen.contains('${cycleIdOf(m.date, s)}|${m.description}|${m.category}'));
  for (final m in added) {
    movements.add(m);
    changed = true;
  }
  return changed ? movements : null;
}

// ---- Totals -----------------------------------------------------------

Map<String, String> typesOf(AppState s) => {for (final c in s.categories) c.name: c.type};
bool _isIncome(Movement m, Map<String, String> types) => types[m.category] == 'Entrada';
int signed(Movement m, Map<String, String> types) => _isIncome(m, types) ? m.cents : -m.cents;

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
  });
  final String id, label, start, end;
  final List<Movement> items;
  final int receitas, despesas, sobra, pago, porPagar, startBalance, endBalance, lowest, savingsRate;
  final String? lowestDate;
}

List<Cycle> computeCycles(AppState state, [String? today]) {
  final s = state.config.cycleStartDay;
  final types = typesOf(state);

  final ids = {cycleIdOf(today ?? todayISO(), s), for (final m in state.movements) cycleIdOf(m.date, s)};
  final sorted = ids.toList()..sort();
  final all = cycleRange(sorted.first, sorted.last);

  final byCycle = {for (final id in all) id: <Movement>[]};
  for (final m in state.movements) {
    byCycle[cycleIdOf(m.date, s)]!.add(m);
  }

  var balance = state.config.openingBalance;
  return all.map((id) {
    final items = sortMovements(byCycle[id]!, types);
    var receitas = 0, despesas = 0, pago = 0, porPagar = 0;
    for (final m in items) {
      if (_isIncome(m, types)) {
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
    // lowest END-OF-DAY balance inside the cycle
    var run = startBalance, lowest = startBalance;
    String? lowestDate;
    for (var i = 0; i < items.length; i++) {
      run += signed(items[i], types);
      final last = i == items.length - 1 || items[i + 1].date != items[i].date;
      if (last && (lowestDate == null || run < lowest)) {
        lowest = run;
        lowestDate = items[i].date;
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
    );
  }).toList();
}

// money actually in the account: opening balance + every movement marked Pago
int cashNow(AppState state) {
  final types = typesOf(state);
  return state.movements
      .where((m) => m.estado == 'Pago')
      .fold(state.config.openingBalance, (acc, m) => acc + signed(m, types));
}
