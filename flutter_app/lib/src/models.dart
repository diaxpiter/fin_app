// Data shapes. The JSON matches the PWA's store (version 1), so a backup
// exported from one app can be imported into the other.

class Category {
  const Category({required this.name, required this.type, required this.color});
  final String name;
  final String type; // 'Entrada' | 'Saída'
  final String color; // '#RRGGBB'

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(name: j['name'] as String, type: j['type'] as String, color: j['color'] as String);
  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'color': color};
}

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
  });
  final String id, description, category;
  final int cents, day;
  final bool variable;
  final String? from, to;

  factory Recurring.fromJson(Map<String, dynamic> j) => Recurring(
        id: j['id'] as String,
        description: j['description'] as String,
        category: j['category'] as String,
        cents: (j['cents'] as num).toInt(),
        day: (j['day'] as num).toInt(),
        variable: j['variable'] == true,
        from: j['from'] as String?,
        to: j['to'] as String?,
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'description': description, 'category': category, 'cents': cents, 'day': day,
        if (variable) 'variable': true,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
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
  });
  final String id;
  final String date; // YYYY-MM-DD
  final String description, category;
  final int cents;
  String estado; // 'Pago' | 'Previsto'
  final bool gen;

  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
        id: j['id'] as String,
        date: j['date'] as String,
        description: j['description'] as String,
        category: j['category'] as String,
        cents: (j['cents'] as num).toInt(),
        estado: j['estado'] as String,
        gen: j['gen'] == true,
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'description': description, 'category': category,
        'cents': cents, 'estado': estado,
        if (gen) 'gen': true,
      };
}

class Config {
  const Config({required this.cycleStartDay, required this.openingBalance});
  final int cycleStartDay, openingBalance;

  factory Config.fromJson(Map<String, dynamic> j) => Config(
        cycleStartDay: (j['cycleStartDay'] as num).toInt(),
        openingBalance: (j['openingBalance'] as num).toInt(),
      );
  Map<String, dynamic> toJson() => {'cycleStartDay': cycleStartDay, 'openingBalance': openingBalance};
}

class AppState {
  AppState({required this.config, required this.categories, required this.recurring, required this.movements});
  Config config;
  final List<Category> categories;
  final List<Recurring> recurring;
  List<Movement> movements;

  static List<Map<String, dynamic>> _list(Object? v) =>
      (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // Throws FormatException when the document is not a version-1 backup.
  factory AppState.fromJson(Object? json) {
    if (json is! Map || json['version'] != 1 || json['config'] is! Map ||
        json['categories'] is! List || json['recurring'] is! List || json['movements'] is! List) {
      throw const FormatException('Ficheiro inválido.');
    }
    try {
      return AppState(
        config: Config.fromJson(Map<String, dynamic>.from(json['config'] as Map)),
        categories: _list(json['categories']).map(Category.fromJson).toList(),
        recurring: _list(json['recurring']).map(Recurring.fromJson).toList(),
        movements: _list(json['movements']).map(Movement.fromJson).toList(),
      );
    } catch (_) {
      throw const FormatException('Ficheiro inválido.');
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'config': config.toJson(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'recurring': recurring.map((r) => r.toJson()).toList(),
        'movements': movements.map((m) => m.toJson()).toList(),
      };
}
