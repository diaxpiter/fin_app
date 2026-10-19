import 'dart:convert';

import 'package:fin_app/src/holidays.dart';
import 'package:fin_app/src/logic.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Easter and the holidays that move with it (Portugal)', () {
    expect(easter(2026), DateTime.utc(2026, 4, 5));
    expect(easter(2027), DateTime.utc(2027, 3, 28));
    expect(isHoliday('2026-04-03', 'PT'), isTrue, reason: 'Good Friday');
    expect(isHoliday('2026-06-04', 'PT'), isTrue, reason: 'Corpus Christi');
    expect(isHoliday('2027-05-27', 'PT'), isTrue, reason: 'Corpus Christi');
    expect(isHoliday('2026-06-10', 'PT'), isTrue);
    expect(isHoliday('2026-06-11', 'PT'), isFalse);
    expect(isHoliday('2026-06-10', 'none'), isFalse);
  });

  test('salary on the 25th, or the business day before', () {
    String before(String d) => shiftToBusinessDay(d, DayShift.before, 'PT');
    expect(before('2027-01-25'), '2027-01-25', reason: 'Monday: unchanged');
    expect(before('2026-07-25'), '2026-07-24', reason: 'Saturday → Friday');
    expect(before('2026-10-25'), '2026-10-23', reason: 'Sunday → Friday');
    expect(before('2026-04-25'), '2026-04-24', reason: 'Saturday and holiday → Friday');
    expect(before('2026-12-25'), '2026-12-24', reason: 'Christmas on a Friday → Thursday');
    expect(before('2027-12-25'), '2027-12-24', reason: 'Christmas on a Saturday → Friday');
    expect(before('2026-06-10'), '2026-06-09', reason: 'holiday on a Wednesday → Tuesday');
    expect(shiftToBusinessDay('2026-04-25', DayShift.after, 'PT'), '2026-04-27');
    expect(shiftToBusinessDay('2026-10-25', DayShift.none, 'PT'), '2026-10-25');
  });

  AppState withSalary({required int startDay, String holidays = 'PT'}) => AppState(
        config: Config(cycleStartDay: startDay, openingBalance: 0, holidays: holidays),
        categories: [...categories],
        recurring: [
          const Recurring(
              id: 'sal', description: 'Salário', category: 'Receita', cents: 100000, day: 25, shift: DayShift.before),
        ],
        movements: [],
      );

  test('the planned salary lands on the business day', () {
    final s = withSalary(startDay: 1)..movements = syncRecurring(withSalary(startDay: 1), '2026-10-01')!;
    expect(s.movements.firstWhere((m) => m.date.startsWith('2026-10')).date, '2026-10-23');
    expect(s.movements.firstWhere((m) => m.date.startsWith('2026-12')).date, '2026-12-24');
  });

  test('paid early, before the cycle starts: still counts in its own cycle', () {
    // cycles start on the 25th (payday); Sunday 25 Oct 2026 → paid Friday 23 Oct
    final s = withSalary(startDay: 25);
    s.movements = syncRecurring(s, '2026-10-01')!;
    final oct = s.movements.firstWhere((m) => m.date == '2026-10-23');
    expect(cycleIdOf(oct.date, 25), '2026-10', reason: 'by date it would fall in the previous cycle');
    expect(oct.cycle, '2026-11');
    final cycles = {for (final c in computeCycles(s, '2026-10-01')) c.id: c};
    expect(cycles['2026-11']!.receitas, 100000);
    expect(cycles['2026-10']!.receitas, 100000, reason: 'September’s salary, not two');
    expect(cycles.values.every((c) => c.receitas <= 100000), isTrue);
    // round-trips through a backup
    final back = AppState.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.movements.firstWhere((m) => m.date == '2026-10-23').cycle, '2026-11');
  });

  test('weekends only when holidays are off', () {
    final s = withSalary(startDay: 1, holidays: 'none');
    final out = syncRecurring(s, '2026-12-01')!;
    expect(out.first.date, '2026-12-25', reason: 'Christmas Friday is a business day without holidays');
  });

  test('old data without the new fields still loads', () {
    final j = seedState().toJson();
    (j['config'] as Map).remove('holidays');
    final back = AppState.fromJson(jsonDecode(jsonEncode(j)));
    expect(back.config.holidays, 'PT');
    expect(back.recurring.every((r) => r.shift == DayShift.none), isTrue);
  });
}
