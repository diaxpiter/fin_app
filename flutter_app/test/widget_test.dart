// Renders the app at phone, tablet and desktop sizes and checks the
// navigation adapts and nothing overflows.

import 'package:fin_app/main.dart';
import 'package:fin_app/src/account.dart';
import 'package:fin_app/src/app_controller.dart';
import 'package:fin_app/src/seed.dart';
import 'package:fin_app/src/store.dart';
import 'package:fin_app/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpAt(WidgetTester tester, Size size, {String? language = 'pt', DateTime? now}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = Store.memory()..setLanguage(language);
  final app = AppController(store, clock: () => now ?? DateTime(2026, 11, 1));
  // no backend → guest mode, straight to the app
  final account = AccountController(store: store, backend: null, prefs: null);
  await account.init();
  await tester.pumpWidget(FinApp(controller: app, account: account));
  await tester.pumpAndSettle();
}

/// Plano holds the forecast and the fixed bills: open the bills.
Future<void> openFixas(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.event_note_outlined).first);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PillChip, 'Fixas'));
  await tester.pumpAndSettle();
}

void main() {
  group('bills', billTests);
  group('language and currency', languageTests);
  group('editing, balance, matching', editingTests);
  group('typed inputs and calendars', inputTests);
  group('accounts', accountTests);
  group('budgets', budgetTests);
  group('home', homeTests);
  group('everyday', everydayTests);
  group('categories and first run', categoryUiTests);

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
      for (final icon in [
        Icons.format_list_bulleted,
        Icons.pie_chart_outline,
        Icons.savings_outlined,
        Icons.event_note_outlined,
        Icons.home_outlined
      ]) {
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
    await openFixas(tester);
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

void budgetTests() {
  testWidgets('set a budget in Categorias and see the warning on Início', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('LIVRE PARA GASTAR'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pie_chart_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moradia'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '300');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('excedeu o orçamento'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.home_outlined).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Moradia: excedeu o orçamento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void everydayTests() {
  testWidgets('create a savings goal and see it with its progress', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.savings_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text('PATRIMÓNIO'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Nova meta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome da meta'), 'Férias');
    await tester.enterText(find.widgetWithText(TextField, 'Valor a atingir'), '900');
    await tester.enterText(find.widgetWithText(TextField, 'Guardar por ciclo'), '100');
    await tester.enterText(find.widgetWithText(TextField, 'Já tenho'), '300');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('300,00 / 900,00'), find.byType(ListView), const Offset(0, -300));
    expect(find.text('Férias'), findsWidgets); // the goal and its new account
    expect(find.text('300,00 / 900,00'), findsOneWidget);
    expect(find.textContaining('por ciclo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a goal needs a name and an amount', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.savings_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Nova meta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Dá um nome à meta.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('import a bank file: the rent is settled, the coffee is added', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.format_list_bulleted).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField),
        'Data;Descrição;Montante;Saldo\n'
        '24-10-2026;TRF SENHORIO;-250,00;1.000,00\n'
        '25-10-2026;CAFE CENTRAL;-1,20;998,80\n');
    await tester.tap(find.text('Analisar texto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Marca «Renda» como pago'), findsOneWidget);
    expect(find.text('Importar 2 movimentos'), findsOneWidget);
    await tester.tap(find.text('Importar 2 movimentos'));
    await tester.pumpAndSettle();
    expect(find.text('2 movimentos importados'), findsOneWidget);
    final store = AppScope.of(tester.element(find.byType(Scaffold).first), listen: false).store;
    expect(store.state.movements.firstWhere((m) => m.description == 'Renda').estado, 'Pago');
    expect(store.state.movements.any((m) => m.description == 'CAFE CENTRAL' && m.estado == 'Pago'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unreadable file is explained', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.format_list_bulleted).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.upload_file));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'isto não é um extrato');
    await tester.tap(find.text('Analisar texto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não reconheci este formato'), findsOneWidget);
  });

  testWidgets('search looks through every cycle', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.format_list_bulleted).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('search')), 'klarna');
    await tester.pumpAndSettle();
    expect(find.text('Klarna'), findsWidgets);
    expect(find.text('Renda'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('search')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('Nada encontrado.'), findsOneWidget);
  });

  testWidgets('Plano switches between the forecast and the fixed bills', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.event_note_outlined).first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PillChip, 'Previsão'), findsOneWidget);
    await tester.tap(find.widgetWithText(PillChip, 'Fixas'));
    await tester.pumpAndSettle();
    expect(find.text('SUBSCRIÇÕES'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Categorias offers budgets worked out from what was spent', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.pie_chart_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Quanto devias gastar?'), findsOneWidget);
    await tester.tap(find.textContaining('Definir 3 orçamentos'));
    await tester.pumpAndSettle();
    expect(find.text('ORÇAMENTO DO CICLO'), findsOneWidget);
    expect(find.text('Quanto devias gastar?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void homeTests() {
  testWidgets('before the cycle starts, Início still shows what is safe to spend', (tester) async {
    await pumpAt(tester, const Size(390, 844), now: DateTime(2026, 10, 22));
    expect(find.text('LIVRE PARA GASTAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a guest with data and no backup is reminded to save one', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.textContaining('Sem cópia de segurança'), findsOneWidget);
    await tester.tap(find.textContaining('Sem cópia de segurança'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustes'), findsOneWidget); // the Ajustes page opened
    expect(tester.takeException(), isNull);
  });
}

void languageTests() {
  testWidgets('switch to English and US dollars from Ajustes', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    expect(find.text('Movimentos'), findsOneWidget);
    expect(find.text('€'), findsNWidgets(2)); // after each big amount (safe to spend, left this cycle)

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
    expect(find.text(r'$'), findsNWidgets(2));
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
    // the keypad steps aside while the description is selected; tap the amount to get it back
    await tester.tap(find.byKey(const ValueKey('nova-amount')));
    await tester.pumpAndSettle();
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
    await openFixas(tester);
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

void accountTests() {
  testWidgets('add an account, then move money to it with a transfer', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    // Ajustes → Contas → Nova conta
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova conta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Conta'), 'Revolut');
    await tester.enterText(find.widgetWithText(TextField, 'Saldo / valor hoje'), '100');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Revolut'), findsOneWidget);
    await tester.tap(find.byType(BackButton)); // pageBack() looks for the English "Back" tooltip
    await tester.pumpAndSettle();

    // Nova → Transferência: Conta principal → Revolut, 50,00
    await tester.tap(find.byTooltip('Nova despesa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transferência'));
    await tester.pumpAndSettle();
    expect(find.text('Nova transferência'), findsOneWidget);
    for (final k in ['5', '0', '0', '0']) {
      await tester.tap(find.text(k).last);
    }
    await tester.tap(find.text('Adicionar transferência'));
    await tester.pumpAndSettle();
    expect(find.text('Transferência adicionada'), findsOneWidget);

    // Início lists both accounts; Revolut went from 100 to 150
    await tester.scrollUntilVisible(find.text('150,00'), 200);
    expect(find.text('Revolut'), findsWidgets);
    expect(find.text('150,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void categoryUiTests() {
  testWidgets('add a category and delete another on Categorias', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.tap(find.byIcon(Icons.pie_chart_outline).first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova categoria').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Animais');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Animais'), findsWidgets);

    await tester.tap(find.byTooltip('Apagar').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Apagar'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Apagar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty guest device starts with the setup, and Concluir opens the app', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = Store.memory(emptyState())..setLanguage('pt');
    final app = AppController(store, clock: () => DateTime(2026, 11, 1));
    final account = AccountController(store: store, backend: null, prefs: prefs);
    await account.init();
    await tester.pumpWidget(FinApp(controller: app, account: account));
    await tester.pumpAndSettle();
    expect(find.text('Vamos preparar o teu painel'), findsOneWidget);
    // the setup stays open while the plan is being filled in
    store.addCategory('Animais', 'Saída', '#7AA2F7');
    await tester.pumpAndSettle();
    expect(find.text('Vamos preparar o teu painel'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Saltar por agora'), 400, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Saltar por agora'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    // not shown again
    final again = AccountController(store: store, backend: null, prefs: prefs);
    await again.init();
    expect(again.needsOnboarding, isFalse);
  });

  testWidgets('a guest who already has data does not get the setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final account = AccountController(store: Store.memory(), backend: null, prefs: prefs);
    await account.init();
    expect(account.needsOnboarding, isFalse);
  });
}
