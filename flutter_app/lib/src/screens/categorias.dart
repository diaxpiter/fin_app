import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../i18n.dart';
import '../layout.dart';
import '../logic.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Where the cycle's money went, with an optional spending limit per category.
class CategoriasScreen extends StatelessWidget {
  const CategoriasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final m = app.model;
    final i = m.cycles.indexWhere((c) => c.id == m.cycle.id);
    final prevOf = i > 0 ? {for (final e in spendByCategory(m.state, m.cycles[i - 1])) e.key: e.value} : <String, int>{};
    final spend = spendByCategory(m.state, m.cycle);
    final spentOf = {for (final e in spend) e.key: e.value};
    final total = spend.fold<int>(0, (a, e) => a + e.value);
    // every expense category, so a budget can be set before the first purchase
    final rows = [
      ...spend.map((e) => e.key),
      for (final c in m.state.categories)
        if (c.type == 'Saída' && !spentOf.containsKey(c.name)) c.name,
    ];
    final budgets = {for (final c in m.state.categories) if (c.budget != null) c.name: c.budget!};
    final budgeted = budgets.values.fold<int>(0, (a, b) => a + b);
    final spentInBudgets = budgets.keys.fold<int>(0, (a, k) => a + (spentOf[k] ?? 0));
    final suggestions = {
      for (final name in rows)
        if (!budgets.containsKey(name))
          if (suggestedBudget(m.state, m.cycles, m.cycle.id, name) case final v?) name: v
    };

    return ScreenList(
      maxWidth: 640,
      children: [
        TopRow(children: [H1(s.navCategories), CyclePicker(m)]),
        const SizedBox(height: 20),
        Lbl(s.spendingByCategory),
        const SizedBox(height: 16),
        if (total == 0)
          Text(s.noSpending, style: const TextStyle(fontSize: 14, color: Palette.muted))
        else
          Center(
            child: Semantics(
              label:
                  '${s.spendingByCategory}: ${spend.map((e) => '${s.category(e.key)} ${app.money.amount(e.value)}').join(', ')}',
              child: SizedBox(
                width: 190,
                height: 190,
                child: CustomPaint(
                  painter: _DonutPainter([for (final e in spend) (e.value, m.colorOf(e.key))]),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Lbl(s.spent),
                      const SizedBox(height: 6),
                      Text(app.money.amount(total), style: mono(size: 20, weight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        if (budgets.isNotEmpty)
          _BudgetSummary(spent: spentInBudgets, budget: budgeted)
        else if (suggestions.isNotEmpty)
          _SuggestCard(suggestions: suggestions),
        for (final name in rows)
          _CategoryRow(
            name: name,
            spent: spentOf[name] ?? 0,
            total: total,
            before: prevOf[name],
            budget: budgets[name],
          ),
        const SizedBox(height: 24),
        Lbl(s.categoriesTitle),
        const SizedBox(height: 10),
        const CategoryManager(),
      ],
    );
  }
}

/// All budgets together: how much of the total is used.
class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({required this.spent, required this.budget});
  final int spent, budget;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final over = spent > budget;
    final ratio = budget == 0 ? 0.0 : math.min(1.0, spent / budget);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Lbl(s.budgetsTitle),
        const SizedBox(height: 10),
        Text(s.budgetUsed(app.money.amount(spent), app.money.amount(budget)),
            style: mono(size: 18, weight: FontWeight.w500, color: over ? Palette.neg : Palette.text)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(children: [
              Container(color: Palette.line2),
              FractionallySizedBox(
                  widthFactor: ratio, child: Container(color: over ? Palette.neg : (ratio >= 0.8 ? Palette.warn : Palette.accent))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(over ? s.overBy(app.money.amount(spent - budget)) : s.budgetLeft(app.money.amount(budget - spent)),
            style: TextStyle(fontSize: 12, color: over ? Palette.neg : Palette.muted)),
      ]),
    );
  }
}

/// One tap sets a sensible budget for every category that has history.
class _SuggestCard extends StatelessWidget {
  const _SuggestCard({required this.suggestions});
  final Map<String, int> suggestions;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.suggestTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(s.suggestBody, style: const TextStyle(fontSize: 13, height: 1.4, color: Palette.muted)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            app.store.setBudgets(suggestions);
            toast(context, s.suggestDone(suggestions.length));
          },
          style: FilledButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Palette.bg),
          child: Text(s.suggestAction(suggestions.length)),
        ),
      ]),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow(
      {required this.name, required this.spent, required this.total, required this.before, required this.budget});
  final String name;
  final int spent, total;
  final int? before, budget;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final color = app.model.colorOf(name);
    final over = budget != null && spent > budget!;
    final ratio = budget == null || budget == 0 ? 0.0 : math.min(1.0, spent / budget!);
    final barColor = over ? Palette.neg : (ratio >= 0.8 ? Palette.warn : color);
    final delta = before != null && before! > 0 ? ((spent - before!) / before! * 100).round() : null;
    return InkWell(
      onTap: () => showBudgetSheet(context, name),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Dot(color),
            const SizedBox(width: 12),
            Expanded(child: Text(s.category(name), style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
            if (delta != null && delta != 0)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text('${delta > 0 ? '▲' : '▼'} ${delta.abs()}%',
                    style: mono(size: 12, color: delta > 0 ? Palette.neg : Palette.accent)),
              ),
            Text(app.money.amount(spent), style: mono()),
            SizedBox(
                width: 48,
                child: Text(total > 0 ? '${(spent / total * 100).round()}%' : '',
                    textAlign: TextAlign.right, style: mono(size: 12, color: Palette.muted))),
          ]),
          const SizedBox(height: 8),
          if (budget != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(children: [
                  Container(color: Palette.line2),
                  FractionallySizedBox(widthFactor: ratio, child: Container(color: barColor)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              over
                  ? s.budgetOver(s.category(name), app.money.amount(spent - budget!))
                  : '${s.budgetUsed(app.money.amount(spent), app.money.amount(budget!))} · ${s.budgetLeft(app.money.amount(budget! - spent))}',
              style: TextStyle(fontSize: 12, color: over ? Palette.neg : Palette.muted),
            ),
          ] else
            Row(children: [
              Icon(Icons.add_circle_outline, size: 14, color: Palette.accent.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(s.setBudget, style: TextStyle(fontSize: 12, color: Palette.accent.withValues(alpha: 0.8))),
            ]),
        ]),
      ),
    );
  }
}

