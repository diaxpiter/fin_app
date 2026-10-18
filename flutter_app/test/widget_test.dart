// Renders the app at phone, tablet and desktop sizes and checks the
// navigation adapts and nothing overflows.

import 'package:fin_app/main.dart';
import 'package:fin_app/src/account.dart';
import 'package:fin_app/src/app_controller.dart';
import 'package:fin_app/src/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = Store.memory();
  final app = AppController(store, clock: () => DateTime(2026, 11, 1));
  // no backend → guest mode, straight to the app
  final account = AccountController(store: store, backend: null, prefs: null);
  await account.init();
  await tester.pumpWidget(FinApp(controller: app, account: account));
  await tester.pumpAndSettle();
}

void main() {
  group('bills', billTests);

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
