import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../i18n.dart';
import '../layout.dart';
import '../logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// What is yours: net worth over time and the goals being saved for.
class PoupancaScreen extends StatelessWidget {
  const PoupancaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final m = app.model;
    final todayCycle = cycleIdOf(m.today, m.state.config.cycle);
    final net = netWorth(m.state);
    final i = m.cycles.indexWhere((c) => c.id == todayCycle);
    final from = math.max(0, math.max(0, i) - 5);
    final window = m.cycles.sublist(from, math.min(m.cycles.length, from + 12));
    final rate = recentSavingsRate(m.cycles, todayCycle);
    final goals = m.state.goals;

    return ScreenList(
      maxWidth: 640,
      children: [
        TopRow(children: [
          H1(s.navSavings),
          FilledButton.icon(
            onPressed: () => showGoalEditor(context),
            style: FilledButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Palette.bg),
            icon: const Icon(Icons.add, size: 18),
            label: Text(s.newGoal),
          ),
        ]),
        const SizedBox(height: 24),
        Lbl(s.netWorth),
        const SizedBox(height: 14),
        BigAmount(net, size: 56, color: net < 0 ? Palette.neg : Palette.text),
        if (window.length >= 2) ...[
          const SizedBox(height: 18),
          Semantics(
            label: '${s.netWorth}: ${window.map((c) => '${cycleLabel(c.id, app.lang)} ${app.money.amount(c.endBalance)}').join(', ')}',
            child: SizedBox(
              height: 110,
              child: CustomPaint(
                size: Size.infinite,
                painter: _LinePainter([for (final c in window) c.endBalance], i < 0 ? null : i - from),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(cycleLabel(window.first.id, app.lang), style: mono(size: 11, color: Palette.muted)),
            Text(cycleLabel(window.last.id, app.lang), style: mono(size: 11, color: Palette.muted)),
          ]),
          const SizedBox(height: 4),
          Text(s.netWorthEnd(app.money.amount(window.last.endBalance)),
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ],
        if (rate != null) ...[
          const SizedBox(height: 10),
          Text(s.savedRate(rate), style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ],
        const SizedBox(height: 28),
        Lbl(s.goalsTitle),
        const SizedBox(height: 6),
        if (goals.isEmpty) ...[
          const SizedBox(height: 8),
          Text(s.goalEmpty, style: const TextStyle(fontSize: 14, height: 1.45, color: Palette.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final idea in s.goalIdeas)
              ActionChip(label: Text(idea), onPressed: () => showGoalEditor(context, name: idea)),
          ]),
        ] else
          for (final g in goals) _GoalRow(g, todayCycle),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow(this.goal, this.todayCycle);
  final Goal goal;
  final String todayCycle;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final p = goalProgress(app.store.state, goal, todayCycle);
    final ratio = goal.target == 0 ? 1.0 : (p.saved / goal.target).clamp(0.0, 1.0);
    final sub = p.done
        ? s.goalDone
        : goal.perCycle <= 0
            ? s.goalNoPlan
            : '${s.goalPerCycleLine(app.money.amount(goal.perCycle))} · ${s.goalEta(cycleLabel(p.etaCycle!, app.lang))}';
    return InkWell(
      onTap: () => showGoalEditor(context, goal: goal),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(goal.name, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)),
            Text('${app.money.amount(p.saved)} / ${app.money.amount(goal.target)}', style: mono(size: 13)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Container(color: Palette.line2),
                FractionallySizedBox(widthFactor: ratio, child: Container(color: Palette.accent)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(sub, style: TextStyle(fontSize: 12, color: p.done ? Palette.accent : Palette.muted)),
        ]),
      ),
    );
  }
}

/// Creates or edits a goal. A new goal gets its own savings account unless an existing one is picked;
/// a per-cycle amount sets up the automatic transfer on payday.
Future<void> showGoalEditor(BuildContext context, {Goal? goal, String name = ''}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(child: _GoalForm(goal: goal, name: name)),
      ),
    );