/// Sets a category's spending limit per cycle, with this cycle's, last cycle's and the average
/// spending next to the field so the number isn't a guess. Empty removes the budget.
Future<void> showBudgetSheet(BuildContext context, String category) async {
  final app = AppScope.of(context, listen: false);
  final s = app.s;
  final m = app.model;
  final current = m.state.categories.firstWhere((c) => c.name == category).budget;
  final i = m.cycles.indexWhere((c) => c.id == m.cycle.id);
  int spentIn(int idx) => idx < 0
      ? 0
      : spendByCategory(m.state, m.cycles[idx]).where((e) => e.key == category).fold(0, (a, e) => a + e.value);
  final now = spentIn(i), prev = i > 0 ? spentIn(i - 1) : 0;
  final avg = suggestedBudget(m.state, m.cycles, m.cycle.id, category);
  final ctrl = TextEditingController(text: current == null ? '' : app.money.amount(current));

  Widget stat(String label, int cents) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Palette.muted)),
          Text(app.money.amount(cents), style: mono(size: 13)),
        ]),
      );

  final text = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.surface,
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Dot(m.colorOf(category)),
            const SizedBox(width: 10),
            Text(s.budgetFor(s.category(category)), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          stat(s.budgetThisCycle, now),
          if (i > 0) stat(s.budgetPrevCycle, prev),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [MoneyInputFormatter()],
            style: mono(size: 20),
            decoration: InputDecoration(labelText: s.budgetPerCycle, suffixText: app.money.symbol, border: const OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (avg != null)
              ActionChip(label: Text(s.budgetAverage(app.money.amount(avg))), onPressed: () => setSheet(() => ctrl.text = app.money.amount(avg))),
            if (prev > 0)
              ActionChip(label: Text(s.budgetPrevChip(app.money.amount(prev))), onPressed: () => setSheet(() => ctrl.text = app.money.amount(prev))),
          ]),
          const SizedBox(height: 6),
          Text(s.budgetHint, style: const TextStyle(fontSize: 12, height: 1.4, color: Palette.muted)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            if (current != null)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, ''),
                  style: TextButton.styleFrom(foregroundColor: Palette.neg),
                  child: Text(s.remove)),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(s.save)),
          ]),
        ]),
      ),
    ),
  );
  if (text == null) return;
  final cents = parseAmount(text);
  app.store.setBudget(category, cents == null || cents == 0 ? null : cents);
  if (context.mounted) toast(context, s.budgetSet);
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);
  final List<(int, Color)> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (a, e) => a + e.$1);
    if (total == 0) return;
    const stroke = 22.0;
    final arc = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    var start = -math.pi / 2;
    for (final (cents, color) in slices) {
      final sweep = cents / total * 2 * math.pi;
      canvas.drawArc(arc, start, math.max(0.0, sweep - 0.02), false, paint..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.slices.toString() != slices.toString();
}

const _swatches = [
  '#7AA2F7', '#E9B44C', '#B58CF5', '#FF7A64', '#5FD0A5', '#C8F169', '#F78FB3', '#4FC3D9', '#F2994A', '#9A9AA1',
];

/// Every category as a chip, grouped by kind: the cross deletes it, the last chip of each group adds one.
class CategoryManager extends StatelessWidget {
  const CategoryManager({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final store = app.store;
    Widget group(String label, String type) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 4),
              child: Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted))),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final c in store.state.categories.where((c) => c.type == type))
              InputChip(
                avatar: Dot(app.model.colorOf(c.name)),
                label: Text(s.category(c.name)),
                onDeleted: store.categoryHeir(c.name) == null ? null : () => _delete(context, c.name),
                deleteButtonTooltipMessage: s.delete,
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text(s.newCategory),
              onPressed: () => _add(context, type),
            ),
          ]),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      group(s.expenses, 'Saída'),
      const SizedBox(height: 8),
      group(s.income, 'Entrada'),
    ]);
  }

  Future<void> _delete(BuildContext context, String name) async {
    final app = AppScope.of(context, listen: false);
    final s = app.s;
    final heir = app.store.categoryHeir(name)!;
    final q = s.deleteCategoryQ(s.category(name), app.store.categoryUses(name), s.category(heir));
    if (!await confirm(context, q, s.delete)) return;
    app.store.removeCategory(name);
    if (context.mounted) toast(context, s.categoryDeleted);
  }

  Future<void> _add(BuildContext context, String type) {
    final app = AppScope.of(context, listen: false);
    final s = app.s;
    final name = TextEditingController();
    final used = app.store.state.categories.map((c) => c.color.toUpperCase()).toSet();
    var color = _swatches.firstWhere((c) => !used.contains(c), orElse: () => _swatches.first);
    String? error;
    return showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Palette.surface,
          title: Text(s.newCategory),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: Store.maxCategoryName,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: s.categoryName, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final c in _swatches)
                    Semantics(
                      button: true,
                      selected: c == color,
                      label: c,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => color = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: hexColor(c),
                            shape: BoxShape.circle,
                            border: Border.all(color: c == color ? Palette.text : Colors.transparent, width: 2),
                          ),
                        ),
                      ),
                    ),
                ]),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!, style: const TextStyle(color: Palette.neg, fontSize: 13)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            TextButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return setState(() => error = s.enterName);
                if (!app.store.addCategory(name.text, type, color)) return setState(() => error = s.categoryExists);
                Navigator.pop(ctx);
                toast(context, s.categorySaved);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }
}
