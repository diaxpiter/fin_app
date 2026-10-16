import test from 'node:test';
import assert from 'node:assert/strict';
import { computeCycles, cycleIdOf, cycleBounds, fmtCents, parseMoney, cashNow, occurrenceDate } from '../src/logic.js';
import { seedState } from '../src/seed.js';

test('cycle ids and bounds (start day 23)', () => {
  assert.equal(cycleIdOf('2026-10-23', 23), '2026-11');
  assert.equal(cycleIdOf('2026-11-22', 23), '2026-11');
  assert.equal(cycleIdOf('2026-11-23', 23), '2026-12');
  assert.equal(cycleIdOf('2026-10-16', 23), '2026-10');
  assert.deepEqual(cycleBounds('2026-11', 23), { start: '2026-10-23', end: '2026-11-22' });
  assert.deepEqual(cycleBounds('2027-01', 23), { start: '2026-12-23', end: '2027-01-22' });
});

test('calendar-month cycles when start day is 1', () => {
  assert.equal(cycleIdOf('2026-03-15', 1), '2026-03');
  assert.deepEqual(cycleBounds('2026-02', 1), { start: '2026-02-01', end: '2026-02-28' });
});

test('recurring occurrence lands inside its cycle', () => {
  assert.equal(occurrenceDate(25, '2026-12', 23), '2026-11-25');
  assert.equal(occurrenceDate(11, '2026-12', 23), '2026-12-11');
  assert.equal(occurrenceDate(27, '2026-12', 23), '2026-11-27');
});

test('money formatting and parsing', () => {
  assert.equal(fmtCents(113757), '1.137,57');
  assert.equal(fmtCents(-25000), '−250,00');
  assert.equal(fmtCents(5, { sign: true }), '+0,05');
  assert.equal(parseMoney('1.137,57'), 113757);
  assert.equal(parseMoney('35'), 3500);
});

// The numbers below are what the Google Sheet shows (Painel + Previsão tabs).
test('first cycle matches the sheet', () => {
  const cycles = computeCycles(seedState(), '2026-10-15');
  const nov = cycles.find((c) => c.id === '2026-11');
  assert.equal(nov.receitas, 113757);
  assert.equal(nov.despesas, 89851);
  assert.equal(nov.sobra, 23906);
  assert.equal(nov.porPagar, 89851);
  assert.equal(nov.pago, 0);
  assert.equal(nov.savingsRate, 21);
  assert.equal(nov.lowest, 23906);
  assert.equal(nov.lowestDate, '2026-11-13');
});

test('forecast matches the sheet', () => {
  const cycles = computeCycles(seedState(), '2026-10-15');
  const by = Object.fromEntries(cycles.map((c) => [c.id, c]));
  assert.equal(by['2026-12'].receitas, 163057);
  assert.equal(by['2026-12'].despesas, 45606);
  assert.equal(by['2026-12'].sobra, 117451);
  assert.equal(by['2026-12'].endBalance, 141357);
  assert.equal(by['2027-01'].receitas, 106600);
  assert.equal(by['2027-01'].sobra, 60994);
  assert.equal(by['2027-01'].endBalance, 202351);
  assert.equal(by['2027-06'].endBalance, 789606);
});

test('cash in account only counts movements marked Pago', () => {
  const s = seedState();
  assert.equal(cashNow(s), 0);
  s.movements.find((m) => m.description === 'Salário').estado = 'Pago';
  assert.equal(cashNow(s), 113757);
});

test("today's cycle is listed even before the plan starts", () => {
  const cycles = computeCycles(seedState(), '2026-10-16');
  assert.equal(cycles[0].id, '2026-10');
  assert.equal(cycles[0].items.length, 0);
});
