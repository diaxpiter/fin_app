# Painel Financeiro (fin_app)

A personal finance app built with Flutter. It runs on Android, iOS, web and desktop, installs to the iPhone Home Screen from Safari (no App Store), and works offline.

It started from the "Financial - Davi" Google Sheet: money is organised in **cycles that start on a day you choose** (23 Oct – 22 Nov is the "Nov" cycle), with fixed bills, several accounts, a forecast and quick expense entry. Details of the app itself are in [`flutter_app/`](flutter_app/README.md).

## Screens

| Screen | What it does |
| --- | --- |
| Início | **Safe to spend** until the cycle ends, balance left in the cycle, paid vs. still to pay, cash per account, next payments, this week against last week, budget warnings |
| Movimentos | Every movement of the cycle, grouped by day. Search across all cycles. Tap one to mark it paid/planned, edit or delete it. Import a bank statement (CSV) |
| Categorias | Where the cycle's money went, per category, against the previous cycle. Budgets per category, with a suggested amount from your own history and one tap to set them all. Add your own categories or delete the ones you do not use (what used a deleted one moves to "Outros") |
| Poupança | Net worth now and over the plan, and savings goals. Each goal has a savings account and an automatic transfer on payday ("pay yourself first") |
| Plano | The forecast (balance per cycle) and the fixed bills, with a summary of subscriptions per month and per year |
| Ajustes | Accounts, language, currency, backup (file or clipboard), CSV export, statement import |

**First run.** A new account, or an empty device used as a guest, starts with a short setup: language, currency, the day the month starts, your accounts (checking, spending, savings or investment, each with its starting balance), your categories and your fixed bills. Everything can be changed later.

New expense: the expenses you repeat appear as chips, one tap fills amount, category and description.

**Statement import.** Choose your bank's CSV (or paste its text). The app finds the date, description and amount columns, files each row under the category you used for the same shop before, ticks off planned bills that the statement shows as paid, and skips rows already recorded. You review everything before it is saved.

## Run it

```sh
cd flutter_app
flutter pub get
flutter run -d chrome          # or any other device
flutter analyze && flutter test
```

The tests check the cycle maths against the numbers in the Google Sheet, the encrypted sync (two devices, offline, conflicts), and every screen at phone, tablet and desktop sizes.

## Put it on your iPhone

The site is built and deployed by [`.github/workflows/pages.yml`](.github/workflows/pages.yml) on every push to `main` (analysis and tests run first; a failure blocks the deploy).

1. One time: repo **Settings → Pages → Source: GitHub Actions**.
2. Push to `main`, wait for the "Deploy to GitHub Pages" run (Actions tab, ~3 min).
3. Open `https://diaxpiter.github.io/fin_app/` in **Safari** on the iPhone (or Chrome on Android).
4. Share → **Add to Home Screen**.

It must be opened from the Home Screen icon to run full-screen like an app.

## Your data

- Without an account, data lives only in the browser or phone. **Ajustes → Exportar dados** saves a file; the app reminds you when the last one is over 30 days old.
- With an account, data is encrypted on the device before it is uploaded ([`crypto.dart`](flutter_app/lib/src/crypto.dart)). The server sees only ciphertext. Changes made on two devices are merged, and changes that could not be uploaded are kept until they can be.
- Tick **Dispositivo partilhado** when signing in on a computer that is not yours: nothing is kept on it, and signing in is needed after every reload.
- Money is stored as integer cents. Dates are plain `YYYY-MM-DD` strings. A cycle id is the month the cycle ends in (`2026-11` = 23 Oct – 22 Nov). Anything read from a backup or the server is validated first.

## Setting up the server (Supabase)

1. Run [`supabase/schema.sql`](supabase/schema.sql) once in the SQL editor. Run it again after pulling updates: it is safe to repeat, and newer versions add a table that keeps the last 10 versions of each vault.
2. In the Supabase dashboard, under Authentication, turn on **email confirmation** and **CAPTCHA protection**, and keep the default rate limits.

## Security notes

- The page sets a Content-Security-Policy in [`web/index.html`](flutter_app/web/index.html). GitHub Pages cannot send response headers, so protection against embedding in another site (`frame-ancestors` / `X-Frame-Options`) needs a host that can, such as Cloudflare or Netlify in front of the site.
- The data key is kept in the browser's storage unless **Dispositivo partilhado** is ticked. Anything that can run script on the page could read it, which is why the policy is strict and the page loads no third-party code.
- Not done yet: secure storage of the key on iOS and Android, and Argon2id instead of PBKDF2 for the password.
