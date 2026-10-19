import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class MovimentosScreen extends StatelessWidget {
  const MovimentosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final m = app.model;
    final c = m.cycle;
    final acc = app.accountFilter;
    final items = c.items.where((x) =>
        (app.filter == 'Todos' || x.estado == app.filter) &&
        (acc == null || (x.account ?? m.state.defaultAccount) == acc || x.toAccount == acc));
    final groups = <(String, List<Movement>)>[];
    for (final it in items) {
      if (groups.isNotEmpty && groups.last.$1 == it.date) {
        groups.last.$2.add(it);
      } else {
        groups.add((it.date, [it]));
      }
    }

    return ScreenList(
      maxWidth: 760,
      children: [
        TopRow(children: [H1(s.navMovements), CyclePicker(m)]),
        const SizedBox(height: 6),
        Text('${cycleLabel(c.id, app.lang)} · ${s.movementCount(c.items.length)}',
            style: mono(size: 12, color: Palette.muted)),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in const ['Todos', 'Pago', 'Previsto'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PillChip(
                    label: f == 'Todos' ? s.all : s.estado(f), selected: app.filter == f, onTap: () => app.setFilter(f)),
              ),
          ]),
        ),
        if (m.multiAccount) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final a in [null, ...m.state.accounts])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillChip(
                    label: a == null ? s.accounts : s.accountName(a),
                    selected: acc == a?.id,
                    onTap: () => app.setAccountFilter(a?.id),
                  ),
                ),
            ]),
          ),
        ],
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(s.noMovements, style: const TextStyle(fontSize: 14, color: Palette.muted)),
          ),
        for (final (date, list) in groups) ...[
          const SizedBox(height: 22),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Lbl('${formatDay(date, app.lang)} · ${weekday(date, app.lang)}')),
          for (final mv in list) MovementRow(mv, m),
        ],
      ],
    );
  }
}
