// Business days: weekends plus national holidays, so a fixed bill like a
// salary paid "on the 25th, or the business day before" lands on the right date.
// To add a country: a code in [holidayCountries] and a case in [_holidays].

import 'logic.dart' show iso, parseISO;
import 'models.dart' show DayShift;

/// Countries with a built-in holiday calendar ('none' = weekends only).
const holidayCountries = ['PT', 'none'];

/// Easter Sunday (Gregorian, anonymous algorithm).
DateTime easter(int y) {
  final a = y % 19, b = y ~/ 100, c = y % 100, d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30, i = c ~/ 4, k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31, day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime.utc(y, month, day);
}

String _isoOf(DateTime d) => iso(d.year, d.month, d.day);

final _cache = <String, Set<String>>{};

/// National holidays of [country] in year [y], as YYYY-MM-DD.
Set<String> _holidays(String country, int y) => _cache.putIfAbsent('$country$y', () {
      switch (country) {
        case 'PT':
          // Portugal's 13 national holidays (Código do Trabalho, art. 234.º); municipal ones vary by town.
          final e = easter(y);
          return {
            iso(y, 1, 1), // Ano Novo
            _isoOf(e.subtract(const Duration(days: 2))), // Sexta-feira Santa
            _isoOf(e), // Páscoa
            iso(y, 4, 25), // Dia da Liberdade
            iso(y, 5, 1), // Dia do Trabalhador
            _isoOf(e.add(const Duration(days: 60))), // Corpo de Deus
            iso(y, 6, 10), // Dia de Portugal
            iso(y, 8, 15), // Assunção de Nossa Senhora
            iso(y, 10, 5), // Implantação da República
            iso(y, 11, 1), // Todos os Santos
            iso(y, 12, 1), // Restauração da Independência
            iso(y, 12, 8), // Imaculada Conceição
            iso(y, 12, 25), // Natal
          };
        default:
          return const {};
      }
    });

bool isHoliday(String dateISO, String country) => _holidays(country, parseISO(dateISO).y).contains(dateISO);

bool isBusinessDay(String dateISO, String country) {
  final p = parseISO(dateISO);
  final wd = DateTime.utc(p.y, p.m, p.d).weekday;
  return wd != DateTime.saturday && wd != DateTime.sunday && !isHoliday(dateISO, country);
}

/// Moves [dateISO] to the previous / next business day when it isn't one.
String shiftToBusinessDay(String dateISO, DayShift shift, String country) {
  if (shift == DayShift.none) return dateISO;
  final p = parseISO(dateISO);
  var d = DateTime.utc(p.y, p.m, p.d);
  final step = Duration(days: shift == DayShift.before ? -1 : 1);
  while (!isBusinessDay(_isoOf(d), country)) {
    d = d.add(step);
  }
  return _isoOf(d);
}
