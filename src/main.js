import * as store from './store.js';
import {
  computeCycles, cashNow, cycleIdOf, cycleLabel, fmtCents, formatDay, parseISO, todayISO,
} from './logic.js';

// ---------- tiny helpers ----------
const $app = document.getElementById('app');
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const WEEKDAYS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
const weekday = (iso) => { const { y, m, d } = parseISO(iso); return WEEKDAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]; };

const ICON = {
  home: '<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  list: '<path d="M4 6h16M4 12h16M4 18h10"/>',
  chart: '<path d="M5 20v-6M12 20V4M19 20v-9"/>',
  repeat: '<path d="M17 2l4 4-4 4M3 11V9a3 3 0 0 1 3-3h15M7 22l-4-4 4-4M21 13v2a3 3 0 0 1-3 3H3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  sliders: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  chevron: '<path d="M6 9l6 6 6-6"/>',
  back: '<path d="M15 6l-6 6 6 6"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>',
};
const svg = (name, size = 22, sw = 1.7) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON[name]}</svg>`;

// ---------- UI state (not persisted, except the chosen cycle) ----------
const ui = {
  cycle: null,
  filter: 'Todos',
  sheet: null, // movement id with the action sheet open
  nova: null,
  toast: '',
};

function resetNova() {
  ui.nova = { cents: 0, cat: 'Alimentação', estado: 'Pago', desc: '', date: todayISO() };
}
resetNova();

function model() {
  const state = store.get();
  const today = todayISO();
  const cycles = computeCycles(state, today);
  if (!ui.cycle || !cycles.some((c) => c.id === ui.cycle)) {
    // today's cycle, unless it is empty: then the next cycle that has movements
    const todayId = cycleIdOf(today, state.config.cycleStartDay);
    const withItems = cycles.find((c) => c.id >= todayId && c.items.length > 0);
    const cur = cycles.find((c) => c.id === todayId);
    ui.cycle = (cur && cur.items.length > 0) || !withItems ? todayId : withItems.id;
  }
  const cycle = cycles.find((c) => c.id === ui.cycle);
  const colors = Object.fromEntries(state.categories.map((c) => [c.name, c.color]));
  const types = Object.fromEntries(state.categories.map((c) => [c.name, c.type]));
  return { state, today, cycles, cycle, colors, types };
}

// ---------- shared pieces ----------
function tabbar(active) {
  const tabs = [
    ['#/', 'home', 'Início'], ['#/movimentos', 'list', 'Movimentos'],
    ['#/previsao', 'chart', 'Previsão'], ['#/fixas', 'repeat', 'Fixas'],
  ];
  return `<nav class="tabbar" aria-label="Navegação">${tabs.map(([href, icon, label]) =>
    `<a class="tab${active === href ? ' on' : ''}" href="${href}"${active === href ? ' aria-current="page"' : ''}>${svg(icon)}${label}</a>`).join('')}</nav>`;
}
const fab = () => `<a class="fab" href="#/nova" aria-label="Nova despesa">${svg('plus', 24, 2.2)}</a>`;

function cyclePicker(m) {
  const opts = m.cycles.map((c) => `<option value="${c.id}"${c.id === m.cycle.id ? ' selected' : ''}>${esc(c.label)} · ${formatDay(c.start)} – ${formatDay(c.end)}</option>`).join('');
  return `<label class="pill-btn">
    <span class="mono">${formatDay(m.cycle.start)} – ${formatDay(m.cycle.end)}</span>
    <span style="color:var(--muted)">${svg('chevron', 14, 2)}</span>
    <select data-action="cycle" aria-label="Escolher ciclo">${opts}</select>
  </label>`;
}

function movementRow(mv, m, { showDate = false } = {}) {
  const income = m.types[mv.category] === 'Entrada';
  const amt = income ? `+${fmtCents(mv.cents)}` : `−${fmtCents(mv.cents)}`;
  const paid = mv.estado === 'Pago';
  return `<button type="button" class="row" data-action="open-sheet" data-id="${esc(mv.id)}">
    <span class="dot" style="background:${m.colors[mv.category] || '#9A9AA1'}"></span>
    <span class="grow"><span class="r-title">${esc(mv.description)}</span><span class="r-sub">${esc(mv.category)}${showDate ? ` · ${formatDay(mv.date)}` : ''}</span></span>
    <span class="r-right"><span class="mono r-amt${income ? ' income' : ''}">${amt}</span><span class="tag ${paid ? 'paid' : 'planned'}">${paid ? 'PAGO' : 'PREVISTO'}</span></span>
  </button>`;
}

// ---------- screens ----------
function viewHome(m) {
  const c = m.cycle;
  const pct = (v) => (c.receitas > 0 ? Math.min(100, Math.round((v / c.receitas) * 100)) : 0);
  const upcoming = c.items
    .filter((x) => m.types[x.category] !== 'Entrada' && x.estado === 'Previsto' && x.date >= m.today)
    .slice(0, 3);
  const empty = c.items.length === 0;
  return `<div class="screen">
    <div class="top">${cyclePicker(m)}<a class="icon-btn" href="#/ajustes" aria-label="Ajustes">${svg('sliders')}</a></div>
    <div class="hero">
      <div class="lbl">Sobra do ciclo</div>
      <div class="big"><span class="num${c.sobra < 0 ? ' neg' : ''}">${fmtCents(c.sobra)}</span><span class="cur">€</span></div>
      <div class="hint">${empty ? 'Ainda sem movimentos neste ciclo' : `${c.savingsRate}% da receita`} · hoje, ${formatDay(m.today)}</div>
    </div>
    <div class="meter"><div class="track"><i style="width:${pct(c.pago)}%;background:var(--accent)"></i><i style="width:${Math.max(0, pct(c.pago + c.porPagar) - pct(c.pago))}%;background:#3A3A40"></i></div>
      <div class="meter-l"><span><b style="color:var(--accent)">●</b> Pago ${pct(c.pago)}%</span><span>Por pagar ${pct(c.pago + c.porPagar) - pct(c.pago)}%</span></div></div>
    <div class="grid2">
      <div><div class="lbl">Receitas</div><div class="mono g-v">${fmtCents(c.receitas)}</div></div>
      <div><div class="lbl">Despesas</div><div class="mono g-v neg">${fmtCents(c.despesas)}</div></div>
      <div><div class="lbl">Em conta</div><div class="mono g-v">${fmtCents(cashNow(m.state))}</div></div>
      <div><div class="lbl">Mais baixo</div><div class="mono g-v">${fmtCents(c.lowest)}</div></div>
    </div>
    <div class="sec"><h2>Próximos pagamentos</h2><a href="#/movimentos">Ver todos</a></div>
    ${upcoming.length ? upcoming.map((x) => `<div class="row static"><span class="dot" style="background:${m.colors[x.category] || '#9A9AA1'}"></span><span class="grow r-title">${esc(x.description)}</span><span class="mono r-date">${formatDay(x.date)}</span><span class="mono r-amt w78">${fmtCents(x.cents)}</span></div>`).join('') : '<p class="empty">Nada por pagar a partir de hoje.</p>'}
  </div>${fab()}${tabbar('#/')}`;
}

function viewMovimentos(m) {
  const c = m.cycle;
  const items = c.items.filter((x) => ui.filter === 'Todos' || x.estado === ui.filter);
  const groups = [];
  for (const it of items) {
    const g = groups[groups.length - 1];
    if (g && g.date === it.date) g.items.push(it); else groups.push({ date: it.date, items: [it] });
  }
  const chips = ['Todos', 'Pago', 'Previsto'].map((f) => `<button type="button" class="chip${ui.filter === f ? ' on' : ''}" data-action="filter" data-v="${f}">${f}</button>`).join('');
  return `<div class="screen">
    <div class="top"><h1>Movimentos</h1>${cyclePicker(m)}</div>
    <div class="mono sub">${esc(c.label)} · ${c.items.length} movimento${c.items.length === 1 ? '' : 's'}</div>
    <div class="chips">${chips}</div>
    ${groups.length ? groups.map((g) => `<div class="day"><div class="lbl">${formatDay(g.date)} · ${weekday(g.date)}</div>${g.items.map((x) => movementRow(x, m)).join('')}</div>`).join('') : '<p class="empty">Sem movimentos para mostrar.</p>'}
  </div>${fab()}${tabbar('#/movimentos')}`;
}

function viewNova(m) {
  const n = ui.nova;
  const cats = m.state.categories.filter((c) => c.type === 'Saída');
  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', 'back'];
  return `<div class="screen nova">
    <div class="top center"><a class="icon-btn" href="#/" aria-label="Fechar">${svg('close', 22, 1.8)}</a><div class="t">Nova despesa</div><span style="width:44px"></span></div>
    <div class="amount"><span class="mono" id="amount">${fmtCents(n.cents)}</span><span class="cur">€</span></div>
    <div class="field"><label for="desc" class="lbl">Descrição</label><input id="desc" type="text" placeholder="Ex.: Supermercado" value="${esc(n.desc)}" autocomplete="off" enterkeyhint="done"></div>
    <div class="chips wrap">${cats.map((c) => `<button type="button" class="chip${n.cat === c.name ? ' on' : ''}" data-action="nova-cat" data-v="${esc(c.name)}">${esc(c.name)}</button>`).join('')}</div>
    <div class="two">
      <label class="date-btn">${svg('calendar', 16, 1.8)}<span id="date-text">${n.date === m.today ? 'Hoje, ' : ''}${formatDay(n.date)}</span><input type="date" id="date" value="${n.date}" aria-label="Data"></label>
      <div class="seg-wrap">${['Pago', 'Previsto'].map((e) => `<button type="button" class="seg${n.estado === e ? ' on' : ''}" data-action="nova-estado" data-v="${e}">${e}</button>`).join('')}</div>
    </div>
    <div class="bottom">
      <div class="keys">${keys.map((k) => k === 'back'
        ? `<button type="button" class="key" data-action="key" data-v="back" aria-label="Apagar">${svg('back', 22, 1.8)}</button>`
        : `<button type="button" class="key" data-action="key" data-v="${k}">${k}</button>`).join('')}</div>
      <button type="button" class="add" data-action="nova-save">Adicionar despesa</button>
    </div>
  </div>`;
}

function viewPrevisao(m) {
  const plan = m.cycles.filter((c) => c.items.length > 0);
  const last = plan[plan.length - 1] || m.cycle;
  const bars = plan.slice(0, 7);
  const max = Math.max(1, ...bars.map((c) => Math.abs(c.sobra)));
  return `<div class="screen">
    <div class="top"><h1>Previsão</h1></div>
    <div class="mono sub">${plan.length} ciclos · ${plan.length ? `${esc(plan[0].label)} – ${esc(last.label)}` : ''}</div>
    <div class="hero" style="margin-top:26px">
      <div class="lbl">Saldo acumulado em ${esc(cycleLabel(last.id).toLowerCase())}</div>
      <div class="big"><span class="num mid">${fmtCents(last.endBalance)}</span><span class="cur">€</span></div>
    </div>
    <div class="lbl" style="margin:26px 0 14px">Sobra por ciclo</div>
    <div class="bars">${bars.map((c) => `<button type="button" class="bar" data-action="pick-cycle" data-id="${c.id}"><i style="height:${Math.max(4, Math.round((Math.abs(c.sobra) / max) * 120))}px;background:${c.id === m.cycle.id ? 'var(--accent)' : '#2A2A2F'}"></i><span${c.id === m.cycle.id ? ' style="color:var(--text)"' : ''}>${esc(cycleLabel(c.id).slice(0, 3))}</span></button>`).join('')}</div>
    <div class="table">
      <div class="th lbl"><div>Ciclo</div><div>Entra</div><div>Sai</div><div>Sobra</div></div>
      ${plan.map((c) => `<div class="tr mono"><div class="t-name">${esc(c.label)}</div><div>${fmtCents(c.receitas)}</div><div class="neg">${fmtCents(c.despesas)}</div><div>${fmtCents(c.sobra)}</div></div>`).join('')}
    </div>
  </div>${tabbar('#/previsao')}`;
}

function viewFixas(m) {
  const rec = [...m.state.recurring].sort((a, b) => a.day - b.day);
  const now = cycleIdOf(m.today, m.state.config.cycleStartDay);
  const active = rec.filter((r) => (!r.to || r.to >= now));
  const out = active.filter((r) => m.types[r.category] !== 'Entrada').reduce((a, r) => a + r.cents, 0);
  const inn = active.filter((r) => m.types[r.category] === 'Entrada').reduce((a, r) => a + r.cents, 0);
  return `<div class="screen">
    <div class="top"><h1>Contas fixas</h1></div>
    <div class="strip"><div><div class="lbl">Sai por mês</div><div class="mono s-v">${fmtCents(out)}</div></div><div class="sep"><div class="lbl">Entra por mês</div><div class="mono s-v income">${fmtCents(inn)}</div></div></div>
    <div class="lbl" style="margin-top:24px">Por dia do mês</div>
    <div style="margin-top:6px">${rec.map((r) => {
      const income = m.types[r.category] === 'Entrada';
      const ended = r.to && r.to < now;
      return `<div class="row static${ended ? ' ended' : ''}"><span class="daybox mono">${r.day}</span><span class="grow r-title">${esc(r.description)}${r.variable ? '<span class="pill">Variável</span>' : ''}${r.to ? `<span class="pill">até ${esc(cycleLabel(r.to).slice(0, 3).toLowerCase())}</span>` : ''}</span><span class="mono r-amt${income ? ' income' : ''}">${income ? '+' : ''}${fmtCents(r.cents)}</span></div>`;
    }).join('')}</div>
    <p class="note">Por agora as contas fixas só se consultam. Editá-las vem na próxima versão.</p>
  </div>${tabbar('#/fixas')}`;
}

function viewAjustes(m) {
  return `<div class="screen">
    <div class="top"><a class="icon-btn" href="#/" aria-label="Voltar" style="margin-left:-12px">${svg('back', 22, 1.8)}</a><h1 style="font-size:20px">Ajustes</h1><span style="width:44px"></span></div>
    <div class="settings">
      <div class="s-row"><div><div class="r-title">Dia de início do ciclo</div><div class="r-sub">Os ciclos começam no dia ${m.state.config.cycleStartDay}</div></div></div>
      <button type="button" class="s-row btn" data-action="export"><div><div class="r-title">Exportar dados</div><div class="r-sub">Guarda uma cópia (.json) no telemóvel</div></div></button>
      <label class="s-row btn"><div><div class="r-title">Importar dados</div><div class="r-sub">Repõe uma cópia exportada antes</div></div><input type="file" accept="application/json,.json" data-action="import" hidden></label>
      <button type="button" class="s-row btn danger" data-action="reset"><div><div class="r-title">Repor dados de exemplo</div><div class="r-sub">Apaga os teus movimentos e volta ao início</div></div></button>
    </div>
    <p class="note">Os dados ficam só neste telemóvel. Exporta uma cópia de vez em quando.</p>
  </div>${tabbar('')}`;
}

const ROUTES = {
  '#/': viewHome, '#/movimentos': viewMovimentos, '#/nova': viewNova,
  '#/previsao': viewPrevisao, '#/fixas': viewFixas, '#/ajustes': viewAjustes,
};

// ---------- render ----------
function sheetHtml(m) {
  if (!ui.sheet) return '';
  const mv = m.state.movements.find((x) => x.id === ui.sheet);
  if (!mv) return '';
  const income = m.types[mv.category] === 'Entrada';
  return `<div class="scrim" data-action="close-sheet"><div class="sheet" role="dialog" aria-label="Movimento" data-stop>
    <div class="sheet-h"><div class="r-title">${esc(mv.description)}</div><div class="r-sub">${esc(mv.category)} · ${formatDay(mv.date)} · ${income ? '+' : '−'}${fmtCents(mv.cents)} €</div></div>
    <button type="button" class="sheet-b" data-action="toggle-estado" data-id="${esc(mv.id)}">${mv.estado === 'Pago' ? 'Marcar como previsto' : (income ? 'Marcar como recebido' : 'Marcar como pago')}</button>
    <button type="button" class="sheet-b danger" data-action="delete" data-id="${esc(mv.id)}">Apagar</button>
    <button type="button" class="sheet-b" data-action="close-sheet">Fechar</button>
  </div></div>`;
}

function render() {
  const hash = ROUTES[location.hash] ? location.hash : '#/';
  const m = model();
  $app.innerHTML = ROUTES[hash](m) + sheetHtml(m) + (ui.toast ? `<div class="toast" role="status">${esc(ui.toast)}</div>` : '');
  if (hash !== '#/nova') window.scrollTo(0, 0);
}

function showToast(text) {
  ui.toast = text;
  render();
  setTimeout(() => { ui.toast = ''; render(); }, 1600);
}

// ---------- events ----------
$app.addEventListener('click', (e) => {
  const el = e.target.closest('[data-action]');
  if (!el || el.tagName === 'SELECT' || el.tagName === 'INPUT') return;
  const { action, v, id } = el.dataset;
  if (action === 'close-sheet') {
    if (el.classList.contains('scrim') && e.target !== el) return;
    ui.sheet = null; return render();
  }
  switch (action) {
    case 'filter': ui.filter = v; break;
    case 'open-sheet': ui.sheet = id; break;
    case 'toggle-estado': {
      const mv = store.get().movements.find((x) => x.id === id);
      if (mv) store.setEstado(id, mv.estado === 'Pago' ? 'Previsto' : 'Pago');
      ui.sheet = null; break;
    }
    case 'delete':
      if (confirm('Apagar este movimento?')) { store.removeMovement(id); ui.sheet = null; } else return;
      break;
    case 'pick-cycle': ui.cycle = id; break;
    case 'nova-cat': ui.nova.cat = v; break;
    case 'nova-estado': ui.nova.estado = v; break;
    case 'key': {
      const n = ui.nova;
      if (v === 'back') n.cents = Math.floor(n.cents / 10);
      else n.cents = Math.min(n.cents * (v === '00' ? 100 : 10) + (v === '00' ? 0 : Number(v)), 99999999);
      document.getElementById('amount').textContent = fmtCents(n.cents);
      return; // no full re-render: keeps the keypad snappy
    }
    case 'nova-save': {
      const n = ui.nova;
      if (n.cents <= 0) { showToast('Indica um valor.'); return; }
      const desc = (document.getElementById('desc')?.value || n.desc).trim() || n.cat;
      store.addMovement({ date: n.date, description: desc, category: n.cat, cents: n.cents, estado: n.estado });
      ui.cycle = cycleIdOf(n.date, store.get().config.cycleStartDay);
      resetNova();
      location.hash = '#/';
      showToast('Despesa adicionada');
      return;
    }
    case 'export': {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([store.exportJSON()], { type: 'application/json' }));
      a.download = `fin_app_${todayISO()}.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      return;
    }
    case 'reset':
      if (confirm('Repor os dados de exemplo? Os teus movimentos serão apagados.')) { store.resetToSeed(); ui.cycle = null; showToast('Dados repostos'); }
      return;
    default: return;
  }
  render();
});

$app.addEventListener('change', async (e) => {
  const t = e.target;
  if (t.dataset.action === 'cycle') { ui.cycle = t.value; render(); }
  else if (t.id === 'date') {
    if (t.value) { ui.nova.date = t.value; const m = model(); document.getElementById('date-text').textContent = `${t.value === m.today ? 'Hoje, ' : ''}${formatDay(t.value)}`; }
  } else if (t.dataset.action === 'import' && t.files[0]) {
    try { store.importJSON(await t.files[0].text()); ui.cycle = null; showToast('Dados importados'); }
    catch { showToast('Ficheiro inválido'); }
  }
});

$app.addEventListener('input', (e) => { if (e.target.id === 'desc') ui.nova.desc = e.target.value; });

window.addEventListener('hashchange', () => { ui.sheet = null; render(); });

// ---------- boot ----------
store.load();
render();

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
