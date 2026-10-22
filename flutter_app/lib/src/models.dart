// Data shapes. The JSON matches the PWA's store (version 1), so a backup
// exported from one app can be imported into the other.

/// Category type of transfers between the user's own accounts.
const transferType = 'Transferência';

// Backups, imports and synced data are untrusted: a bad value must be refused when it is read,
// not crash the app on every launch afterwards.
final _hexColor = RegExp(r'^#[0-9A-Fa-f]{6}$');
final _cycleId = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

/// Largest amount in cents (10 billion): stays exact in the JavaScript numbers the web build uses.
const maxCents = 1000000000000;

bool _isDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final d = DateTime.tryParse(s);
  return d != null && d.toIso8601String().startsWith(s); // refuses 2026-02-30
}

Never _invalid(String what) => throw FormatException('invalid $what');

/// Built-in category for transfers; added to older data automatically.
const transferCategory = Category(name: 'Transferência', type: transferType, color: '#6B6B72');

enum AccountKind { current, spending, savings, investment }

/// One of the user's bank / broker accounts. Its balance is [openingBalance]
/// plus every paid movement on it.
class Account {
  const Account({required this.id, required this.name, this.kind = AccountKind.current, this.openingBalance = 0});
  final String id, name;
  final AccountKind kind;
  final int openingBalance;

  /// Savings and investments: money moved there counts as "saved", not spent.
  bool get isSavings => kind == AccountKind.savings || kind == AccountKind.investment;

  static const mainName = 'Conta principal';
  static const main = Account(id: 'main', name: mainName);

  Account copyWith({String? name, AccountKind? kind, int? openingBalance}) => Account(
      id: id, name: name ?? this.name, kind: kind ?? this.kind, openingBalance: openingBalance ?? this.openingBalance);

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: AccountKind.values.asNameMap()[j['kind']] ?? AccountKind.current,
        openingBalance: (j['openingBalance'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind.name, 'openingBalance': openingBalance};
}

class Category {
  const Category({required this.name, required this.type, required this.color, this.budget});
  final String name;
  final String type; // 'Entrada' | 'Saída'
  final String color; // '#RRGGBB'

  /// Spending limit per cycle, in cents; null = no budget.
  final int? budget;

  Category withBudget(int? cents) => Category(name: name, type: type, color: color, budget: cents);

  factory Category.fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String, color = j['color'] as String, budget = (j['budget'] as num?)?.toInt();
    if (!const {'Entrada', 'Saída', transferType}.contains(type)) _invalid('category type');
    if (!_hexColor.hasMatch(color)) _invalid('category colour');
    if (budget != null && (budget < 0 || budget > maxCents)) _invalid('budget');
    return Category(name: j['name'] as String, type: type, color: color, budget: budget);
  }
  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'color': color, if (budget != null) 'budget': budget};
}

/// What a fixed bill does when its day is a weekend or national holiday.
enum DayShift { none, before, after }

// `from` / `to` are cycle ids (inclusive), the month the cycle ends in.
class Recurring {
  const Recurring({
    required this.id,
    required this.description,
    required this.category,
    required this.cents,
    required this.day,
    this.variable = false,
    this.from,
    this.to,
    this.shift = DayShift.none,
    this.account,
    this.toAccount,
  });
  final String id, description, category;

  /// Which account it's paid from (or into); null = the first account.
  final String? account;

  /// For a transfer: the account the money goes to.
  final String? toAccount;
  final int cents, day;
  final bool variable;
  final String? from, to;
  final DayShift shift;

  Recurring withCategory(String c) => Recurring(
      id: id, description: description, category: c, cents: cents, day: day, variable: variable,
      from: from, to: to, shift: shift, account: account, toAccount: toAccount);

  factory Recurring.fromJson(Map<String, dynamic> j) {
    final cents = (j['cents'] as num).toInt(), day = (j['day'] as num).toInt();
    final from = j['from'] as String?, to = j['to'] as String?;
    if (cents < 0 || cents > maxCents) _invalid('amount');
    if (day < 1 || day > 31) _invalid('day');
    if ((from != null && !_cycleId.hasMatch(from)) || (to != null && !_cycleId.hasMatch(to))) _invalid('cycle');
    return Recurring(
      id: j['id'] as String,
      description: j['description'] as String,
      category: j['category'] as String,
      cents: cents,
      day: day,
      variable: j['variable'] == true,
      from: from,
      to: to,
      shift: DayShift.values.asNameMap()[j['shift']] ?? DayShift.none,
      account: j['account'] as String?,
      toAccount: j['toAccount'] as String?,
    );
  }
  Map<String, dynamic> toJson() => {
        'id': id, 'description': description, 'category': category, 'cents': cents, 'day': day,
        if (variable) 'variable': true,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (shift != DayShift.none) 'shift': shift.name,
        if (account != null) 'account': account,
        if (toAccount != null) 'toAccount': toAccount,
      };
}

