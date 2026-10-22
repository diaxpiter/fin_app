// Savings goals: each has a savings account and, optionally, an automatic transfer on payday.

import 'package:fin_app/src/logic.dart';
import 'package:fin_app/src/merge.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:fin_app/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

Store storeWithGoal({int perCycle = 10000}) {
  final store = Store.memory();
  store.saveGoal(name: 'Férias', target: 90000, perCycle: perCycle, alreadySaved: 30000, today: '2026-11-01');
  return store;
}

void main() {
  test('a goal gets its own savings account and a transfer on the salary day', () {
    final store = storeWithGoal();
    final g = store.state.goals.single;
    final acc = store.state.accountById(g.account)!;
    expect(acc.isSavings, isTrue);
    expect(acc.openingBalance, 30000);
    final bill = store.state.recurring.firstWhere((r) => r.id == g.billId);
    expect(bill.category, transferType);
    expect(bill.cents, 10000);
    expect(bill.toAccount, g.account);
    expect(bill.account, store.state.defaultAccount);
    expect(bill.day, 25); // the salary's day in the example data
    expect(store.state.movements.where((m) => m.toAccount == g.account), isNotEmpty);
  });

  test('progress and the finish estimate follow the per-cycle amount', () {
    final store = storeWithGoal();
    final p = goalProgress(store.state, store.state.goals.single, '2026-11');
    expect(p.saved, 30000);
    expect(p.cyclesLeft, 6); // 600,00 left at 100,00 a cycle
    expect(p.etaCycle, '2027-05');
    expect(p.done, isFalse);
    expect(goalProgress(storeWithGoal(perCycle: 0).state, storeWithGoal(perCycle: 0).state.goals.single, '2026-11').etaCycle, isNull);
  });

  test('a reached goal is done', () {
    final store = Store.memory();
    store.saveGoal(name: 'Pequena', target: 20000, perCycle: 0, alreadySaved: 25000);
    expect(goalProgress(store.state, store.state.goals.single, '2026-11').done, isTrue);
  });

  test('changing the amount updates the transfer; zero removes it; deleting keeps the account', () {
    final store = storeWithGoal();
    final g = store.state.goals.single;
    store.saveGoal(id: g.id, name: 'Férias', target: 90000, perCycle: 5000, today: '2026-11-01');
    expect(store.state.recurring.firstWhere((r) => r.id == g.billId).cents, 5000);
    expect(store.state.accounts.where((a) => a.id == g.account), hasLength(1)); // no second account

    store.saveGoal(id: g.id, name: 'Férias', target: 90000, perCycle: 0, today: '2026-11-01');
    expect(store.state.recurring.any((r) => r.id == g.billId), isFalse);
    expect(store.state.movements.any((m) => m.toAccount == g.account && m.estado == 'Previsto'), isFalse);

    store.removeGoal(g.id, today: '2026-11-01');
    expect(store.state.goals, isEmpty);
    expect(store.state.accountById(g.account), isNotNull);
  });

  test('a goal can use an existing savings account', () {
    final store = Store.memory();
    store.saveAccount(const Account(id: 'sav', name: 'Poupança', kind: AccountKind.savings, openingBalance: 100000));
    store.saveGoal(name: 'Casa', target: 500000, perCycle: 0, account: 'sav');
    expect(store.state.accounts.where((a) => a.isSavings), hasLength(1));
    expect(goalProgress(store.state, store.state.goals.single, '2026-11').saved, 100000);
  });

  test('net worth counts every account, savings included', () {
    final store = storeWithGoal();
    store.saveAccount(const Account(id: 'x', name: 'Cartão', kind: AccountKind.spending, openingBalance: 5000));
    expect(netWorth(store.state), 35000);
  });

  test('recent savings rate comes from the last cycles with income', () {
    final cycles = computeCycles(seedState(), '2026-11-01');
    expect(recentSavingsRate(cycles, '2026-11'), 21);
    expect(recentSavingsRate(cycles, '2026-01'), isNull);
  });

  test('goals survive a backup, an old backup without goals, and a merge', () {
    final store = storeWithGoal();
    final back = AppState.fromJson(store.state.toJson());
    expect(back.goals.single.name, 'Férias');
    final old = store.state.toJson()..remove('goals');
    expect(AppState.fromJson(old).goals, isEmpty);

    final base = AppState.fromJson(seedState().toJson());
    final merged = mergeStates(base, store.state, base);
    expect(merged.goals.single.name, 'Férias');
    expect(mergeStates(base, base, store.state).goals.single.name, 'Férias');
  });
}
