// Statement import, learned categories, frequent expenses, the weekly summary and budget suggestions.

import 'package:fin_app/src/import_csv.dart';
import 'package:fin_app/src/logic.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:fin_app/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

const ptFile = 'Data Mov.;Data Valor;Descrição;Montante;Saldo\n'
    '22-10-2026;22-10-2026;COMPRA 1234 CONTINENTE MATOSINHOS;-45,30;1.234,50\n'
    '23-10-2026;23-10-2026;TRF SALARIO EMPRESA LDA;1.630,57;2.865,07\n';

Movement paid(String id, String date, String desc, int cents, {String category = 'Outros', bool gen = false}) =>
    Movement(id: id, date: date, description: desc, category: category, cents: cents, estado: 'Pago', gen: gen);

AppState stateOf(List<Movement> ms) =>
    AppState(config: const Config(cycleStartDay: 23, openingBalance: 0), categories: categories, recurring: [], movements: ms);

void main() {
  categoryTests();
  group('reading a bank file', () {
    test('Portuguese layout: semicolons, day-first dates, decimal commas, a balance column', () {
      final r = parseBankCsv(ptFile)!;
      expect(r.rows, hasLength(2));
      expect(r.rows[0].date, '2026-10-22');
      expect(r.rows[0].cents, -4530);
      expect(r.rows[0].description, contains('CONTINENTE'));
      expect(r.rows[1].cents, 163057); // not the balance
    });

    test('separate debit and credit columns, quoted text with a comma', () {
      final r = parseBankCsv('Date,Description,Debit,Credit,Balance\n'
          '2026-10-22,"Coffee, Lisbon",3.20,,100.00\n'
          '2026-10-23,Refund,,15.00,115.00\n')!;
      expect(r.rows.map((x) => x.cents), [-320, 1500]);
      expect(r.rows[0].description, 'Coffee, Lisbon');
    });

    test('no header row', () {
      final r = parseBankCsv('22/10/2026;Pingo Doce;-12,50\n23/10/2026;Padaria;-3,10\n')!;
      expect(r.rows.map((x) => x.cents), [-1250, -310]);
      expect(r.rows.first.description, 'Pingo Doce');
    });

    test('rows without a date or amount are counted, not imported', () {
      final r = parseBankCsv('Data;Descrição;Montante\n22-10-2026;Café;-1,20\nTotal;;-1,20\n')!;
      expect(r.rows, hasLength(1));
      expect(r.skipped, 1);
    });

    test('something that is not a statement is refused', () {
      expect(parseBankCsv('hello\nworld'), isNull);
      expect(parseBankCsv('a;b;c\nd;e;f\n'), isNull);
    });

    test('dates and amounts in the usual styles', () {
      for (final d in ['22-10-2026', '22/10/2026', '2026-10-22', '22.10.2026']) {
        expect(parseBankDate(d), '2026-10-22', reason: d);
      }
      expect(parseBankDate('31-02-2026'), isNull);
      expect(parseSignedAmount('-12,30'), -1230);
      expect(parseSignedAmount('(45.00)'), -4500);
      expect(parseSignedAmount('1.234,56'), 123456);
      expect(parseSignedAmount('12,30 €'), 1230);
      expect(parseSignedAmount('12,30-'), -1230);
      expect(parseSignedAmount('abc'), isNull);
      expect(parseSignedAmount('2026-10-22'), isNull);
    });
  });

  group('categories are learned from the user', () {
    final allowed = {'Alimentação', 'Subscrição', 'Outros', 'Moradia'};

    test('what was filed before decides, whatever the card text around it', () {
      final rules = learnRules(stateOf([
        paid('a', '2026-10-01', 'Padaria Central', 300, category: 'Alimentação'),
        paid('b', '2026-10-02', 'Netflix', 1299, category: 'Subscrição'),
      ]));
      expect(rules.categoryFor('COMPRA 99 PADARIA CENTRAL PORTO', allowed: allowed), 'Alimentação');
      expect(rules.categoryFor('NETFLIX.COM 4455', allowed: allowed), 'Subscrição');
      expect(rules.categoryFor('Livraria Lello', allowed: allowed), isNull);
    });

    test('the user beats the built-in guesses; the built-ins fill the gaps', () {
      final mine = learnRules(stateOf([paid('a', '2026-10-01', 'Continente', 900, category: 'Outros')]));
      expect(mine.categoryFor('CONTINENTE MATOSINHOS', allowed: allowed), 'Outros');
      expect(learnRules(stateOf([])).categoryFor('LIDL PORTO', allowed: allowed), 'Alimentação');
    });
  });

  group('planning an import', () {
    List<ImportItem> plan(List<CsvRow> rows, [AppState? s]) => planImport(s ?? seedState(), rows);

    test('a payment of the same amount close to a planned bill settles it', () {
      final items = plan([const CsvRow('2026-10-24', 'TRF RENT', -25000), const CsvRow('2026-10-23', 'SALARIO', 113757)]);
      expect(items[0].action, ImportAction.markPaid);
      expect(items[0].plannedName, 'Renda');
      expect(items[1].action, ImportAction.markPaid);
      expect(items[1].plannedName, 'Salário');
    });

    test('one planned bill is settled only once', () {
      final items = plan([const CsvRow('2026-10-23', 'A', -25000), const CsvRow('2026-10-23', 'B', -25000)]);
      expect(items.where((i) => i.action == ImportAction.markPaid), hasLength(1));
      expect(items[1].action, ImportAction.add);
    });

    test('anything else is added under the best guess, or Outros', () {
      final items = plan([const CsvRow('2026-10-25', 'LIDL PORTO', -777), const CsvRow('2026-10-25', 'XYZ', -123)]);
      expect(items[0].action, ImportAction.add);
      expect(items[0].category, 'Alimentação');
      expect(items[1].category, 'Outros');
    });

    test('a row already recorded as paid is skipped and unticked', () {
      final s = stateOf([paid('p', '2026-10-30', 'Já cá está', 777)]);
      final items = plan([const CsvRow('2026-10-30', 'LIDL', -777)], s);
      expect(items.single.action, ImportAction.skip);
      expect(items.single.include, isFalse);
    });

    test('importing applies only what is ticked', () {
      final store = Store.memory();
      final items = plan([const CsvRow('2026-10-24', 'TRF RENT', -25000), const CsvRow('2026-10-25', 'LIDL', -777)]);
      items[1].include = false;
      expect(store.importMovements(items), 1);
      expect(store.state.movements.firstWhere((m) => m.description == 'Renda').estado, 'Pago');
      expect(store.state.movements.any((m) => m.description == 'LIDL'), isFalse);

      final again = plan([const CsvRow('2026-10-25', 'LIDL', -777)], store.state);
      expect(store.importMovements(again, account: 'main'), 1);
      final added = store.state.movements.firstWhere((m) => m.description == 'LIDL');
      expect([added.estado, added.cents, added.category], ['Pago', 777, 'Alimentação']);
    });
  });

  group('everyday helpers', () {
    test('frequent expenses: repeated by hand, recent, most repeated first', () {
      final s = stateOf([
        paid('1', '2026-11-01', 'Café', 120),
        paid('2', '2026-11-03', 'Café', 130),
        paid('3', '2026-11-05', 'Café', 140),
        paid('4', '2026-11-02', 'Almoço', 750),
        paid('5', '2026-11-04', 'Almoço', 800),
        paid('6', '2026-11-04', 'Gasóleo', 4000),
        paid('7', '2026-11-01', 'Renda', 25000, gen: true),
        paid('8', '2026-11-02', 'Renda', 25000, gen: true),
        paid('9', '2025-01-01', 'Antigo', 100),
        paid('10', '2025-01-02', 'Antigo', 100),
      ]);
      final f = frequentExpenses(s, '2026-11-10');
      expect(f.map((x) => x.description), ['Café', 'Almoço']);
      expect(f.first.cents, 140); // the latest amount
    });

    test('the week: spending per day, against the week before, and what falls due', () {
      final s = stateOf([
        paid('1', '2026-11-10', 'Hoje', 1000),
        paid('2', '2026-11-07', 'Há três dias', 500),
        paid('3', '2026-11-02', 'Semana anterior', 700),
        paid('4', '2026-11-10', 'Salário', 99999, category: 'Receita'),
        Movement(id: '5', date: '2026-11-13', description: 'Luz', category: 'Moradia', cents: 2000, estado: 'Previsto'),
        Movement(id: '6', date: '2026-12-13', description: 'Longe', category: 'Moradia', cents: 5000, estado: 'Previsto'),
      ]);
      final w = weekSummary(s, '2026-11-10');
      expect(w.days.length, 7);
      expect(w.days.last, 1000);
      expect(w.spent, 1500);
      expect(w.previous, 700);
      expect([w.dueCount, w.dueTotal], [1, 2000]);
    });

    test('adding days crosses month and year ends', () {
      expect(addDays('2026-12-30', 5), '2027-01-04');
      expect(addDays('2026-03-01', -1), '2026-02-28');
    });

    test('a suggested budget is the recent average rounded up to 5,00, or this cycle with no history', () {
      final s = seedState();
      final cycles = computeCycles(s, '2026-11-01');
      expect(suggestedBudget(s, cycles, '2026-11', 'Moradia'), 41000); // 405,88 → 410,00
      expect(suggestedBudget(s, cycles, '2026-11', 'Lazer'), isNull);
    });
  });
}

