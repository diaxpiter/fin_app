import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../account.dart';
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

    final containsToday = c.start.compareTo(m.today) <= 0 && c.end.compareTo(m.today) >= 0;
    // Nothing planned yet in today's cycle: the app shows the next one, and the same sum holds for it.
    final todayEmpty = m.cycles.every((x) => x.start.compareTo(m.today) > 0 || x.end.compareTo(m.today) < 0 || x.items.isEmpty);
    final nextId = m.cycles.where((x) => x.start.compareTo(m.today) > 0).firstOrNull?.id;
    final current = containsToday || (todayEmpty && c.id == nextId);
    final safe = safeToSpend(m.state, c);
    final days = daysLeftIn(c.end, containsToday ? m.today : c.start);
    final warnings = <(String, bool)>[];
    if (current) {
      final spentBy = {for (final e in spendByCategory(m.state, c)) e.key: e.value};
      for (final cat in m.state.categories) {
        final b = cat.budget, sp = spentBy[cat.name] ?? 0;
        if (b == null || b == 0) continue;
        if (sp > b) {
          warnings.add((s.budgetOver(s.category(cat.name), app.money.amount(sp - b)), true));
        } else if (sp * 100 >= b * 80) {
          warnings.add((s.budgetNear(s.category(cat.name), (sp * 100 / b).round()), false));
        }
      }
    }

    // the data lives only on this device: nag gently when there is no recent file backup
    final lastBackup = m.state.config.lastBackup;
    final backupDue = AccountScope.of(context).status == AccountStatus.guest &&
        m.state.movements.isNotEmpty &&
        (lastBackup == null || DateTime.parse(m.today).difference(DateTime.parse(lastBackup)).inDays > 30);

    final summary = <Widget>[
      if (backupDue)
        InkWell(
          onTap: () => openAjustes(context),
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('⚠ ${s.backupDue}', style: const TextStyle(fontSize: 13, color: Palette.warn)),
          ),
        ),
      if (current) ...[
        const SizedBox(height: 28),
        Lbl(s.safeToSpend),
        const SizedBox(height: 14),
        BigAmount(safe, size: wide ? 80 : 68, color: safe < 0 ? Palette.neg : Palette.accent),
        const SizedBox(height: 12),
        Text(safe > 0 ? s.safePerDay(app.money.amount(safe ~/ days), days) : s.safeHint,
            style: const TextStyle(fontSize: 14, color: Palette.muted, height: 1.4)),
        for (final (text, over) in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ $text', style: TextStyle(fontSize: 13, color: over ? Palette.neg : Palette.warn)),
          ),
      ],
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
        // one account: tap to set how much is in it today (with several, use the list below)
        (s.inAccount, cashNow(m.state), Palette.text, m.multiAccount ? null : () => editBalance(context)),
        (s.lowest, c.lowest, Palette.text, null),
        if (m.state.accounts.any((a) => a.isSavings)) (s.savedInvested, c.saved, Palette.accent, null),
      ]),
      if (m.multiAccount) ...[
        const SizedBox(height: 24),
        Text(s.accounts, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const AccountsList(showAdd: false),
      ],
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
      _WeekCard(weekSummary(m.state, m.today)),
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

/// The last seven days of spending against the seven before, and the bills due next week.
class _WeekCard extends StatelessWidget {
  const _WeekCard(this.week);
  final WeekSummary week;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    if (week.spent == 0 && week.previous == 0 && week.dueCount == 0) return const SizedBox.shrink();
    final delta = week.previous > 0 ? ((week.spent - week.previous) / week.previous * 100).round() : null;
    final tallest = math.max(1, week.days.reduce(math.max));
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Lbl(s.thisWeek),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(app.money.amount(week.spent), style: mono(size: 22, weight: FontWeight.w500)),
          if (delta != null && delta != 0) ...[
            const SizedBox(width: 10),
            Text(s.vsLastWeek(delta), style: TextStyle(fontSize: 12, color: delta > 0 ? Palette.neg : Palette.accent)),
          ],
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < week.days.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    height: math.max(3, 44 * week.days[i] / tallest),
                    decoration: BoxDecoration(
                      color: i == week.days.length - 1 ? Palette.accent : Palette.accent.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        if (week.dueCount > 0) ...[
          const SizedBox(height: 14),
          Text(s.dueNextWeek(week.dueCount, app.money.amount(week.dueTotal)),
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ],
      ]),
    );
  }
}