class Movement {
  Movement({
    required this.id,
    required this.date,
    required this.description,
    required this.category,
    required this.cents,
    required this.estado,
    this.gen = false,
    this.cycle,
    this.edited = false,
    this.account,
    this.toAccount,
  });
  final String id;

  /// The account it's on (null = the first account); for a transfer, where the money leaves.
  final String? account;

  /// For a transfer: where the money arrives.
  final String? toAccount;
  final String date; // YYYY-MM-DD

  /// Set when the movement belongs to a different cycle than its date says:
  /// a salary due on the cycle's first day but paid the business day before.
  final String? cycle;
  final String description, category;
  final int cents;
  String estado; // 'Pago' | 'Previsto'
  final bool gen;

  /// A planned bill the user changed by hand: editing the bill won't overwrite it.
  final bool edited;

  /// A copy with the user's changes. Moving the date drops any cycle override.
  Movement copyWith(
          {String? date,
          String? description,
          String? category,
          int? cents,
          String? estado,
          String? account,
          String? toAccount,
          bool clearToAccount = false}) =>
      Movement(
        id: id,
        date: date ?? this.date,
        description: description ?? this.description,
        category: category ?? this.category,
        cents: cents ?? this.cents,
        estado: estado ?? this.estado,
        gen: gen,
        cycle: date == null || date == this.date ? cycle : null,
        edited: gen,
        account: account ?? this.account,
        toAccount: clearToAccount ? null : (toAccount ?? this.toAccount),
      );

  /// Same movement under another category; unlike [copyWith] it does not count as a hand edit.
  Movement withCategory(String c) => Movement(
      id: id, date: date, description: description, category: c, cents: cents, estado: estado, gen: gen,
      cycle: cycle, edited: edited, account: account, toAccount: toAccount);

  factory Movement.fromJson(Map<String, dynamic> j) {
    final date = j['date'] as String, estado = j['estado'] as String, cycle = j['cycle'] as String?;
    final cents = (j['cents'] as num).toInt();
    if (!_isDate(date)) _invalid('date');
    if (estado != 'Pago' && estado != 'Previsto') _invalid('status');
    if (cents < 0 || cents > maxCents) _invalid('amount');
    if (cycle != null && !_cycleId.hasMatch(cycle)) _invalid('cycle');
    return Movement(
      id: j['id'] as String,
      date: date,
      description: j['description'] as String,
      category: j['category'] as String,
      cents: cents,
      estado: estado,
      gen: j['gen'] == true,
      cycle: cycle,
      edited: j['edited'] == true,
      account: j['account'] as String?,
      toAccount: j['toAccount'] as String?,
    );
  }
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'description': description, 'category': category,
        'cents': cents, 'estado': estado,
        if (gen) 'gen': true,
        if (cycle != null) 'cycle': cycle,
        if (edited) 'edited': true,
        if (account != null) 'account': account,
        if (toAccount != null) 'toAccount': toAccount,
      };
}

class Config {
  const Config({
    required this.cycleStartDay,
    required this.openingBalance,
    this.language,
    this.currency = 'EUR',
    this.holidays = 'PT',
    this.lastBackup,
  });
  final int cycleStartDay, openingBalance;

  /// Date (YYYY-MM-DD) the data was last exported as a file; null = never.
  final String? lastBackup;

  /// 'pt' / 'en'; null follows the device language.
  final String? language;

  /// ISO 4217 code, e.g. 'EUR'.
  final String currency;

  /// Whose national holidays count as non-business days ('PT'), or 'none' for weekends only.
  final String holidays;

  Config copyWith(
          {int? cycleStartDay,
          int? openingBalance,
          String? language,
          bool clearLanguage = false,
          String? currency,
          String? holidays,
          String? lastBackup}) =>
      Config(
        cycleStartDay: cycleStartDay ?? this.cycleStartDay,
        openingBalance: openingBalance ?? this.openingBalance,
        language: clearLanguage ? null : (language ?? this.language),
        currency: currency ?? this.currency,
        holidays: holidays ?? this.holidays,
        lastBackup: lastBackup ?? this.lastBackup,
      );

