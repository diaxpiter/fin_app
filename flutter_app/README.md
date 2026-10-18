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

## Privacy

Everything stays on the device (shared_preferences: localStorage on web, UserDefaults on
iOS, SharedPreferences on Android, a local file on desktop). There is no server and no
account, so nobody else, the developer included, can see the data.
Backups are a JSON copy made through the clipboard (Ajustes → Exportar / Importar). The
format is the same as the PWA's, so a copy from one app imports into the other.

## Code

```
lib/main.dart                 app + adaptive shell (bottom bar / rail)
lib/src/layout.dart           breakpoints, centred page body
lib/src/logic.dart            finance maths: port of ../src/logic.js, keep in sync
lib/src/models.dart           data classes + JSON (same schema as the PWA)
lib/src/seed.dart             example data from the sheet
lib/src/store.dart            on-device persistence
lib/src/app_controller.dart   UI state + derived model
lib/src/widgets.dart          shared rows, chips, pickers, action sheet
lib/src/screens/              Início, Movimentos, Nova, Previsão, Fixas, Ajustes
test/logic_test.dart          sheet numbers (same cases as the JS tests)
test/widget_test.dart         renders every tab at 5 screen sizes, adds an expense
```
