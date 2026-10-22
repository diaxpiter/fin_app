// Starting data, copied from the "Financial - Davi" Google Sheet.
// Used by "Repor dados de exemplo" and by tests; a new user starts from [emptyState].

import 'logic.dart';
import 'models.dart';

const categories = [
  Category(name: 'Receita', type: 'Entrada', color: '#C8F169'),
  Category(name: 'Moradia', type: 'Saída', color: '#7AA2F7'),
  Category(name: 'Alimentação', type: 'Saída', color: '#E9B44C'),
  Category(name: 'Subscrição', type: 'Saída', color: '#B58CF5'),
  Category(name: 'Crédito', type: 'Saída', color: '#FF7A64'),
  Category(name: 'Lazer', type: 'Saída', color: '#5FD0A5'),
  Category(name: 'Outros', type: 'Saída', color: '#9A9AA1'),
];

// Contas fixas. `from` / `to` are cycle ids (the month the cycle ends in).
const recurring = [
  Recurring(id: 'sal', description: 'Salário', category: 'Receita', cents: 163057, day: 25, variable: true, from: '2026-11'),
  Recurring(id: 'renda', description: 'Renda', category: 'Moradia', cents: 25000, day: 25, from: '2026-11'),
  Recurring(id: 'agua', description: 'Água', category: 'Moradia', cents: 3500, day: 25, variable: true, from: '2026-11'),
  Recurring(id: 'luz', description: 'Luz', category: 'Moradia', cents: 5000, day: 25, variable: true, from: '2026-11'),
  Recurring(id: 'tel', description: 'Telemóvel', category: 'Moradia', cents: 4223, day: 25, from: '2026-11'),
  Recurring(id: 'net', description: 'Internet', category: 'Moradia', cents: 2865, day: 25, from: '2026-11'),
  Recurring(id: 'klarna', description: 'Klarna', category: 'Crédito', cents: 34709, day: 25, variable: true, from: '2026-11', to: '2026-11'),
  Recurring(id: 'cred', description: 'Crédito', category: 'Crédito', cents: 9536, day: 11, from: '2026-11', to: '2026-11'),
  Recurring(id: 'gin1', description: 'Ginásio 1/2', category: 'Subscrição', cents: 1960, day: 27, from: '2026-11'),
  Recurring(id: 'gin2', description: 'Ginásio 2/2', category: 'Subscrição', cents: 1960, day: 11, from: '2026-11'),
  Recurring(id: 'icloud', description: 'iCloud', category: 'Subscrição', cents: 99, day: 11, from: '2026-11'),
  Recurring(id: 'crunchy', description: 'Crunchyroll', category: 'Subscrição', cents: 999, day: 11, from: '2026-11'),
];

// The first cycle (23 Oct – 22 Nov 2026) was entered by hand in the sheet.
const _firstCycle = [
  ('2026-10-23', 'Salário', 'Receita', 113757),
  ('2026-10-23', 'Renda', 'Moradia', 25000),
  ('2026-10-23', 'Água', 'Moradia', 3500),
  ('2026-10-23', 'Luz', 'Moradia', 5000),
  ('2026-10-23', 'Telemóvel', 'Moradia', 4223),
  ('2026-10-23', 'Internet', 'Moradia', 2865),
  ('2026-10-23', 'Klarna', 'Crédito', 34709),
  ('2026-10-30', 'Ginásio 1/2', 'Subscrição', 1960),
  ('2026-11-10', 'iCloud', 'Subscrição', 99),
  ('2026-11-11', 'Crunchyroll', 'Subscrição', 999),
  ('2026-11-11', 'Crédito', 'Crédito', 9536),
  ('2026-11-13', 'Ginásio 2/2', 'Subscrição', 1960),
];

AppState seedState() {
  const config = Config(cycleStartDay: 23, openingBalance: 0);
  final ids = cycleRange('2026-12', '2027-10');
  // salary in Jan 2027 is lower in the sheet (10 660,00 → 1.066,00 €)
  const overrides = {'sal:2027-01': 106600};
  var i = 0;
  final first = [
    for (final (date, description, category, cents) in _firstCycle)
      Movement(id: 'seed:${i++}', date: date, description: description, category: category, cents: cents, estado: 'Previsto'),
  ];
  return AppState(
    config: config,
    categories: [...categories],
    recurring: [...recurring],
    movements: [...first, ...expandRecurring(recurring, ids, config.cycleStartDay, overrides)],
  );
}

/// What a brand-new account starts with: categories only, calendar-month cycles.
AppState emptyState() => AppState(
      config: const Config(cycleStartDay: 1, openingBalance: 0),
      categories: [...categories],
      recurring: [],
      movements: [],
    );
