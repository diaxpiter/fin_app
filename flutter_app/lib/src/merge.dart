// Three-way merge of the user's data when two devices edited it between syncs.
// Nothing is dropped silently: each list is merged item by item, and when both
// sides changed the same item the local (newest) edit wins.

import 'dart:convert';

import 'models.dart';

/// [base] is the last copy both sides agreed on, [local] has unsynced edits, [remote] came from the server.
AppState mergeStates(AppState base, AppState local, AppState remote) {
  final b = base.toJson(), l = local.toJson(), r = remote.toJson();
  bool same(Object? x, Object? y) => jsonEncode(x) == jsonEncode(y);

  List<Object?> mergeList(String key, String idKey) {
    Map<String, Object?> byId(Map<String, dynamic> j) =>
        {for (final e in (j[key] as List?) ?? const []) (e as Map)[idKey] as String: e};
    final bm = byId(b), lm = byId(l), rm = byId(r);
    final out = <Object?>[];
    for (final id in {...lm.keys, ...rm.keys}) {
      final inBase = bm.containsKey(id);
      final mine = lm[id], theirs = rm[id];
      if (mine != null && theirs != null) {
        // changed only on one side → that side; on both → local
        out.add(inBase && same(mine, bm[id]) ? theirs : mine);
      } else if (mine != null) {
        // gone remotely: keep only what is new here or was edited here
        if (!inBase || !same(mine, bm[id])) out.add(mine);
      } else if (theirs != null) {
        // deleted here: keep only what is new there or was edited there
        if (!inBase || !same(theirs, bm[id])) out.add(theirs);
      }
    }
    return out;
  }

  return AppState.fromJson({
    'version': 1,
    'config': same(l['config'], b['config']) ? r['config'] : l['config'],
    'categories': mergeList('categories', 'name'),
    'recurring': mergeList('recurring', 'id'),
    'movements': mergeList('movements', 'id'),
    'accounts': mergeList('accounts', 'id'),
    'goals': mergeList('goals', 'id'),
  });
}
