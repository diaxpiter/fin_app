// Renders the app at phone, tablet and desktop sizes and checks the
// navigation adapts and nothing overflows.

import 'package:fin_app/main.dart';
import 'package:fin_app/src/account.dart';
import 'package:fin_app/src/app_controller.dart';
import 'package:fin_app/src/store.dart';
import 'package:fin_app/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt(WidgetTester tester, Size size, {String? language = 'pt'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = Store.memory()..setLanguage(language);
  final app = AppController(store, clock: () => DateTime(2026, 11, 1));
  // no backend → guest mode, straight to the app
  final account = AccountController(store: store, backend: null, prefs: null);
  await account.init();
  await tester.pumpWidget(FinApp(controller: app, account: account));
  await tester.pumpAndSettle();
}

void main() {
  group('bills', billTests);
  group('language and currency', languageTests);
  group('editing, balance, matching', editingTests);
  group('typed inputs and calendars', inputTests);

  const sizes = {
    'small phone': Size(320, 640),
    'phone': Size(390, 844),
    'phone landscape': Size(844, 390),
    'tablet': Size(820, 1180),
    'desktop': Size(1440, 900),
  };

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('every tab renders on $name', (tester) async {
      await pumpAt(tester, size);
      expect(find.byType(size.width < 600 ? NavigationBar : NavigationRail), findsOneWidget);
      // tap by icon: the short landscape rail hides labels
      for (final icon in [Icons.format_list_bulleted, Icons.bar_chart_outlined, Icons.repeat, Icons.home_outlined]) {
        await tester.tap(find.byIcon(icon).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('quick add works on $name', (tester) async {
      await pumpAt(tester, size);
      await tester.tap(find.byTooltip('Nova despesa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.tap(find.text('2').last);
      await tester.tap(find.text('Adicionar despesa'));
      await tester.pumpAndSettle();
      expect(find.text('Despesa adicionada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

void billTests() {
  testWidgets('add a fixed bill from Fixas (dot as decimal point)', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.repeat).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Seguro');
    await tester.enterText(find.widgetWithText(TextField, 'Valor'), '25.50');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Seguro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void languageTests() {
  testWidgets('switch to English and US dollars from Ajustes', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('Movimentos'), findsOneWidget);
    expect(find.text('€'), findsOneWidget); // after the big amount in Portuguese

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Português'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.textContaining('Euro'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('US dollar').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('LEFT THIS CYCLE'), findsOneWidget); // section labels are upper-case
    expect(find.text(r'$'), findsOneWidget);
    expect(find.text('239.06'), findsWidgets, reason: 'English number style (leftover and lowest balance)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('follows the device language until one is chosen', (tester) async {
    await pumpAt(tester, const Size(390, 844), language: null); // test devices are English
    expect(find.text('Home'), findsOneWidget);
  });
}

void editingTests() {
  testWidgets('edit a movement from its action sheet', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.format_list_bulleted).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar movimento'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byIcon(Icons.backspace_outlined));
    }
    await tester.tap(find.text('3').last);
    await tester.tap(find.text('00').last);
    await tester.tap(find.text('00').last);
    await tester.tap(find.text('Guardar alterações'));
    await tester.pumpAndSettle();
    expect(find.text('Movimento atualizado'), findsOneWidget);
    expect(find.text('−300,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paying a planned bill asks to settle it instead of duplicating', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Nova despesa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moradia'));
    await tester.enterText(find.byType(TextField), 'Luz');
    for (final k in ['5', '2', '3', '0']) {
      await tester.tap(find.text(k).last);
    }
    await tester.tap(find.text('Adicionar despesa'));
    await tester.pumpAndSettle();
    expect(find.text('É uma conta prevista?'), findsOneWidget);
    await tester.tap(find.textContaining('Luz ·'));
    await tester.pumpAndSettle();
    expect(find.text('Conta marcada como paga'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap "Em conta" to set today\'s balance', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.text('EM CONTA'));
    await tester.pumpAndSettle();
    expect(find.text('Quanto tens hoje na conta?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1.234,56');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('1.234,56'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void inputTests() {
  test('money fields keep only digits and separators', () {
    TextEditingValue type(String t, {bool signed = false}) => MoneyInputFormatter(signed: signed)
        .formatEditUpdate(const TextEditingValue(text: '12'), TextEditingValue(text: t));
    expect(type('12,5').text, '12,5');
    expect(type('1.234,56').text, '1.234,56');
    expect(type('12a').text, '12', reason: 'letters rejected');
    expect(type('12 €').text, '12', reason: 'symbols rejected');
    expect(type('-12').text, '12', reason: 'no minus unless signed');
    expect(type('-12', signed: true).text, '-12');
    expect(type('1-2', signed: true).text, '12', reason: 'minus only at the start');
  });

  testWidgets('bill form: letters are ignored, dates come from a calendar', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.repeat).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();

    final amount = find.widgetWithText(TextField, 'Valor');
    await tester.enterText(amount, 'abc');
    expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
    await tester.enterText(amount, '45,90');
    expect(tester.widget<TextField>(amount).controller!.text, '45,90');

    // first payment: the calendar opens; picking the 12th sets the day of the month
    await tester.tap(find.text('Primeiro pagamento'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('12'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('12 nov 2026'), findsOneWidget);

    // last payment before the first is refused: the last-payment calendar opens a year ahead
    // (Oct 2027); then move the first payment to Dec 2027
    await tester.tap(find.text('Último pagamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primeiro pagamento'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 13; i++) {
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.byIcon(Icons.chevron_right)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('12')));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('12 dez 2027'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Descrição'), 'Seguro');
    await tester.ensureVisible(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('O último pagamento não pode ser antes do primeiro.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
