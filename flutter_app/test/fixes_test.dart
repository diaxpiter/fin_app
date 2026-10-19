import 'package:fin_app/src/logic.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:fin_app/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

AppState blank() => AppState(
    config: const Config(cycleStartDay: 1, openingBalance: 0),
    categories: [...categories],
    recurring: [],
    movements: [
      Movement(id: 'p1', date: '2026-11-25', description: 'Luz', category: 'Moradia', cents: 5000, estado: 'Previsto'),
      Movement(id: 'p2', date: '2026-11-25', description: 'Água', category: 'Moradia', cents: 3500, estado: 'Previsto'),
      Movement(id: 'p3', date: '2026-12-25', description: 'Luz', category: 'Moradia', cents: 5000, estado: 'Previsto'),
      Movement(id: 'x', date: '2026-11-03', description: 'Luz', category: 'Moradia', cents: 4800, estado: 'Pago'),
    ]);

void main() {
  group('matching a payment to a planned bill', () {
    List<String> ids(String desc, {String date = '2026-11-10', String cat = 'Moradia'}) =>
        matchPlanned(blank(), date: date, description: desc, category: cat).map((m) => m.id).toList();

    test('same description, same cycle, still planned', () {
      expect(ids('Luz'), ['p1']);
      expect(ids('luz '), ['p1'], reason: 'case and spaces ignored');
      expect(ids('Luz EDP'), ['p1'], reason: 'contains the planned description');
    });
    test('empty description or the category name: any planned bill in that category', () {
      expect(ids(''), unorderedEquals(['p1', 'p2']));
      expect(ids('Moradia'), unorderedEquals(['p1', 'p2']));
    });
    test('no match for other descriptions, categories, cycles, or paid movements', () {
      expect(ids('Gás'), isEmpty);
      expect(ids('Luz', cat: 'Lazer'), isEmpty);
      expect(ids('Luz', date: '2027-01-10'), isEmpty);
    });
  });

  test('"how much is in the account today" sets the opening balance', () {
    final s = blank();
    expect(cashNow(s), -4800);
    final store = Store.memory(s)..setBalanceToday(120000);
    expect(cashNow(store.state), 120000);
    expect(store.state.accounts.first.openingBalance, 124800);
    store.setBalanceToday(-5000);
    expect(cashNow(store.state), -5000);
  });

  test('paying a planned bill settles it instead of adding a movement', () {
    final store = Store.memory(blank())..payPlanned('p1', cents: 5230, date: '2026-11-24');
    final p1 = store.state.movements.firstWhere((m) => m.id == 'p1');
    expect((p1.estado, p1.cents, p1.date), ('Pago', 5230, '2026-11-24'));
    expect(store.state.movements, hasLength(4));
  });

  test('a planned bill edited by hand survives editing the bill', () {
    final store = Store.memory(AppState(
        config: const Config(cycleStartDay: 1, openingBalance: 0),
        categories: [...categories],
        recurring: [],
        movements: []));
    const bill = Recurring(id: 'b', description: 'Luz', category: 'Moradia', cents: 5000, day: 5);
    store.saveRecurring(bill, '2026-11-01');
    final dec = store.state.movements.firstWhere((m) => m.date == '2026-12-05');
    store.updateMovement(dec.copyWith(cents: 6100)); // known higher estimate for December
    store.saveRecurring(const Recurring(id: 'b', description: 'Luz', category: 'Moradia', cents: 5500, day: 5), '2026-11-01');
    expect(store.state.movements.firstWhere((m) => m.date == '2026-12-05').cents, 6100);
    expect(store.state.movements.firstWhere((m) => m.date == '2027-01-05').cents, 5500);
    expect(store.state.movements.where((m) => m.id == dec.id), hasLength(1), reason: 'no duplicate');
  });

  test('moving an early-paid salary to another date drops its cycle override', () {
    final m = Movement(
        id: 'g', date: '2026-10-23', description: 'Salário', category: 'Receita', cents: 1, estado: 'Previsto', gen: true, cycle: '2026-11');
    expect(m.copyWith(cents: 2).cycle, '2026-11');
    expect(m.copyWith(date: '2026-10-27').cycle, isNull);
    expect(m.copyWith(cents: 2).edited, isTrue);
  });
}