class _GoalForm extends StatefulWidget {
  const _GoalForm({this.goal, this.name = ''});
  final Goal? goal;
  final String name;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final _name = TextEditingController(text: widget.goal?.name ?? widget.name);
  late final _target = TextEditingController();
  late final _per = TextEditingController();
  final _have = TextEditingController();
  String? _account, _error;
  bool _init = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _per.dispose();
    _have.dispose();
    super.dispose();
  }

  void _save() {
    final app = AppScope.of(context, listen: false);
    final s = app.s;
    final name = _name.text.trim();
    final target = parseAmount(_target.text);
    final per = _per.text.trim().isEmpty ? 0 : parseAmount(_per.text);
    final have = _have.text.trim().isEmpty ? 0 : parseAmount(_have.text);
    if (name.isEmpty) return setState(() => _error = s.goalNameRequired);
    if (target == null || target <= 0) return setState(() => _error = s.goalTargetRequired);
    if (per == null || have == null) return setState(() => _error = s.enterAmount);
    app.store.saveGoal(
        id: widget.goal?.id,
        name: name,
        target: target,
        perCycle: per,
        account: widget.goal?.account ?? _account,
        alreadySaved: have,
        today: app.today);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final app = AppScope.of(context, listen: false);
    final s = app.s;
    if (!await confirm(context, s.deleteGoalQ, s.delete)) return;
    app.store.removeGoal(widget.goal!.id, today: app.today);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final editing = widget.goal != null;
    if (!_init) {
      _init = true;
      if (editing) {
        _target.text = app.money.amount(widget.goal!.target);
        if (widget.goal!.perCycle > 0) _per.text = app.money.amount(widget.goal!.perCycle);
      }
    }
    final savings = app.store.state.accounts.where((a) => a.isSavings).toList();
    InputDecoration deco(String label, {bool money = true}) => InputDecoration(
        labelText: label, suffixText: money ? app.money.symbol : null, border: const OutlineInputBorder());
    const gap = SizedBox(height: 12);

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(editing ? widget.goal!.name : s.newGoal, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: deco(s.goalName, money: false)),
      gap,
      TextField(
        controller: _target,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [MoneyInputFormatter()],
        decoration: deco(s.goalTarget),
      ),
      gap,
      TextField(
        controller: _per,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [MoneyInputFormatter()],
        decoration: deco(s.goalPerCycle),
      ),
      const SizedBox(height: 6),
      Text(s.goalPerCycleHint, style: const TextStyle(fontSize: 12, height: 1.4, color: Palette.muted)),
      if (!editing) ...[
        gap,
        if (savings.isNotEmpty)
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _account,
            decoration: deco(s.goalAccount, money: false),
            dropdownColor: Palette.surface2,
            items: [
              DropdownMenuItem(value: null, child: Text(s.goalNewAccount)),
              for (final a in savings) DropdownMenuItem(value: a.id, child: Text(s.accountName(a))),
            ],
            onChanged: (v) => setState(() => _account = v),
          ),
        if (_account == null) ...[
          if (savings.isNotEmpty) gap,
          TextField(
            controller: _have,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [MoneyInputFormatter()],
            decoration: deco(s.goalHave),
          ),
        ],
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: Palette.neg, fontSize: 13)),
        ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        if (editing)
          TextButton(onPressed: _delete, style: TextButton.styleFrom(foregroundColor: Palette.neg), child: Text(s.delete)),
        TextButton(onPressed: _save, child: Text(s.save)),
      ]),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.current);
  final List<int> values;
  final int? current;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = math.max(1, hi - lo);
    const pad = 8.0;
    Offset at(int i) => Offset(
        pad + i * (size.width - 2 * pad) / (values.length - 1), size.height - pad - (values[i] - lo) / span * (size.height - 2 * pad));
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = Palette.accent.withValues(alpha: 0.12));
    canvas.drawPath(
        line,
        Paint()
          ..color = Palette.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    if (current != null && current! >= 0 && current! < values.length) {
      canvas.drawCircle(at(current!), 5, Paint()..color = Palette.accent);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values.toString() != values.toString() || old.current != current;
}
