import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'importar.dart';

class MovimentosScreen extends StatelessWidget {
  const MovimentosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final m = app.model;
    final c = m.cycle;
    final acc = app.accountFilter;
    final q = app.search.trim().toLowerCase();
    final searching = q.isNotEmpty;
    // a search looks through every cycle, newest first
    final Iterable<Movement> source =
        searching ? sortMovements(m.state.movements, typesOf(m.state)).reversed : c.items;
    final items = source.where((x) =>
        (app.filter == 'Todos' || x.estado == app.filter) &&
        (acc == null || (x.account ?? m.state.defaultAccount) == acc || x.toAccount == acc) &&
        (!searching || x.description.toLowerCase().contains(q) || s.category(x.category).toLowerCase().contains(q)));
    final groups = <(String, List<Movement>)>[];
    for (final it in items) {
      if (groups.isNotEmpty && groups.last.$1 == it.date) {
        groups.last.$2.add(it);
      } else {
        groups.add((it.date, [it]));
      }
    }

    final desk = isDesktop(context);
    final rowsList = desk ? items.toList() : const <Movement>[];
    final importButton = IconButton(
      tooltip: s.importStatement,
      color: Palette.muted,
      icon: const Icon(Icons.upload_file),
      onPressed: () => openImport(context),
    );
    final searchField = TextField(
      key: const ValueKey('search'),
      onChanged: app.setSearch,
      decoration: InputDecoration(
        hintText: s.searchHint,
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
    final statusPills = [
      for (final f in const ['Todos', 'Pago', 'Previsto'])
        PillChip(label: f == 'Todos' ? s.all : s.estado(f), selected: app.filter == f, onTap: () => app.setFilter(f)),
    ];
    final accountPills = [
      for (final a in [null, ...m.state.accounts])
        PillChip(
          label: a == null ? s.accounts : s.accountName(a),
          selected: acc == a?.id,
          onTap: () => app.setAccountFilter(a?.id),
        ),
    ];

    return ScreenList(
      maxWidth: 760,
      children: [
        TopRow(children: [
          H1(s.navMovements),
          // desktop keeps the two tools together on the right; narrow screens let them wrap
          if (desk) Row(mainAxisSize: MainAxisSize.min, children: [importButton, CyclePicker(m)]) else ...[importButton, CyclePicker(m)],
        ]),
        const SizedBox(height: 6),
        Text('${cycleLabel(c.id, app.lang)} · ${s.movementCount(c.items.length)}',
            style: mono(size: 12, color: Palette.muted)),
        const SizedBox(height: 16),
        if (desk) ...[
          // desktop: search and filters on one line, then a table with a column per field
          Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 340, child: searchField),
            ...statusPills,
            if (m.multiAccount) ...accountPills,
          ]),
          const SizedBox(height: 22),
          const _TableHeader(),
          for (final mv in rowsList) _MovementTableRow(mv, m),
          if (rowsList.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(searching ? s.noMatches : s.noMovements, style: const TextStyle(fontSize: 14, color: Palette.muted)),
            ),
        ] else ...[
          searchField,
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final p in statusPills) Padding(padding: const EdgeInsets.only(right: 8), child: p)]),
          ),
          if (m.multiAccount) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final p in accountPills) Padding(padding: const EdgeInsets.only(right: 8), child: p)]),
            ),
          ],
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(searching ? s.noMatches : s.noMovements, style: const TextStyle(fontSize: 14, color: Palette.muted)),
            ),
          for (final (date, list) in groups) ...[
            const SizedBox(height: 22),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Lbl('${formatDay(date, app.lang)} · ${weekday(date, app.lang)}')),
            for (final mv in list) MovementRow(mv, m),
          ],
        ],
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line2))),
      child: Row(children: [
        const SizedBox(width: 20),
        Expanded(flex: 2, child: Lbl(s.colDate)),
        Expanded(flex: 6, child: Lbl(s.description)),
        Expanded(flex: 3, child: Lbl(s.categoryLabel)),
        if (app.model.multiAccount) Expanded(flex: 3, child: Lbl(s.account)),
        Expanded(flex: 2, child: Lbl(s.colStatus)),
        Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Lbl(s.amount))),
      ]),
    );
  }
}

class _MovementTableRow extends StatelessWidget {
  const _MovementTableRow(this.mv, this.m);
  final Movement mv;
  final Model m;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final income = m.isIncome(mv.category);
    final transfer = mv.toAccount != null && m.isTransferCategory(mv.category);
    String acc(String? id) => s.accountName(m.state.accountById(id) ?? m.state.accounts.first);
    const muted = TextStyle(fontSize: 13, color: Palette.muted);
    return InkWell(
      onTap: () => showMovementActions(context, mv),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
        child: Row(children: [
          SizedBox(width: 20, child: Dot(m.colorOf(mv.category))),
          Expanded(flex: 2, child: Text(formatDay(mv.date, app.lang), style: mono(size: 13, color: Palette.soft))),
          Expanded(flex: 6, child: Text(mv.description, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text(s.category(mv.category), style: muted, overflow: TextOverflow.ellipsis)),
          if (m.multiAccount)
            Expanded(
                flex: 3,
                child: Text(transfer ? s.transferLabel(acc(mv.account), acc(mv.toAccount)) : acc(mv.account),
                    style: muted, overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 2,
              child: Text(s.estado(mv.estado).toUpperCase(),
                  style: mono(size: 11, weight: FontWeight.w500, color: mv.estado == 'Pago' ? Palette.muted : Palette.warn)
                      .copyWith(letterSpacing: 0.4))),
          Expanded(
              flex: 2,
              child: Text('${transfer ? '⇄ ' : (income ? '+' : '−')}${app.money.amount(mv.cents)}',
                  textAlign: TextAlign.right,
                  style: mono(color: income ? Palette.accent : (transfer ? Palette.muted : Palette.text)))),
        ]),
      ),
    );
  }
}
