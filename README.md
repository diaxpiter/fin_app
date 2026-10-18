# Painel Financeiro (fin_app)

A personal finance web app for iPhone. It installs from Safari to the Home Screen (no App Store), works offline, and keeps your data on the phone.

It is built from the "Financial - Davi" Google Sheet: money is organised in **cycles that start on the 23rd** (23 Oct – 22 Nov is the "Nov" cycle), with recurring bills, a forecast, and quick expense entry.

A Flutter version of the same app is in [`flutter_app/`](flutter_app/README.md). It runs natively on Android, iOS, web and desktop, and its layout adapts from small phones to wide desktop windows.

## Screens

| Screen | What it does |
| --- | --- |
| Início | Balance left over in the cycle, paid vs. still to pay, cash in account, lowest balance, next payments |
| Movimentos | Every movement of the cycle, grouped by day. Tap one to mark it paid/planned or delete it |
| Nova despesa | Keypad, category, date, Pago/Previsto. The + button on Início and Movimentos opens it |
| Previsão | Balance per cycle and accumulated balance for the whole plan |
| Fixas | Recurring bills (read-only for now) |
| Ajustes | Export / import a backup, reset to the example data |

## Run it

No build step, no dependencies. Any static server works:

```sh
python3 -m http.server 8000
# open http://localhost:8000
```

Tests (Node 20+):

```sh
node --test test/logic.test.mjs
```

The tests check the cycle maths against the numbers in the Google Sheet (cycle totals, savings rate, accumulated balance through Jun 2027).

## Put it on your iPhone

The site is the Flutter app, built and deployed by [`.github/workflows/pages.yml`](.github/workflows/pages.yml) on every push to `main` (tests run first; a failing test blocks the deploy).

1. One time: repo **Settings → Pages → Source: GitHub Actions**.
2. Push to `main`, wait for the "Deploy to GitHub Pages" run (Actions tab, ~3 min).
3. Open `https://diaxpiter.github.io/fin_app/` in **Safari** on the iPhone (or Chrome on Android).
4. Share → **Add to Home Screen**.

It must be opened from the Home Screen icon to run full-screen like an app.

## How it is organised

```
index.html            app shell + PWA meta tags
styles.css            all styling (dark theme, one lime accent)
src/logic.js          pure finance logic (cycles, recurring bills, totals) — tested
src/seed.js           starting data copied from the sheet
src/store.js          persistence (localStorage). Swap this file to change the backend
src/main.js           screens, routing, events
sw.js                 offline cache
manifest.webmanifest  install info and icons
```

Money is stored as integer cents. Dates are plain `YYYY-MM-DD` strings (no time-zone surprises). A cycle id is the month the cycle ends in (`2026-11` = 23 Oct – 22 Nov).

## Known limits and next steps

- Data lives in the phone's browser storage only. Use **Ajustes → Exportar dados** now and then. A real backend (sync between devices, or reading the Google Sheet) is the next big decision.
- Recurring bills can't be edited in the app yet, and changing one doesn't regenerate future movements.
- Editing a movement's amount or description isn't built; delete and re-add for now.
- The start day (23) and opening balance are fixed in `src/seed.js` until there is a settings form.
