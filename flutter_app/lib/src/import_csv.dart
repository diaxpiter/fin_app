// Bank statement import: reads a CSV exported by a bank, guesses each row's category from the user's
// own history, and ties payments to bills that were planned. Pure logic; the screen is screens/importar.dart.

import 'i18n.dart' show parseAmount;
import 'logic.dart';
import 'models.dart';

class CsvRow {
  const CsvRow(this.date, this.description, this.cents);
  final String date; // YYYY-MM-DD
  final String description;

  /// Negative = money out.
  final int cents;
}

class CsvResult {
  const CsvResult(this.rows, this.skipped);
  final List<CsvRow> rows;

  /// Lines that had no usable date or amount (totals, notes).
  final int skipped;
}

// ---- reading the file --------------------------------------------------

List<String> _fields(String line, String d) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == d) {
      out.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  out.add(cur.toString().trim());
  return out;
}

/// Date written as 2026-10-23, 23-10-2026, 23/10/2026, 23.10.2026 or 2026/10/23 → ISO, or null.
String? parseBankDate(String raw) {
  final t = raw.trim().split(' ').first;
  final m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(t) ??
      RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(t);
  if (m == null) return null;
  final first = m.group(1)!.length == 4;
  final y = int.parse(first ? m.group(1)! : m.group(3)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(first ? m.group(3)! : m.group(1)!);
  final out = iso(y, mo, d);
  final check = DateTime.tryParse(out);
  return check != null && check.month == mo && check.day == d ? out : null;
}

final _money = RegExp(r'^[+\-−(]?\s*\d[\d.,\s]*\)?\s*-?$');

/// "-12,30", "1.234,56", "(45.00)", "12,30 €", "12,30-" → signed cents, or null when it isn't an amount.
int? parseSignedAmount(String raw) {
  var t = raw.replaceAll(RegExp(r'(€|EUR|eur|\$|£)'), '').trim();
  if (t.isEmpty || !_money.hasMatch(t) || parseBankDate(t) != null) return null;
  final neg = t.startsWith('-') || t.startsWith('−') || t.startsWith('(') || t.endsWith('-');
  t = t.replaceAll(RegExp(r'[+\-−()\s]'), '');
  final c = parseAmount(t);
  return c == null ? null : (neg ? -c : c);
}

bool _hasDecimals(String s) => RegExp(r'[.,]\d{1,2}\s*(€|EUR)?\)?-?$').hasMatch(s.trim());

final _hDate = RegExp(r'^(data|date|dt)', caseSensitive: false);
final _hAmount = RegExp(r'montante|valor|amount|quantia|importe|value', caseSensitive: false);
final _hDebit = RegExp(r'd[ée]bito|debit', caseSensitive: false);
final _hCredit = RegExp(r'cr[ée]dito|credit', caseSensitive: false);
final _hBalance = RegExp(r'saldo|balance', caseSensitive: false);
final _hDesc = RegExp(r'descri|movimento|detalhe|detail|memo|narrat|texto|benefici', caseSensitive: false);

String _delimiter(List<String> lines) {
  var best = ';', bestScore = -1;
  for (final d in [';', '\t', ',', '|']) {
    final score = lines.where((l) => _fields(l, d).length >= 3).length;
    if (score > bestScore) {
      best = d;
      bestScore = score;
    }
  }
  return best;
}

/// Finds the date, description and amount columns of a bank CSV and returns its movements; null when
/// the file doesn't look like a statement. Quoted fields spanning several lines are not supported.
CsvResult? parseBankCsv(String text) {
  final lines = text
      .replaceFirst('﻿', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) return null;
  final d = _delimiter(lines.take(10).toList());
  final rows = [for (final l in lines) _fields(l, d)];

  // header: the first early row that names at least two kinds of column
  var header = -1;
  for (var i = 0; i < rows.length && i < 12 && header < 0; i++) {
    final kinds = {
      for (final c in rows[i])
        if (_hDate.hasMatch(c)) 'date',
      for (final c in rows[i])
        if (_hAmount.hasMatch(c) || _hDebit.hasMatch(c) || _hCredit.hasMatch(c)) 'amount',
      for (final c in rows[i])
        if (_hDesc.hasMatch(c)) 'desc',
    };
    if (kinds.length >= 2) header = i;
  }
  final names = header >= 0 ? rows[header] : const <String>[];
  final data = rows.skip(header + 1).toList();
  final width = data.fold<int>(0, (a, r) => r.length > a ? r.length : a);
  final sample = data.take(40).toList();

  String cell(List<String> r, int c) => c < r.length ? r[c] : '';
  double frac(int c, bool Function(String) test) {
    final cells = sample.map((r) => cell(r, c)).where((x) => x.isNotEmpty).toList();
    return cells.isEmpty ? 0 : cells.where(test).length / cells.length;
  }

  int? pick(Iterable<int> candidates, RegExp header, {RegExp? not}) {
    for (final c in candidates) {
      final n = c < names.length ? names[c] : '';
      if (header.hasMatch(n) && (not == null || !not.hasMatch(n))) return c;
    }
    return null;
  }

  final cols = List.generate(width, (i) => i);
  // a column named like a date needs fewer valid cells: statements end with totals and notes
  final dateCols = cols.where((c) {
    final f = frac(c, (x) => parseBankDate(x) != null);
    return f >= 0.7 || (f >= 0.4 && c < names.length && _hDate.hasMatch(names[c]));
  }).toList();
  if (dateCols.isEmpty) return null;
  final dateCol = pick(dateCols, _hDate) ?? dateCols.first;

  final numeric = cols
      .where((c) => !dateCols.contains(c) && frac(c, (x) => parseSignedAmount(x) != null) >= 0.5)
      .where((c) => frac(c, _hasDecimals) >= 0.5)
      .toList();
  final debitCol = pick(numeric, _hDebit), creditCol = pick(numeric, _hCredit);
  final int? amountCol = debitCol != null && creditCol != null
      ? null
      : pick(numeric, _hAmount, not: _hBalance) ??
          numeric.where((c) => !(c < names.length && _hBalance.hasMatch(names[c]))).firstOrNull;
  if (amountCol == null && (debitCol == null || creditCol == null)) return null;

  final textCols = cols
      .where((c) => c != dateCol && !dateCols.contains(c) && !numeric.contains(c))
      .where((c) => frac(c, (x) => x.isNotEmpty) > 0)
      .toList();
  final descCol = pick(textCols, _hDesc);

  final out = <CsvRow>[];
  var skipped = 0;
  for (final r in data) {
    final date = parseBankDate(cell(r, dateCol));
    int? cents;
    if (amountCol != null) {
      cents = parseSignedAmount(cell(r, amountCol));
    } else {
      final out_ = parseSignedAmount(cell(r, debitCol!)), inn = parseSignedAmount(cell(r, creditCol!));
      cents = inn != null && inn != 0 ? inn.abs() : (out_ != null && out_ != 0 ? -out_.abs() : null);
    }
    if (date == null || cents == null || cents == 0) {
      skipped++;
      continue;
    }
    final desc = (descCol != null ? cell(r, descCol) : textCols.map((c) => cell(r, c)).where((x) => x.isNotEmpty).join(' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    out.add(CsvRow(date, desc.length > 80 ? desc.substring(0, 80) : desc, cents));
  }
  return out.isEmpty ? null : CsvResult(out, skipped);
}

// ---- guessing the category ----------------------------------------------

const _stop = {
  'compra', 'compras', 'pagamento', 'pag', 'transferencia', 'trf', 'mb', 'way', 'cartao', 'card', 'debito', 'credito',
  'purchase', 'payment', 'pos', 'ref', 'referencia', 'servico', 'servicos', 'the', 'and', 'lda', 'sa', 'para', 'por',
  'dos', 'das', 'del', 'visa', 'mastercard', 'levantamento', 'entidade', 'portugal', 'porto', 'lisboa'
};

String _plain(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ', to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// The words of a description that identify who was paid: letters only, no card boilerplate.
List<String> merchantWords(String description) => RegExp(r'[a-z]{3,}')
    .allMatches(_plain(description))
    .map((m) => m.group(0)!)
    .where((w) => !_stop.contains(w))
    .toList();

/// A few common Portuguese merchants, used until the user's own history knows better.
const _defaults = {
  'continente': 'Alimentação', 'pingo': 'Alimentação', 'lidl': 'Alimentação', 'auchan': 'Alimentação',
  'minipreco': 'Alimentação', 'intermarche': 'Alimentação', 'aldi': 'Alimentação', 'mercadona': 'Alimentação',
  'netflix': 'Subscrição', 'spotify': 'Subscrição', 'hbo': 'Subscrição', 'disney': 'Subscrição', 'youtube': 'Subscrição',
  'icloud': 'Subscrição', 'crunchyroll': 'Subscrição', 'prime': 'Subscrição',
  'edp': 'Moradia', 'endesa': 'Moradia', 'galp': 'Moradia', 'iberdrola': 'Moradia', 'epal': 'Moradia',
  'vodafone': 'Moradia', 'meo': 'Moradia', 'nowo': 'Moradia',
};

/// "Who is paid → category", learned from what the user already filed (most common wins).
class Rules {
  Rules._(this._byKey);
  final Map<String, Map<String, int>> _byKey;

  /// The category for [description], or null when nothing known matches.
  String? categoryFor(String description, {required Set<String> allowed}) {
    final words = merchantWords(description).toSet();
    String? best;
    var bestLen = 0, bestCount = 0;
    _byKey.forEach((key, cats) {
      final parts = key.split(' ');
      if (!parts.every(words.contains)) return;
      final top = cats.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (!allowed.contains(top.key)) return;
      if (parts.length > bestLen || (parts.length == bestLen && top.value > bestCount)) {
        best = top.key;
        bestLen = parts.length;
        bestCount = top.value;
      }
    });
    if (best != null) return best;
    for (final w in merchantWords(description)) {
      final c = _defaults[w];
      if (c != null && allowed.contains(c)) return c;
    }
    return null;
  }
}

Rules learnRules(AppState state) {
  final types = typesOf(state);
  final byKey = <String, Map<String, int>>{};
  for (final m in state.movements) {
    if (types[m.category] == transferType) continue;
    final w = merchantWords(m.description);
    if (w.isEmpty) continue;
    final key = w.take(2).join(' ');
    final cats = byKey.putIfAbsent(key, () => {});
    cats[m.category] = (cats[m.category] ?? 0) + 1;
  }
  return Rules._(byKey);
}

// ---- what to do with each row ---------------------------------------------

enum ImportAction { add, markPaid, skip }

class ImportItem {
  ImportItem(this.row, this.category, this.action, {this.plannedId, this.plannedName, this.include = true});
  final CsvRow row;
  String category;
  final ImportAction action;
  final String? plannedId, plannedName;
  bool include;
}

int _daysBetween(String a, String b) {
  final x = parseISO(a), y = parseISO(b);
  return DateTime.utc(x.y, x.m, x.d).difference(DateTime.utc(y.y, y.m, y.d)).inDays;
}

/// Decides, for each row: skip it (already recorded), settle a planned bill of the same amount close
/// by, or add it as a new paid movement under the most likely category.
List<ImportItem> planImport(AppState state, List<CsvRow> rows) {
  final types = typesOf(state);
  final rules = learnRules(state);
  final expenseCats = {for (final c in state.categories) if (c.type == 'Saída') c.name};
  final incomeCats = {for (final c in state.categories) if (c.type == 'Entrada') c.name};
  final fallbackOut = expenseCats.contains('Outros') ? 'Outros' : expenseCats.first;
  final fallbackIn = incomeCats.first;
  final used = <String>{};
  bool sameKind(Movement m, bool income) =>
      types[m.category] != transferType && (types[m.category] == 'Entrada') == income;

  return [
    for (final r in rows)
      () {
        final income = r.cents > 0, cents = r.cents.abs();
        final cat = rules.categoryFor(r.description, allowed: income ? incomeCats : expenseCats) ??
            (income ? fallbackIn : fallbackOut);
        final already = state.movements
            .any((m) => m.estado == 'Pago' && m.date == r.date && m.cents == cents && sameKind(m, income));
        if (already) return ImportItem(r, cat, ImportAction.skip, include: false);
        final planned = state.movements
            .where((m) =>
                m.estado == 'Previsto' &&
                !used.contains(m.id) &&
                m.cents == cents &&
                sameKind(m, income) &&
                _daysBetween(m.date, r.date).abs() <= 7)
            .toList()
          ..sort((a, b) => _daysBetween(a.date, r.date).abs().compareTo(_daysBetween(b.date, r.date).abs()));
        if (planned.isNotEmpty) {
          used.add(planned.first.id);
          return ImportItem(r, planned.first.category, ImportAction.markPaid,
              plannedId: planned.first.id, plannedName: planned.first.description);
        }
        return ImportItem(r, cat, ImportAction.add);
      }()
  ];
}