  factory Config.fromJson(Map<String, dynamic> j) {
    final day = (j['cycleStartDay'] as num).toInt(), currency = (j['currency'] as String?) ?? 'EUR';
    if (day < 1 || day > 28) _invalid('cycle start day');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) _invalid('currency');
    final lastBackup = j['lastBackup'] as String?;
    if (lastBackup != null && !_isDate(lastBackup)) _invalid('date');
    return Config(
      cycleStartDay: day,
      openingBalance: (j['openingBalance'] as num).toInt(),
      language: j['language'] as String?,
      currency: currency,
      holidays: (j['holidays'] as String?) ?? 'PT',
      lastBackup: lastBackup,
    );
  }
  Map<String, dynamic> toJson() => {
        'cycleStartDay': cycleStartDay,
        'openingBalance': openingBalance,
        if (language != null) 'language': language,
        'currency': currency,
        'holidays': holidays,
        if (lastBackup != null) 'lastBackup': lastBackup,
      };
}

/// A savings goal: an amount to reach in a savings account, optionally fed by an automatic transfer
/// of [perCycle] on payday.
class Goal {
  const Goal({required this.id, required this.name, required this.account, required this.target, this.perCycle = 0});
  final String id, name, account;
  final int target, perCycle;

  /// Id of the fixed transfer that feeds this goal.
  String get billId => 'rgoal_$id';

  Goal copyWith({int? perCycle}) =>
      Goal(id: id, name: name, account: account, target: target, perCycle: perCycle ?? this.perCycle);

  factory Goal.fromJson(Map<String, dynamic> j) {
    final target = (j['target'] as num).toInt(), per = (j['perCycle'] as num?)?.toInt() ?? 0;
    if (target < 0 || target > maxCents || per < 0 || per > maxCents) _invalid('goal amount');
    return Goal(id: j['id'] as String, name: j['name'] as String, account: j['account'] as String, target: target, perCycle: per);
  }
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'account': account, 'target': target, 'perCycle': perCycle};
}

class AppState {
  AppState({
    required this.config,
    required List<Category> categories,
    required this.recurring,
    required this.movements,
    List<Account>? accounts,
    List<Goal>? goals,
  })  : categories = [...categories, if (!categories.any((c) => c.type == transferType)) transferCategory],
        accounts = accounts == null || accounts.isEmpty ? [Account.main] : [...accounts],
        goals = [...?goals] {
    // older data kept one opening balance in the config: it belongs to the first account now
    if (config.openingBalance != 0) {
      this.accounts[0] =
          this.accounts[0].copyWith(openingBalance: this.accounts[0].openingBalance + config.openingBalance);
      config = config.copyWith(openingBalance: 0);
    }
  }
  Config config;
  final List<Category> categories;
  List<Account> accounts;
  List<Goal> goals;

  /// Movements and bills without an account belong to the first one.
  String get defaultAccount => accounts.first.id;
  Account? accountById(String? id) => accounts.where((a) => a.id == (id ?? defaultAccount)).firstOrNull;
  final List<Recurring> recurring;
  List<Movement> movements;

  static List<Map<String, dynamic>> _list(Object? v) =>
      (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // Throws FormatException when the document is not a version-1 backup.
  factory AppState.fromJson(Object? json) {
    if (json is! Map || json['version'] != 1 || json['config'] is! Map ||
        json['categories'] is! List || json['recurring'] is! List || json['movements'] is! List) {
      throw const FormatException('invalid backup');
    }
    try {
      return AppState(
        config: Config.fromJson(Map<String, dynamic>.from(json['config'] as Map)),
        categories: _list(json['categories']).map(Category.fromJson).toList(),
        recurring: _list(json['recurring']).map(Recurring.fromJson).toList(),
        movements: _list(json['movements']).map(Movement.fromJson).toList(),
        accounts: json['accounts'] is List ? _list(json['accounts']).map(Account.fromJson).toList() : null,
        goals: json['goals'] is List ? _list(json['goals']).map(Goal.fromJson).toList() : null,
      );
    } catch (_) {
      throw const FormatException('invalid backup');
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'config': config.toJson(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'recurring': recurring.map((r) => r.toJson()).toList(),
        'movements': movements.map((m) => m.toJson()).toList(),
        'accounts': accounts.map((a) => a.toJson()).toList(),
        if (goals.isNotEmpty) 'goals': goals.map((g) => g.toJson()).toList(),
      };
}
