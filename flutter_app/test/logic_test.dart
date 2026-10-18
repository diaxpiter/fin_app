// Same checks as ../../test/logic.test.mjs: the cycle maths must match the Google Sheet.

import 'package:fin_app/src/logic.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fixed bills', recurringTests);

  test('cycle ids and bounds (start day 23)', () {
    expect(cycleIdOf('2026-10-23', 23), '2026-11');
    expect(cycleIdOf('2026-11-22', 23), '2026-11');
    expect(cycleIdOf('2026-11-23', 23), '2026-12');
    expect(cycleIdOf('2026-10-16', 23), '2026-10');
    expect(cycleBounds('2026-11', 23), (start: '2026-10-23', end: '2026-11-22'));
    expect(cycleBounds('2027-01', 23), (start: '2026-12-23', end: '2027-01-22'));
  });

  test('calendar-month cycles when start day is 1', () {
    expect(cycleIdOf('2026-03-15', 1), '2026-03');
    expect(cycleBounds('2026-02', 1), (start: '2026-02-01', end: '2026-02-28'));
  });

  test('recurring occurrence lands inside its cycle', () {
    expect(occurrenceDate(25, '2026-12', 23), '2026-11-25');
    expect(occurrenceDate(11, '2026-12', 23), '2026-12-11');
    expect(occurrenceDate(27, '2026-12', 23), '2026-11-27');
  });

  test('money formatting and parsing', () {
    expect(fmtCents(113757), '1.137,57');
    expect(fmtCents(-25000), '−250,00');
    expect(fmtCents(5, sign: true), '+0,05');
    expect(parseMoney('1.137,57'), 113757);
    expect(parseMoney('35'), 3500);
  });

  test('first cycle matches the sheet', () {
    final nov = computeCycles(seedState(), '2026-10-15').firstWhere((c) => c.id == '2026-11');
    expect(nov.receitas, 113757);
    expect(nov.despesas, 89851);
    expect(nov.sobra, 23906);
    expect(nov.porPagar, 89851);
    expect(nov.pago, 0);
    expect(nov.savingsRate, 21);
    expect(nov.lowest, 23906);
    expect(nov.lowestDate, '2026-11-13');
  });

  test('forecast matches the sheet', () {
    final by = {for (final c in computeCycles(seedState(), '2026-10-15')) c.id: c};
    expect(by['2026-12']!.receitas, 163057);
    expect(by['2026-12']!.despesas, 45606);
    expect(by['2026-12']!.sobra, 117451);
    expect(by['2026-12']!.endBalance, 141357);
    expect(by['2027-01']!.receitas, 106600);
    expect(by['2027-01']!.sobra, 60994);
    expect(by['2027-01']!.endBalance, 202351);
    expect(by['2027-06']!.endBalance, 789606);
  });

  test('cash in account only counts movements marked Pago', () {
    final s = seedState();
    expect(cashNow(s), 0);
    s.movements.firstWhere((m) => m.description == 'Salário').estado = 'Pago';
    expect(cashNow(s), 113757);
  });

  test("today's cycle is listed even before the plan starts", () {
    final cycles = computeCycles(seedState(), '2026-10-16');
    expect(cycles.first.id, '2026-10');
    expect(cycles.first.items, isEmpty);
  });
}

void recurringTests() {
  Recurring bill({String id = 'b', int cents = 1000, int day = 5, String? from, String? to}) =>
      Recurring(id: id, description: 'Renda', category: 'Moradia', cents: cents, day: day, from: from, to: to);

  AppState blank(List<Recurring> rec) => AppState(
      config: const Config(cycleStartDay: 1, openingBalance: 0), categories: [...categories], recurring: rec, movements: []);

  test('the example data needs no changes (no duplicates of hand-entered bills)', () {
    expect(syncRecurring(seedState(), '2026-10-18'), isNull);
  });

  test('a bill fills the current cycle and the next ones', () {
    final s = blank([bill()]);
    final out = syncRecurring(s, '2026-11-10')!;
    expect(out, hasLength(recurringHorizon));
    expect(out.first.date, '2026-11-05');
    expect(out.last.date, '2027-10-05');
    expect(syncRecurring(s..movements = out, '2026-11-10'), isNull, reason: 'idempotent');
  });

  test('from / to limit the cycles', () {
    final out = syncRecurring(blank([bill(from: '2027-01', to: '2027-03')]), '2026-11-10')!;
    expect(out.map((m) => m.date), ['2027-01-05', '2027-02-05', '2027-03-05']);
  });

  test('editing regenerates future planned occurrences but keeps paid ones and past cycles', () {
    final s = blank([bill()]);
    s.movements = syncRecurring(s, '2026-11-10')!;
    s.movements.firstWhere((m) => m.date == '2026-12-05').estado = 'Pago';
    final edited = AppState(config: s.config, categories: s.categories, recurring: [bill(cents: 2000)], movements: s.movements);
    final out = syncRecurring(edited, '2026-11-10', regenerate: {'b'})!;
    expect(out.firstWhere((m) => m.date == '2026-12-05').cents, 1000, reason: 'paid stays');
    expect(out.firstWhere((m) => m.date == '2027-01-05').cents, 2000);
    expect(out, hasLength(recurringHorizon));
  });

  test('deleting a bill removes only its future planned movements', () {
    final s = blank([bill()]);
    s.movements = syncRecurring(s, '2026-11-10')!;
    s.movements.first.estado = 'Pago';
    final gone = AppState(config: s.config, categories: s.categories, recurring: [], movements: s.movements);
    expect(syncRecurring(gone, '2026-11-10', regenerate: {'b'})!.single.estado, 'Pago');
  });

  test('a movement typed in by hand is not duplicated by the bill', () {
    final s = blank([bill()]);
    s.movements = [Movement(id: 'm1', date: '2026-11-07', description: 'Renda', category: 'Moradia', cents: 990, estado: 'Pago')];
    final out = syncRecurring(s, '2026-11-10')!;
    expect(out.where((m) => cycleIdOf(m.date, 1) == '2026-11'), hasLength(1));
  });
}
