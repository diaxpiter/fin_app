// Starting data, copied from the "Financial - Davi" Google Sheet.
// Used on first launch and by "Repor dados de exemplo" in Ajustes.
import { cycleRange, expandRecurring } from './logic.js';

export const CATEGORIES = [
  { name: 'Receita', type: 'Entrada', color: '#C8F169' },
  { name: 'Moradia', type: 'Saída', color: '#7AA2F7' },
  { name: 'Alimentação', type: 'Saída', color: '#E9B44C' },
  { name: 'Subscrição', type: 'Saída', color: '#B58CF5' },
  { name: 'Crédito', type: 'Saída', color: '#FF7A64' },
  { name: 'Lazer', type: 'Saída', color: '#5FD0A5' },
  { name: 'Outros', type: 'Saída', color: '#9A9AA1' },
];

// Contas fixas. `from` / `to` are cycle ids (the month the cycle ends in).
export const RECURRING = [
  { id: 'sal', description: 'Salário', category: 'Receita', cents: 163057, day: 25, variable: true, from: '2026-11' },
  { id: 'renda', description: 'Renda', category: 'Moradia', cents: 25000, day: 25, from: '2026-11' },
  { id: 'agua', description: 'Água', category: 'Moradia', cents: 3500, day: 25, variable: true, from: '2026-11' },
  { id: 'luz', description: 'Luz', category: 'Moradia', cents: 5000, day: 25, variable: true, from: '2026-11' },
  { id: 'tel', description: 'Telemóvel', category: 'Moradia', cents: 4223, day: 25, from: '2026-11' },
  { id: 'net', description: 'Internet', category: 'Moradia', cents: 2865, day: 25, from: '2026-11' },
  { id: 'klarna', description: 'Klarna', category: 'Crédito', cents: 34709, day: 25, variable: true, from: '2026-11', to: '2026-11' },
  { id: 'cred', description: 'Crédito', category: 'Crédito', cents: 9536, day: 11, from: '2026-11', to: '2026-11' },
  { id: 'gin1', description: 'Ginásio 1/2', category: 'Subscrição', cents: 1960, day: 27, from: '2026-11' },
  { id: 'gin2', description: 'Ginásio 2/2', category: 'Subscrição', cents: 1960, day: 11, from: '2026-11' },
  { id: 'icloud', description: 'iCloud', category: 'Subscrição', cents: 99, day: 11, from: '2026-11' },
  { id: 'crunchy', description: 'Crunchyroll', category: 'Subscrição', cents: 999, day: 11, from: '2026-11' },
];

// The first cycle (23 Oct – 22 Nov 2026) was entered by hand in the sheet.
const FIRST_CYCLE = [
  ['2026-10-23', 'Salário', 'Receita', 113757],
  ['2026-10-23', 'Renda', 'Moradia', 25000],
  ['2026-10-23', 'Água', 'Moradia', 3500],
  ['2026-10-23', 'Luz', 'Moradia', 5000],
  ['2026-10-23', 'Telemóvel', 'Moradia', 4223],
  ['2026-10-23', 'Internet', 'Moradia', 2865],
  ['2026-10-23', 'Klarna', 'Crédito', 34709],
  ['2026-10-30', 'Ginásio 1/2', 'Subscrição', 1960],
  ['2026-11-10', 'iCloud', 'Subscrição', 99],
  ['2026-11-11', 'Crunchyroll', 'Subscrição', 999],
  ['2026-11-11', 'Crédito', 'Crédito', 9536],
  ['2026-11-13', 'Ginásio 2/2', 'Subscrição', 1960],
].map(([date, description, category, cents], i) => ({
  id: `seed:${i}`, date, description, category, cents, estado: 'Previsto',
}));

export function seedState() {
  const config = { cycleStartDay: 23, openingBalance: 0 };
  const ids = cycleRange('2026-12', '2027-10');
  // salary in Jan 2027 is lower in the sheet (10 660,00 → 1.066,00 €)
  const overrides = { 'sal:2027-01': 106600 };
  return {
    version: 1,
    config,
    categories: CATEGORIES,
    recurring: RECURRING,
    movements: [...FIRST_CYCLE, ...expandRecurring(RECURRING, ids, config.cycleStartDay, overrides)],
  };
}
