// Same checks as ../../test/logic.test.mjs: the cycle maths must match the Google Sheet.

import 'package:fin_app/src/logic.dart';
import 'package:fin_app/src/seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
