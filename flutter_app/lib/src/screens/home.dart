import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ajustes.dart';
import 'preferences.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final lang = app.lang;
    final m = app.model;
    final c = m.cycle;
    final size = sizeClassOf(context);
    final wide = size == SizeClass.expanded;

    int pct(int v) => c.receitas > 0 ? math.min(100, (v / c.receitas * 100).round()) : 0;
    final paid = pct(c.pago);
    final planned = math.max(0, pct(c.pago + c.porPagar) - paid);
    final empty = c.items.isEmpty;
    final upcoming = c.items
        .where((x) => !m.isIncome(x.category) && x.estado == 'Previsto' && x.date.compareTo(m.today) >= 0)
        .take(wide ? 8 : 3)
        .toList();

    final summary = <Widget>[
      const SizedBox(height: 28),
      Lbl(s.leftThisCycle),
      const SizedBox(height: 14),
      BigAmount(c.sobra, size: wide ? 80 : 68, color: c.sobra < 0 ? Palette.neg : Palette.text),
      const SizedBox(height: 12),
      Text(
        '${empty ? s.noMovementsInCycle : s.pctOfIncome(c.savingsRate)} · ${s.todayIs(formatDay(m.today, lang))}',
        style: const TextStyle(fontSize: 14, color: Palette.muted, height: 1.4),
      ),
      const SizedBox(height: 28),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (paid > 0) Expanded(flex: paid, child: Container(color: Palette.accent)),
            if (planned > 0) Expanded(flex: planned, child: Container(color: Palette.planned)),
            if (100 - paid - planned > 0) Expanded(flex: 100 - paid - planned, child: Container(color: Palette.line)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: '● ', style: TextStyle(color: Palette.accent)),
          TextSpan(text: s.paidPct(paid)),
        ]), style: const TextStyle(fontSize: 12, color: Palette.muted)),
        Text(s.toPayPct(planned), style: const TextStyle(fontSize: 12, color: Palette.muted)),
      ]),
      const SizedBox(height: 24),
      _StatGrid(columns: size == SizeClass.medium ? 4 : 2, cells: [
        (s.income, c.receitas, Palette.text, null),
        (s.expenses, c.despesas, Palette.neg, null),
        // tap to set how much is in the account today
        (s.inAccount, cashNow(m.state), Palette.text, () => editBalance(context)),
        (s.lowest, c.lowest, Palette.text, null),
      ]),
    ];

    final next = <Widget>[
      SizedBox(height: wide ? 28 : 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
          child: Text(s.upcoming,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => app.setTab(1),
          style: TextButton.styleFrom(foregroundColor: Palette.muted),
          child: Text(s.seeAll, style: const TextStyle(fontSize: 13)),
        ),
      ]),
      if (upcoming.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(s.nothingToPay, style: const TextStyle(fontSize: 14, color: Palette.muted)),
        ),
      for (final x in upcoming)
        InfoRow(
          leading: Dot(m.colorOf(x.category)),
          title: Text(x.description, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis),
          trailing: [
            Text(formatDay(x.date, lang), style: mono(size: 12, color: Palette.muted)),
            SizedBox(width: 90, child: Text(app.money.amount(x.cents), style: mono(), textAlign: TextAlign.right)),
          ],
        ),
    ];

    return ScreenList(
      maxWidth: wide ? 1100 : 640,
      children: [
        TopRow(children: [
          CyclePicker(m),
          IconButton(
            tooltip: s.settings,
            color: Palette.muted,
            icon: const Icon(Icons.tune),
            onPressed: () => openAjustes(context),
          ),
        ]),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: summary)),
            const SizedBox(width: 56),
            Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: next)),
          ])
        else ...[
          ...summary,
          ...next,
        ],
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cells, required this.columns});
  final List<(String, int, Color, VoidCallback?)> cells;
  final int columns;

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: Palette.line);
    final rows = <List<(String, int, Color, VoidCallback?)>>[
      for (var i = 0; i < cells.length; i += columns) cells.sublist(i, math.min(i + columns, cells.length)),
    ];
    return Container(
      decoration: const BoxDecoration(border: Border(top: side, left: side)),
      child: Column(children: [
        for (final row in rows)
          Row(children: [
            for (final (label, cents, color, onTap) in row)
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(border: Border(right: side, bottom: side)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Lbl(label),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(AppScope.of(context).money.amount(cents),
                            style: mono(size: 20, weight: FontWeight.w500, color: color)),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
      ]),
    );
  }
}
