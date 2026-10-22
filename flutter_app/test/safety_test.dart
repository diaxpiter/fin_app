// Bad data must be refused when read, never crash the app, and never overwrite data we couldn't read.

import 'dart:convert';

import 'package:fin_app/src/i18n.dart';
import 'package:fin_app/src/merge.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:fin_app/src/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> backup() => seedState().toJson();

AppState state(List<Movement> movements) => AppState(
    config: const Config(cycleStartDay: 23, openingBalance: 0), categories: categories, recurring: [], movements: movements);

Movement mv(String id, String desc, {int cents = 100}) =>
    Movement(id: id, date: '2026-11-02', description: desc, category: 'Outros', cents: cents, estado: 'Pago');

List<String> names(AppState s) => (s.movements.map((m) => m.description).toList()..sort());

void main() {
  group('malformed data is refused', () {
    void refuses(String what, void Function(Map<String, dynamic> j) damage) {
      test(what, () {
        final j = backup();
        damage(j);
        expect(() => AppState.fromJson(j), throwsFormatException);
      });
    }

    refuses('category colour', (j) => (j['categories'] as List)[0]['color'] = 'red');
    refuses('category type', (j) => (j['categories'] as List)[0]['type'] = 'x');
    refuses('impossible date', (j) => (j['movements'] as List)[0]['date'] = '2026-02-30');
    refuses('not a date', (j) => (j['movements'] as List)[0]['date'] = 'abc');
    refuses('status', (j) => (j['movements'] as List)[0]['estado'] = 'Talvez');
    refuses('negative amount', (j) => (j['movements'] as List)[0]['cents'] = -5);
    refuses('absurd amount', (j) => (j['movements'] as List)[0]['cents'] = 1000000000000000000);
    refuses('bill day', (j) => (j['recurring'] as List)[0]['day'] = 40);
    refuses('cycle id', (j) => (j['recurring'] as List)[0]['from'] = '2026-13');
    refuses('start day', (j) => (j['config'] as Map)['cycleStartDay'] = 40);
    refuses('currency', (j) => (j['config'] as Map)['currency'] = 'euros');

    test('a good backup still loads', () => expect(() => AppState.fromJson(backup()), returnsNormally));
  });

  group('store', () {
    test('a bad import changes nothing', () {
      final store = Store.memory();
      final before = store.state.movements.length;
      final j = backup();
      (j['movements'] as List)[0]['date'] = 'abc';
      expect(() => store.importJSON(jsonEncode(j)), throwsFormatException);
      expect(store.state.movements.length, before);
    });

    test('unreadable saved data is kept, not overwritten', () async {
      const raw = '{"version":2,"future":"data"}';
      SharedPreferences.setMockInitialValues({'fin_app_v1': raw});
      final store = await Store.open();
      expect(store.unreadableCopy, raw);
      expect(store.state.movements, isEmpty);
    });

    test('a new user starts empty, not with the example data', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await Store.open();
      expect(store.state.movements, isEmpty);
      expect(store.state.recurring, isEmpty);
    });

    test('on a shared device nothing is written to local storage', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await Store.open();
      final p = await SharedPreferences.getInstance();
      expect(p.getString('fin_app_v1'), isNotNull);
      store.persist = false;
      expect(p.getString('fin_app_v1'), isNull);
      store.addMovement(date: '2026-11-02', description: 'x', category: 'Outros', cents: 1, estado: 'Pago');
      expect(p.getString('fin_app_v1'), isNull);
    });
  });

  group('three-way merge', () {
    final base = state([mv('a', 'A'), mv('b', 'B')]);

    test('both sides add: both kept', () {
      final m = mergeStates(base, state([mv('a', 'A'), mv('b', 'B'), mv('c', 'local')]),
          state([mv('a', 'A'), mv('b', 'B'), mv('d', 'remote')]));
      expect(names(m), ['A', 'B', 'local', 'remote']);
    });

    test('a deletion made here stays deleted; an untouched remote item is not resurrected', () {
      final m = mergeStates(base, state([mv('a', 'A')]), state([mv('a', 'A'), mv('b', 'B')]));
      expect(names(m), ['A']);
    });

    test('a remote edit is kept when this side did not touch the item', () {
      final m = mergeStates(base, state([mv('a', 'A'), mv('b', 'B')]), state([mv('a', 'A'), mv('b', 'B', cents: 999)]));
      expect(m.movements.firstWhere((x) => x.id == 'b').cents, 999);
    });

    test('when both edit the same item the local edit wins', () {
      final m = mergeStates(
          base, state([mv('a', 'A', cents: 1), mv('b', 'B')]), state([mv('a', 'A', cents: 2), mv('b', 'B')]));
      expect(m.movements.firstWhere((x) => x.id == 'a').cents, 1);
    });

    test('an item edited here survives a remote deletion', () {
      final m = mergeStates(base, state([mv('a', 'A', cents: 7), mv('b', 'B')]), state([mv('b', 'B')]));
      expect(names(m), ['A', 'B']);
    });

    test('settings changed here win, otherwise the remote ones', () {
      final local = state([mv('a', 'A'), mv('b', 'B')])..config = const Config(cycleStartDay: 10, openingBalance: 0);
      expect(mergeStates(base, local, base).config.cycleStartDay, 10);
      final remote = state([mv('a', 'A'), mv('b', 'B')])..config = const Config(cycleStartDay: 5, openingBalance: 0);
      expect(mergeStates(base, base, remote).config.cycleStartDay, 5);
    });
  });

  group('exports and limits', () {
    test('CSV: quotes are escaped and formula-looking text is defused', () {
      final store = Store.memory(state([
        Movement(id: 'x', date: '2026-11-02', description: '=HYPERLINK("http://evil")', category: 'Outros', cents: 1234, estado: 'Pago'),
        Movement(id: 'y', date: '2026-11-03', description: 'Salário, mês', category: 'Receita', cents: 100000, estado: 'Previsto'),
      ]));
      final csv = store.exportCSV().split('\n');
      expect(csv.first, 'date,description,category,account,amount,status');
      expect(csv[1], startsWith("2026-11-02,\"'=HYPERLINK(\"\"http://evil\"\")\",\"Outros\","));
      expect(csv[1], endsWith(',-12.34,Pago'));
      expect(csv[2], contains('"Salário, mês"'));
      expect(csv[2], endsWith(',1000.00,Previsto'));
    });

    test('the backup date is remembered and survives a round trip', () {
      final store = Store.memory();
      store.markBackedUp('2026-11-05');
      expect(AppState.fromJson(store.state.toJson()).config.lastBackup, '2026-11-05');
      final j = store.state.toJson();
      (j['config'] as Map)['lastBackup'] = 'soon';
      expect(() => AppState.fromJson(j), throwsFormatException);
    });

    test('amounts of more than 12 digits are refused so they stay exact', () {
      expect(parseAmount('9.999.999.999,99'), 999999999999);
      expect(parseAmount('99999999999999'), isNull);
    });
  });
}
