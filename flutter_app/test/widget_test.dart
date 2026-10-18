// Renders the app at phone, tablet and desktop sizes and checks the
// navigation adapts and nothing overflows.

import 'package:fin_app/main.dart';
import 'package:fin_app/src/account.dart';
import 'package:fin_app/src/app_controller.dart';
import 'package:fin_app/src/store.dart';
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
