// Pure finance logic: cycles, recurring-bill expansion, totals.
// No DOM, no storage — everything here is unit-tested in test/logic.test.mjs.
// Money is handled in integer cents to avoid floating-point drift.

export const pad = (n) => String(n).padStart(2, '0');
export const iso = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;

export function parseISO(s) {
  const [y, m, d] = s.split('-').map(Number);
  return { y, m, d };
}

export function addMonths(y, m, n) {
  const t = y * 12 + (m - 1) + n;
  return { y: Math.floor(t / 12), m: (t % 12) + 1 };
}

export const daysInMonth = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();

export function todayISO(now = new Date()) {
  return iso(now.getFullYear(), now.getMonth() + 1, now.getDate());
}

// ---- Cycles -----------------------------------------------------------
// A cycle starts on `startDay` and ends the day before the next start.
// Its id is "YYYY-MM" of the month in which it ENDS (23 Oct–22 Nov = "2026-11").
// With startDay = 1 it is simply the calendar month.

export function cycleIdOf(dateISO, startDay) {
  const { y, m, d } = parseISO(dateISO);
  const start = d >= startDay ? { y, m } : addMonths(y, m, -1);
  const end = startDay === 1 ? start : addMonths(start.y, start.m, 1);
  return `${end.y}-${pad(end.m)}`;
}

export function cycleBounds(id, startDay) {
  const [ey, em] = id.split('-').map(Number);
  const s = startDay === 1 ? { y: ey, m: em } : addMonths(ey, em, -1);
  const start = iso(s.y, s.m, startDay);
  const nextStart = addMonths(s.y, s.m, 1);
  const endDate = new Date(Date.UTC(nextStart.y, nextStart.m - 1, startDay - 1));
  const end = iso(endDate.getUTCFullYear(), endDate.getUTCMonth() + 1, endDate.getUTCDate());
  return { start, end };
}

export function nextCycleId(id, n = 1) {
  const [y, m] = id.split('-').map(Number);
  const r = addMonths(y, m, n);
  return `${r.y}-${pad(r.m)}`;
}

export function cycleRange(fromId, toId) {
  const out = [];
  let id = fromId;
  while (id <= toId && out.length < 240) {
    out.push(id);
    id = nextCycleId(id);
  }
  return out;
}

const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
export const monthShort = (m) => MONTHS[m - 1];

export function cycleLabel(id) {
  const [y, m] = id.split('-').map(Number);
  const s = MONTHS[m - 1];
  return `${s[0].toUpperCase()}${s.slice(1)} ${y}`;
}

export function formatDay(dateISO) {
  const { d, m } = parseISO(dateISO);
  return `${d} ${monthShort(m)}`;
}

// ---- Money ------------------------------------------------------------

export function fmtCents(c, { sign = false } = {}) {
  const abs = Math.abs(c);
  const euros = Math.floor(abs / 100);
  const dec = pad(abs % 100);
  const grouped = String(euros).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const s = `${grouped},${dec}`;
  if (c < 0) return `−${s}`;
  return sign && c > 0 ? `+${s}` : s;
}

export function parseMoney(str) {
  const n = Number(String(str).replace(/\./g, '').replace(',', '.'));
  return Number.isFinite(n) ? Math.round(n * 100) : NaN;
}

// ---- Recurring bills -> movements ------------------------------------

export function occurrenceDate(day, cycleId, startDay) {
  const [ey, em] = cycleId.split('-').map(Number);
  const s = startDay === 1 ? { y: ey, m: em } : addMonths(ey, em, -1);
  const t = startDay === 1 || day >= startDay ? s : addMonths(s.y, s.m, 1);
  return iso(t.y, t.m, Math.min(day, daysInMonth(t.y, t.m)));
}

// recurring item: { id, description, category, cents, day, from?: 'YYYY-MM', to?: 'YYYY-MM' }
// `from`/`to` are cycle ids (inclusive). `overrides` maps "recId:cycleId" -> cents.
export function expandRecurring(recurring, cycleIds, startDay, overrides = {}) {
  const out = [];
  for (const cycleId of cycleIds) {
    for (const r of recurring) {
      if (r.from && cycleId < r.from) continue;
      if (r.to && cycleId > r.to) continue;
      const key = `${r.id}:${cycleId}`;
      out.push({
        id: `gen:${key}`,
        date: occurrenceDate(r.day, cycleId, startDay),
        description: r.description,
        category: r.category,
        cents: key in overrides ? overrides[key] : r.cents,
        estado: 'Previsto',
        gen: true,
      });
    }
  }
  return out;
}

// ---- Totals -----------------------------------------------------------

const isIncome = (m, types) => types[m.category] === 'Entrada';
export const signed = (m, types) => (isIncome(m, types) ? m.cents : -m.cents);

export function sortMovements(list, types) {
  // by date; within a day income first so running balances never dip artificially
  return [...list].sort(
    (a, b) =>
      a.date.localeCompare(b.date) ||
      Number(isIncome(b, types)) - Number(isIncome(a, types)) ||
      a.description.localeCompare(b.description, 'pt')
  );
}

export function computeCycles(state, today = todayISO()) {
  const { config, categories, movements } = state;
  const S = config.cycleStartDay;
  const types = Object.fromEntries(categories.map((c) => [c.name, c.type]));

  const ids = new Set([cycleIdOf(today, S)]);
  for (const m of movements) ids.add(cycleIdOf(m.date, S));
  const sorted = [...ids].sort();
  const all = cycleRange(sorted[0], sorted[sorted.length - 1]);

  const byCycle = new Map(all.map((id) => [id, []]));
  for (const m of movements) byCycle.get(cycleIdOf(m.date, S)).push(m);

  let balance = config.openingBalance;
  return all.map((id) => {
    const items = sortMovements(byCycle.get(id), types);
    let receitas = 0, despesas = 0, pago = 0, porPagar = 0;
    for (const m of items) {
      if (isIncome(m, types)) receitas += m.cents;
      else {
        despesas += m.cents;
        if (m.estado === 'Pago') pago += m.cents;
        else porPagar += m.cents;
      }
    }
    const startBalance = balance;
    // lowest END-OF-DAY balance inside the cycle
    let run = startBalance, lowest = startBalance, lowestDate = null;
    for (let i = 0; i < items.length; i++) {
      run += signed(items[i], types);
      const last = i === items.length - 1 || items[i + 1].date !== items[i].date;
      if (last && (lowestDate === null || run < lowest)) {
        lowest = run;
        lowestDate = items[i].date;
      }
    }
    const sobra = receitas - despesas;
    balance += sobra;
    return {
      id, label: cycleLabel(id), ...cycleBounds(id, S), items,
      receitas, despesas, sobra, pago, porPagar,
      startBalance, endBalance: balance,
      lowest: lowestDate === null ? startBalance : lowest, lowestDate,
      savingsRate: receitas > 0 ? Math.round((sobra / receitas) * 100) : 0,
    };
  });
}

// money actually in the account: opening balance + every movement marked Pago
export function cashNow(state) {
  const types = Object.fromEntries(state.categories.map((c) => [c.name, c.type]));
  return state.movements
    .filter((m) => m.estado === 'Pago')
    .reduce((acc, m) => acc + signed(m, types), state.config.openingBalance);
}
