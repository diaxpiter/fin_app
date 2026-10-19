import 'dart:convert';

import 'package:fin_app/src/logic.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:fin_app/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The user's setup: salary into ActivoBank, everyday in Revolut, ETFs at XTB, emergency fund at Trade Republic.
AppState fourAccounts() => AppState(
      config: const Config(cycleStartDay: 1, openingBalance: 0),
      categories: [...categories],
      recurring: [],
      accounts: const [
        Account(id: 'activo', name: 'ActivoBank', kind: AccountKind.current, openingBalance: 50000),
        Account(id: 'revolut', name: 'Revolut', kind: AccountKind.spending, openingBalance: 10000),
        Account(id: 'xtb', name: 'XTB', kind: AccountKind.investment, openingBalance: 200000),
        Account(id: 'tr', name: 'Trade Republic', kind: AccountKind.savings, openingBalance: 300000),
      ],
      movements: [
        Movement(id: 's', date: '2026-11-03', description: 'Salário', category: 'Receita', cents: 150000, estado: 'Pago', account: 'activo'),
        Movement(id: 'r', date: '2026-11-04', description: 'Renda', category: 'Moradia', cents: 60000, estado: 'Pago', account: 'activo'),
        Movement(id: 't1', date: '2026-11-04', description: 'Dia a dia', category: 'Transferência', cents: 40000, estado: 'Pago', account: 'activo', toAccount: 'revolut'),
        Movement(id: 't2', date: '2026-11-05', description: 'ETF', category: 'Transferência', cents: 30000, estado: 'Pago', account: 'activo', toAccount: 'xtb'),
        Movement(id: 'c', date: '2026-11-06', description: 'Café', category: 'Alimentação', cents: 250, estado: 'Pago', account: 'revolut'),
        Movement(id: 'p', date: '2026-11-25', description: 'Luz', category: 'Moradia', cents: 50000, estado: 'Previsto', account: 'activo'),
      ],
    );

void main() {
  test('each account holds its own balance; transfers move money between them', () {
    final s = fourAccounts();
    expect(accountCash(s, 'activo'), 50000 + 150000 - 60000 - 40000 - 30000);
    expect(accountCash(s, 'revolut'), 10000 + 40000 - 250);
    expect(accountCash(s, 'xtb'), 200000 + 30000);
    expect(accountCash(s, 'tr'), 300000);
  });

  test('"Em conta" is everyday money; savings and investments are listed apart', () {
    final s = fourAccounts();
    expect(cashNow(s), accountCash(s, 'activo') + accountCash(s, 'revolut'));
    expect(cashNow(s, accounts: s.accounts.map((a) => a.id)), 50000 + 10000 + 200000 + 300000 + 150000 - 60000 - 250);
  });

  test('transfers are neither income nor expense; money moved to savings shows as saved', () {
    final nov = computeCycles(fourAccounts(), '2026-11-10').firstWhere((c) => c.id == '2026-11');
    expect(nov.receitas, 150000);
    expect(nov.despesas, 60000 + 250 + 50000);
    expect(nov.saved, 30000, reason: 'only the ETF transfer; Revolut is everyday money');
  });

  test('per-account forecast: the salary account would run short when the bill is paid', () {
    final nov = computeCycles(fourAccounts(), '2026-11-10').firstWhere((c) => c.id == '2026-11');
    expect(nov.accountEnd['activo'], 70000 - 50000);
    expect(nov.accountLowest['activo'], 20000);
    expect(nov.accountLowestDate['activo'], '2026-11-25');
    final tight = fourAccounts();
    tight.movements.add(Movement(
        id: 'k', date: '2026-11-26', description: 'Klarna', category: 'Crédito', cents: 30000, estado: 'Previsto', account: 'activo'));
    final c = computeCycles(tight, '2026-11-10').firstWhere((c) => c.id == '2026-11');
    expect(c.accountLowest['activo'], -10000);
    expect(c.accountLowestDate['activo'], '2026-11-26');
  });

  test('setting today\'s balance of one account leaves the others alone', () {
    final store = Store.memory(fourAccounts())..setBalanceToday(123400, account: 'revolut');
    expect(accountCash(store.state, 'revolut'), 123400);
    expect(accountCash(store.state, 'activo'), 70000);
  });

  test('accounts in use cannot be deleted; unused ones can', () {
    final store = Store.memory(fourAccounts());
    expect(store.removeAccount('activo'), isFalse);
    expect(store.removeAccount('tr'), isTrue);
    expect(store.state.accounts.map((a) => a.id), ['activo', 'revolut', 'xtb']);
  });

  test('a transfer bill plans the transfer on its accounts', () {
    final store = Store.memory(fourAccounts())
      ..saveRecurring(
          const Recurring(
              id: 'etf', description: 'ETF', category: 'Transferência', cents: 30000, day: 26, account: 'activo', toAccount: 'xtb'),
          '2026-11-10');
    final planned = store.state.movements.where((m) => m.id.startsWith('gen:etf:')).toList();
    // November already has the ETF transfer typed in by hand: no duplicate there
    expect(planned, hasLength(recurringHorizon - 1));
    expect(planned.any((m) => m.date.startsWith('2026-11')), isFalse);
    expect((planned.first.account, planned.first.toAccount), ('activo', 'xtb'));
  });

  test('older data: one opening balance becomes the main account; still loads and saves', () {
    final j = seedState().toJson()
      ..remove('accounts')
      ..['config'] = {'cycleStartDay': 23, 'openingBalance': 12345};
    final s = AppState.fromJson(jsonDecode(jsonEncode(j)));
    expect(s.accounts.single.id, 'main');
    expect(s.accounts.single.openingBalance, 12345);
    expect(s.config.openingBalance, 0);
    expect(cashNow(s), 12345);
    expect(s.categories.where((c) => c.type == transferType), hasLength(1));
    expect(AppState.fromJson(jsonDecode(jsonEncode(s.toJson()))).accounts.single.openingBalance, 12345);
  });
}
