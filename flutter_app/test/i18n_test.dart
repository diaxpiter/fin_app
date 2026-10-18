import 'dart:convert';

import 'package:fin_app/src/i18n.dart';
import 'package:fin_app/src/models.dart';
import 'package:fin_app/src/seed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('amounts follow the language; the symbol follows language and currency', () {
    final pt = Money('pt', 'EUR'), en = Money('en', 'EUR');
    expect(pt.amount(123456), '1.234,56');
    expect(en.amount(123456), '1,234.56');
    expect(pt.amount(-1200), '−12,00');
    expect(pt.amount(500, sign: true), '+5,00');
    expect(pt.full(123456), '1.234,56 €');
    expect(en.full(123456), '€1,234.56');
    expect(Money('en', 'USD').full(990), r'$9.90');
    expect(Money('pt', 'BRL').full(990), r'R$ 9,90');
    expect(Money('pt', 'USD').full(990), r'9,90 $');
    expect(Money('en', 'CHF').full(990), 'CHF 9.90');
  });

  test('every listed currency formats in every language', () {
    for (final lang in languages.keys) {
      for (final code in currencies.keys) {
        expect(Money(lang, code).full(100), contains(lang == 'pt' ? '1,00' : '1.00'), reason: '$lang $code');
      }
    }
  });

  test('typed amounts are read in either style', () {
    expect(parseAmount('1.234,56'), 123456);
    expect(parseAmount('1,234.56'), 123456);
    expect(parseAmount('45,9'), 4590);
    expect(parseAmount('25.50'), 2550);
    expect(parseAmount('35'), 3500);
    expect(parseAmount('1.234'), 123400, reason: 'three digits after the dot = thousands');
    expect(parseAmount('12,90 €'), 1290);
    expect(parseAmount(''), isNull);
  });

  test('language falls back to the device, then English', () {
    expect(resolveLanguage('pt', 'en'), 'pt');
    expect(resolveLanguage(null, 'pt'), 'pt');
    expect(resolveLanguage(null, 'de'), 'en');
  });

  test('default categories are translated; custom ones are kept', () {
    expect(const S('en').category('Moradia'), 'Housing');
    expect(const S('pt').category('Moradia'), 'Moradia');
    expect(const S('en').category('Cão'), 'Cão');
  });

  test('language and currency are saved with the data; old backups still load', () {
    final s = seedState()..config = seedState().config.copyWith(language: 'en', currency: 'USD');
    final back = AppState.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.config.language, 'en');
    expect(back.config.currency, 'USD');

    final old = seedState().toJson()..['config'] = {'cycleStartDay': 23, 'openingBalance': 0};
    final loaded = AppState.fromJson(jsonDecode(jsonEncode(old)));
    expect(loaded.config.language, isNull);
    expect(loaded.config.currency, 'EUR');
  });
}
