// Data shapes. The JSON matches the PWA's store (version 1), so a backup
// exported from one app can be imported into the other.

/// Category type of transfers between the user's own accounts.
const transferType = 'Transferência';

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
  const Category({required this.name, required this.type, required this.color});
  final String name;
  final String type; // 'Entrada' | 'Saída'
  final String color; // '#RRGGBB'

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(name: j['name'] as String, type: j['type'] as String, color: j['color'] as String);
  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'color': color};
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

  factory Recurring.fromJson(Map<String, dynamic> j) => Recurring(
        id: j['id'] as String,
        description: j['description'] as String,
        category: j['category'] as String,
        cents: (j['cents'] as num).toInt(),
        day: (j['day'] as num).toInt(),
        variable: j['variable'] == true,
        from: j['from'] as String?,
        to: j['to'] as String?,
        shift: DayShift.values.asNameMap()[j['shift']] ?? DayShift.none,
        account: j['account'] as String?,
        toAccount: j['toAccount'] as String?,
      );
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

  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
        id: j['id'] as String,
        date: j['date'] as String,
        description: j['description'] as String,
        category: j['category'] as String,
        cents: (j['cents'] as num).toInt(),
        estado: j['estado'] as String,
        gen: j['gen'] == true,
        cycle: j['cycle'] as String?,
        edited: j['edited'] == true,
        account: j['account'] as String?,
        toAccount: j['toAccount'] as String?,
      );
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
  });
  final int cycleStartDay, openingBalance;

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
          String? holidays}) =>
      Config(
        cycleStartDay: cycleStartDay ?? this.cycleStartDay,
        openingBalance: openingBalance ?? this.openingBalance,
        language: clearLanguage ? null : (language ?? this.language),
        currency: currency ?? this.currency,
        holidays: holidays ?? this.holidays,
      );

  factory Config.fromJson(Map<String, dynamic> j) => Config(
        cycleStartDay: (j['cycleStartDay'] as num).toInt(),
        openingBalance: (j['openingBalance'] as num).toInt(),
        language: j['language'] as String?,
        currency: (j['currency'] as String?) ?? 'EUR',
        holidays: (j['holidays'] as String?) ?? 'PT',
      );
  Map<String, dynamic> toJson() => {
        'cycleStartDay': cycleStartDay,
        'openingBalance': openingBalance,
        if (language != null) 'language': language,
        'currency': currency,
        'holidays': holidays,
      };
}

class AppState {
  AppState({
    required this.config,
    required List<Category> categories,
    required this.recurring,
    required this.movements,
    List<Account>? accounts,
  })  : categories = [...categories, if (!categories.any((c) => c.type == transferType)) transferCategory],
        accounts = accounts == null || accounts.isEmpty ? [Account.main] : [...accounts] {
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
      };
}
