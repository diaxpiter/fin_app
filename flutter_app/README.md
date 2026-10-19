# Painel Financeiro — Flutter

The same app as the PWA in the repo root, built with Flutter so it runs natively on
**Android, iOS, web, Windows, macOS and Linux**, and adapts to any screen size.

## How it adapts

| Width | Typical device | Navigation | Layout |
| --- | --- | --- | --- |
| < 600 | phone (portrait) | bottom bar + floating “+” | single column; Nova despesa full-screen; actions in a bottom sheet |
| 600 – 1039 | phone landscape, small tablet | navigation rail | 4-column stats; extra “Saldo” column in Previsão; Nova despesa in a dialog |
| ≥ 1040 | large tablet, laptop, desktop browser | extended rail with labels | Início split in two panes; content capped so lines stay readable |

Short windows (phones in landscape, height < 560) get a compact rail and a side-by-side
Nova despesa (fields left, keypad right). Big amounts shrink to fit instead of overflowing
on 320px phones, and Previsão shows as many bars as fit the width. With a physical
keyboard, Nova despesa accepts digits, Backspace and Enter.

Breakpoints live in `lib/src/layout.dart`.

## Fixed bills, language and currency

- **Fixed bills** (Fixas): add, edit or delete salary, rent, utilities… Each one is planned
  as a *Previsto* movement for the current cycle and the next 11 (`syncRecurring` in
  `lib/src/logic.dart`). Editing a bill rewrites only its future planned movements: paid
  ones and past cycles stay as they are, and a movement typed in by hand isn't duplicated.
  A new account's first login asks for them, along with language, currency and the day
  the month starts.
- **Weekends and holidays**: each bill can keep its day, or move to the previous or next
  business day (e.g. salary on the 25th, or the business day before). Portugal's 13
  national holidays are built in, Easter-based ones included (`lib/src/holidays.dart`);
  Ajustes → Feriados can switch to weekends only. A salary paid early, before the cycle
  starts, still counts in its own cycle.
- **Accounts**: e.g. a current account for salary and bills, an everyday card, an
  investment broker and an emergency fund. Each movement and fixed bill belongs to one;
  **transfers** (one-off, or as a fixed bill) move money between them without counting as
  income or expense. Início lists each account with today's balance and its lowest point
  this cycle (red if it would go negative before payday), plus how much went to savings /
  investments. "Em conta" is everyday money; savings and investments are listed apart.
  With one account none of this shows. (The old PWA doesn't know transfers: a backup with
  them imports there as expenses.)
- **Language**: Português or English (`lib/src/i18n.dart`, both side by side). Until the
  user picks one it follows the device. Default category names are stored in Portuguese
  and shown translated.
- **Currency**: EUR, USD, GBP, BRL, CHF, CAD, AUD, AOA, MZN. Numbers follow the language
  (`1.234,56 €` / `€1,234.56`), and typed amounts are accepted in either style. Changing
  the currency only changes the symbol; amounts are not converted.

Language and currency are saved with the data, so with an account they follow the user
to every device.

## First run

Install Flutter (3.22 or newer): https://docs.flutter.dev/get-started/install

```sh
cd flutter_app
flutter create --project-name fin_app --platforms=android,ios,web,windows,macos,linux .
flutter pub get
flutter test
flutter run            # pick a device, or: -d chrome / -d windows / -d <phone>
```

`flutter create .` only adds the missing platform folders (android/, ios/, web/…). It
leaves `lib/` and `test/` alone.

## Accounts and privacy

People can use the app **without an account** (data stays on that device only) or
**create an account** to have their data on every device.

With an account, the data is **end-to-end encrypted** (`lib/src/crypto.dart`):

- The password never leaves the device. PBKDF2 (600 000 rounds) turns it into a login
  secret for Supabase and a separate key that unlocks the data.
- The data is encrypted with AES-256-GCM before upload. The `vaults` table holds only
  ciphertext, so whoever runs the Supabase project can't read anyone's finances.
- On their first sign-in, users get a **recovery key**. If they forget the password, the
  reset email plus that key restores access. Without either one the data is gone; that
  is the price of the admin not being able to read it.
- Each user can reach only their own row (row-level security), and **Apagar conta**
  deletes the account and its data (`supabase/schema.sql`).

Changes save on the device at once and sync about a second later. If two devices edit at
the same moment, the first save wins and the other device is told.

Backups: Ajustes → Exportar / Importar copies a JSON backup through the clipboard. The
format is the same as the PWA's.

### Supabase setup (once)

1. SQL Editor → paste `../supabase/schema.sql` → Run.
2. Authentication → URL Configuration: **Site URL** `https://diaxpiter.github.io/fin_app/`;
   add `http://localhost:8080/` under **Redirect URLs** for local testing.
3. Project URL and anon key go in `lib/src/config.dart`. The anon key is public by design.

## Code

```
lib/main.dart                 app + adaptive shell (bottom bar / rail)
lib/src/layout.dart           breakpoints, centred page body
lib/src/logic.dart            finance maths: port of ../src/logic.js, keep in sync
lib/src/models.dart           data classes + JSON (same schema as the PWA)
lib/src/seed.dart             example data from the sheet
lib/src/store.dart            on-device persistence
lib/src/crypto.dart           end-to-end encryption, recovery key
lib/src/backend.dart          Supabase login + vault storage
lib/src/account.dart          sign up/in/out, recovery, sync
lib/src/config.dart           Supabase project URL + anon key
lib/src/i18n.dart             interface text (pt / en), money formatting
lib/src/app_controller.dart   UI state + derived model
lib/src/widgets.dart          shared rows, chips, pickers, action sheet
lib/src/screens/              Início, Movimentos, Nova, Previsão, Fixas (bills.dart), Ajustes,
                              account screens (auth.dart), first login (onboarding.dart)
test/logic_test.dart          sheet numbers (same cases as the JS tests)
test/widget_test.dart         renders every tab at 5 screen sizes, adds an expense
test/account_test.dart        encryption, sign-up/in, recovery, sync, conflicts (fake server)
test/i18n_test.dart           number/currency formatting, amount parsing, saved preferences
test/accounts_test.dart       per-account balances, transfers, savings, per-account forecast
```