void categoryTests() {
  group('categories', () {
    test('adding: trimmed, not empty, not a duplicate, not too long', () {
      final s = Store.memory();
      final n = s.state.categories.length;
      expect(s.addCategory('  Animais ', 'Saída', '#7AA2F7'), isTrue);
      expect(s.state.categories.map((c) => c.name), contains('Animais'));
      expect(s.addCategory('animais', 'Saída', '#7AA2F7'), isFalse);
      expect(s.addCategory('   ', 'Saída', '#7AA2F7'), isFalse);
      expect(s.addCategory('x' * 25, 'Saída', '#7AA2F7'), isFalse);
      expect(s.addCategory('Transferência', 'Saída', '#7AA2F7'), isFalse);
      expect(s.state.categories.length, n + 1);
      // it survives a save and load, so the colour and kind were valid
      expect(AppState.fromJson(s.state.toJson()).categories.length, n + 1);
    });

    test('deleting moves its movements and bills to "Outros"; the rest is untouched', () {
      final s = Store.memory();
      final lazer = s.state.movements.where((m) => m.category == 'Lazer').length;
      final subs = s.state.recurring.where((r) => r.category == 'Subscrição').length;
      final others = s.state.movements.where((m) => m.category == 'Outros').length;
      expect(subs, greaterThan(0));
      expect(s.categoryHeir('Subscrição'), 'Outros');
      expect(s.removeCategory('Subscrição'), isTrue);
      expect(s.state.categories.any((c) => c.name == 'Subscrição'), isFalse);
      expect(s.state.recurring.where((r) => r.category == 'Outros'), hasLength(subs));
      expect(s.state.movements.any((m) => m.category == 'Subscrição'), isFalse);
      expect(s.state.movements.where((m) => m.category == 'Lazer'), hasLength(lazer));
      expect(s.state.movements.where((m) => m.category == 'Outros').length, greaterThanOrEqualTo(others));
      computeCycles(s.state); // still lays out
    });

    test('the last income category and the transfer category cannot be deleted', () {
      final s = Store.memory();
      expect(s.categoryHeir('Receita'), isNull);
      expect(s.removeCategory('Receita'), isFalse);
      expect(s.removeCategory('Transferência'), isFalse);
      s.addCategory('Extras', 'Entrada', '#C8F169');
      expect(s.removeCategory('Receita'), isTrue);
      expect(s.state.movements.any((m) => m.category == 'Receita'), isFalse);
      expect(s.state.movements.any((m) => m.category == 'Extras'), isTrue);
    });
  });
}
