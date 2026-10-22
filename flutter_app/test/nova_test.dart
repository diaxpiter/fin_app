// End-to-end checks of Nova despesa, played as a user would on real screen sizes:
// everything reachable without scrolling, amount and description typed separately
// (on-screen keypad and physical keyboard), and the calendar header on one line.

import 'dart:io';

import 'package:fin_app/src/screens/nova.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpAt;

Future<void> openNova(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Nova despesa'));
  await tester.pumpAndSettle();
}

/// The amount as shown, e.g. "12,50".
String amountText(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('nova-amount')), matching: find.byType(Text)))
    .first
    .data!;

TextField descField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField));

bool keypadShown() => find.byIcon(Icons.backspace_outlined).evaluate().isNotEmpty;

Finder get dateButton => find.byIcon(Icons.calendar_today_outlined);

/// The test font draws every glyph as a square, so "Alimentação" is twice as wide as on a
/// phone. Layout checks load the real Roboto that ships with the Flutter SDK.
final _roboto = Directory('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');

Future<void> loadRoboto() async {
  final loader = FontLoader('Roboto');
  for (final w in ['regular', 'medium', 'bold']) {
    loader.addFont(File('${_roboto.path}/roboto-$w.ttf').readAsBytes().then(ByteData.sublistView));
  }
  await loader.load();
}

void main() {
  final hasRoboto = _roboto.existsSync();
  setUpAll(() async {
    if (hasRoboto) await loadRoboto();
  });

  // iPhone SE / 8, a common Android size, iPhone 15
  const phones = {'375x667': Size(375, 667), '360x740': Size(360, 740), '390x844': Size(390, 844)};

  for (final MapEntry(key: name, value: size) in phones.entries) {
    testWidgets('$name: categories, date and status fit without scrolling', skip: !hasRoboto, (tester) async {
      await pumpAt(tester, size);
      await openNova(tester);
      final list = find.descendant(of: find.byType(NovaScreen), matching: find.byType(Scrollable)).first;
      expect(tester.state<ScrollableState>(list).position.maxScrollExtent, 0, reason: 'the form scrolls');
      // every category chip is on screen and the keypad + save button below it
      for (final c in ['Moradia', 'Alimentação', 'Subscrição', 'Crédito', 'Lazer', 'Outros']) {
        expect(tester.getRect(find.text(c)).bottom, lessThan(tester.getTopLeft(find.text('1').last).dy), reason: c);
      }
      expect(tester.getRect(dateButton).bottom, lessThan(tester.getTopLeft(find.text('1').last).dy));
      expect(tester.getRect(find.text('Adicionar despesa')).bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a full expense, as a user: keypad, description, category, date, planned', (tester) async {
    await pumpAt(tester, const Size(375, 667));
    await openNova(tester);
    for (final k in ['1', '2', '5', '0']) {
      await tester.tap(find.text(k).last);
    }
    await tester.pump();
    expect(amountText(tester), '12,50');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(keypadShown(), isFalse, reason: 'the system keyboard replaces the keypad');
    await tester.enterText(find.byType(TextField), 'Cinema');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(keypadShown(), isTrue, reason: '"done" goes back to the amount');

    await tester.tap(find.text('Lazer'));
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('3')));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('3 nov'), findsOneWidget);
    await tester.tap(find.text('Previsto'));
    await tester.tap(find.text('Adicionar despesa'));
    await tester.pumpAndSettle();
    expect(find.text('Despesa adicionada'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.format_list_bulleted).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Cinema'), 200,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    expect(find.text('Cinema'), findsOneWidget);
    expect(find.text('−12,50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backspace in the description edits the description, not the amount', (tester) async {
    await pumpAt(tester, const Size(390, 844));
    await openNova(tester);
    await tester.tap(find.text('4').last);
    await tester.tap(find.text('2').last);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Cafe');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.pump();
    expect(descField(tester).controller!.text, 'Caf');
    expect(amountText(tester), '0,42', reason: 'keys typed in the description never reach the amount');
  });

  testWidgets('physical keyboard types the amount while it is selected; a letter starts the description',
      (tester) async {
    await pumpAt(tester, const Size(1440, 900));
    await openNova(tester);
    for (final k in [LogicalKeyboardKey.digit9, LogicalKeyboardKey.digit5, LogicalKeyboardKey.numpad0]) {
      await tester.sendKeyEvent(k);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(amountText(tester), '0,95');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(descField(tester).controller!.text, 'p');
    expect(descField(tester).focusNode!.hasFocus, isTrue);

    // tapping the amount selects it again and brings back the keypad
    await tester.tap(find.byKey(const ValueKey('nova-amount')));
    await tester.pumpAndSettle();
    expect(descField(tester).focusNode!.hasFocus, isFalse);
    expect(keypadShown(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(amountText(tester), '9,51');
    expect(descField(tester).controller!.text, 'p');
  });

  testWidgets('on-screen keypad works after typing a description and picking a category', (tester) async {
    await pumpAt(tester, const Size(375, 667));
    await openNova(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Pão');
    await tester.tap(find.text('Alimentação')); // a tap outside closes the system keyboard
    await tester.pumpAndSettle();
    expect(keypadShown(), isTrue);
    await tester.tap(find.text('8').last);
    await tester.tap(find.text('0').last);
    await tester.pump();
    expect(amountText(tester), '0,80');
    expect(descField(tester).controller!.text, 'Pão');
  });

  // The header reads "segunda, 2/11"; in landscape it gets a narrow column of its own.
  const pickerSizes = {
    'small phone': Size(320, 640),
    'phone': Size(375, 667),
    'phone landscape': Size(844, 390),
    'desktop': Size(1440, 900),
  };
  for (final MapEntry(key: name, value: size) in pickerSizes.entries) {
    testWidgets('calendar header keeps every word whole on $name', (tester) async {
      await pumpAt(tester, size, now: DateTime(2026, 11, 2)); // a Monday: "segunda"
      await openNova(tester);
      // on the smallest phones the date row is just below the fold
      await tester.dragUntilVisible(
          dateButton, find.descendant(of: find.byType(NovaScreen), matching: find.byType(ListView)), const Offset(0, -100));
      await tester.pumpAndSettle();
      await tester.tap(dateButton);
      await tester.pumpAndSettle();
      final header = find.descendant(of: find.byType(DatePickerDialog), matching: find.textContaining('/11'));
      expect(header, findsOneWidget);
      final text = tester.widget<Text>(header).data!;
      final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: header, matching: find.byType(RichText)));
      expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" was cut short');
      // each word sits on a single line
      var start = 0;
      for (final word in text.split(' ')) {
        final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + word.length));
        expect(boxes.map((b) => b.top).toSet(), hasLength(1), reason: '"$word" breaks across lines');
        start += word.length + 1;
      }
      if (size.width < size.height) {
        final all = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
        expect(all.map((b) => b.top).toSet(), hasLength(1), reason: 'portrait: weekday and date on one line');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
