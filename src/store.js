// Persistence: one JSON document in localStorage. Swap this module for a
// remote backend later without touching the UI.
import { seedState } from './seed.js';

const KEY = 'fin_app_v1';
let state = null;
const listeners = new Set();

function safeGet() {
  try { return localStorage.getItem(KEY); } catch { return null; }
}
function safeSet(v) {
  try { localStorage.setItem(KEY, v); return true; } catch { return false; }
}

function isValid(s) {
  return s && s.version === 1 && s.config && Array.isArray(s.categories) &&
    Array.isArray(s.recurring) && Array.isArray(s.movements);
}

export function load() {
  const raw = safeGet();
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (isValid(parsed)) return (state = parsed);
    } catch { /* fall through to seed */ }
  }
  state = seedState();
  safeSet(JSON.stringify(state));
  return state;
}

export const get = () => state;
export const subscribe = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };

function commit() {
  safeSet(JSON.stringify(state));
  listeners.forEach((fn) => fn(state));
}

export function addMovement({ date, description, category, cents, estado }) {
  const id = `m:${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  state.movements.push({ id, date, description, category, cents, estado });
  commit();
  return id;
}

export function setEstado(id, estado) {
  const m = state.movements.find((x) => x.id === id);
  if (m) { m.estado = estado; commit(); }
}

export function removeMovement(id) {
  state.movements = state.movements.filter((x) => x.id !== id);
  commit();
}

export function exportJSON() {
  return JSON.stringify(state, null, 2);
}

export function importJSON(text) {
  const parsed = JSON.parse(text);
  if (!isValid(parsed)) throw new Error('Ficheiro inválido.');
  state = parsed;
  commit();
}

export function resetToSeed() {
  state = seedState();
  commit();
}
