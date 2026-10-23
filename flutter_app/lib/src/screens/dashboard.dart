import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';
import 'goals.dart';

/// One colour per account line; wraps around after six.
const _accountColors = [
  Palette.accent,
  Color(0xFF7AA2F7),
  Palette.warn,
  Color(0xFFB58CF5),
  Color(0xFF5FD0A5),
  Palette.neg,
];

/// What is yours, at a glance: net worth, each account over time, income vs spending,
/// where this cycle's money went, and the goals being saved for.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
    final current = i < 0 ? null : i - from;
    final stats = dashStats(m.state, m.cycles, todayCycle);
    final spend = spendByCategory(m.state, m.cycle).take(6).toList();
    final spendMax = spend.isEmpty ? 1 : spend.first.value;
    final accounts = m.state.accounts;

    String label(String id) => cycleLabel(id, app.lang);
    String describe(String name, List<int> v) =>
        '$name: ${[for (var k = 0; k < window.length; k++) '${label(window[k].id)} ${app.money.amount(v[k])}'].join(', ')}';
    Widget axis() => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label(window.first.id), style: mono(size: 11, color: Palette.muted)),
          Text(label(window.last.id), style: mono(size: 11, color: Palette.muted)),
        ]);
    Widget section(String title, List<Widget> body) => Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [Lbl(title), const SizedBox(height: 14), ...body]),
        );

    final netSeries = [for (final c in window) c.endBalance];

    return ScreenList(
      maxWidth: 720,
      children: [
        TopRow(children: [
          H1(s.navDashboard),
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
            label: describe(s.netWorth, netSeries),
            child: SizedBox(
              height: 110,
              child: CustomPaint(
                size: Size.infinite,
                painter: _LinePainter([(Palette.accent, netSeries)], current, fill: true),
              ),
            ),
          ),
          const SizedBox(height: 6),
          axis(),
          const SizedBox(height: 4),
          Text(s.netWorthEnd(app.money.amount(window.last.endBalance)),
              style: const TextStyle(fontSize: 13, color: Palette.muted)),
        ],
        const SizedBox(height: 24),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: _Kpi(s.dashSavingsRate, stats.savingsRate == null ? '—' : '${stats.savingsRate}%',
                  stats.savingsRate == null ? null : s.savedRate(stats.savingsRate!))),
          const SizedBox(width: 12),
          Expanded(child: _Kpi(s.dashAvgSpend, stats.avgSpend == 0 ? '—' : app.money.amount(stats.avgSpend), null)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: _Kpi(
                  s.dashRunway, stats.runwayMonths == null ? '—' : s.dashMonths(stats.runwayMonths!), s.dashRunwayHint)),
          const SizedBox(width: 12),
          Expanded(
              child: _Kpi(s.dashFixedShare, stats.fixedShare == null ? '—' : '${stats.fixedShare}%', s.dashFixedHint)),
        ]),
        if (window.length >= 2)
          section(s.accounts, [
            Semantics(
              label: [
                for (final a in accounts) describe(s.accountName(a), [for (final c in window) c.accountEnd[a.id] ?? 0])
              ].join('. '),
              child: SizedBox(
                height: 150,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _LinePainter([
                    for (var k = 0; k < accounts.length; k++)
                      (
                        _accountColors[k % _accountColors.length],
                        [for (final c in window) c.accountEnd[accounts[k].id] ?? 0]
                      ),
                  ], current),
                ),
              ),
            ),
            const SizedBox(height: 6),
            axis(),
            const SizedBox(height: 12),
            for (var k = 0; k < accounts.length; k++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Dot(_accountColors[k % _accountColors.length]),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.accountName(accounts[k]), style: const TextStyle(fontSize: 14))),
                  Text(app.money.amount(accountCash(m.state, accounts[k].id)), style: mono(size: 14)),
                ]),
              ),
          ]),
        if (window.length >= 2)
          section(s.dashIncomeVsSpend, [
            Semantics(
              label: '${s.income}: ${window.map((c) => app.money.amount(c.receitas)).join(', ')}. '
                  '${s.expenses}: ${window.map((c) => app.money.amount(c.despesas)).join(', ')}',
              child: SizedBox(
                height: 110,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _BarsPainter([for (final c in window) (c.receitas, c.despesas)], current),
                ),
              ),
            ),
            const SizedBox(height: 6),
            axis(),
            const SizedBox(height: 10),
            Row(children: [
              const Dot(Palette.accent),
              const SizedBox(width: 6),
              Text(s.income, style: const TextStyle(fontSize: 12, color: Palette.muted)),
              const SizedBox(width: 16),
              const Dot(Palette.neg),
              const SizedBox(width: 6),
              Text(s.expenses, style: const TextStyle(fontSize: 12, color: Palette.muted)),
            ]),
          ]),
        if (spend.isNotEmpty)
          section('${s.dashSpendNow} · ${label(m.cycle.id)}', [
            for (final e in spend)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Dot(m.colorOf(e.key)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(s.category(e.key), style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
                    Text(app.money.amount(e.value), style: mono(size: 13)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 5,
                      child: Stack(children: [
                        Container(color: Palette.line2),
                        FractionallySizedBox(widthFactor: e.value / spendMax, child: Container(color: m.colorOf(e.key))),
                      ]),
                    ),
                  ),
                ]),
              ),
          ]),
        const SizedBox(height: 32),
        GoalsList(todayCycle),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.hint);
  final String label, value;
  final String? hint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Lbl(label),
          const SizedBox(height: 10),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: mono(size: 20, weight: FontWeight.w500))),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, style: const TextStyle(fontSize: 11, height: 1.35, color: Palette.muted)),
          ],
        ]),
      );
}

/// One or more series on a shared scale; [current] marks today's cycle on each.
class _LinePainter extends CustomPainter {
  _LinePainter(this.series, this.current, {this.fill = false});
  final List<(Color, List<int>)> series;
  final int? current;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s.$2];
    if (all.isEmpty || series.first.$2.length < 2) return;
    final lo = all.reduce(math.min), hi = all.reduce(math.max);
    final span = math.max(1, hi - lo);
    const pad = 8.0;
    final n = series.first.$2.length;
    Offset at(List<int> v, int i) =>
        Offset(pad + i * (size.width - 2 * pad) / (n - 1), size.height - pad - (v[i] - lo) / span * (size.height - 2 * pad));
    if (lo < 0 && hi > 0) {
      final y = size.height - pad - (0 - lo) / span * (size.height - 2 * pad);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = Palette.line2);
    }
    for (final (color, v) in series) {
      final line = Path()..moveTo(at(v, 0).dx, at(v, 0).dy);
      for (var i = 1; i < n; i++) {
        line.lineTo(at(v, i).dx, at(v, i).dy);
      }
      if (fill) {
        final area = Path.from(line)
          ..lineTo(at(v, n - 1).dx, size.height)
          ..lineTo(at(v, 0).dx, size.height)
          ..close();
        canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
      }
      canvas.drawPath(
          line,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round);
      if (current != null && current! >= 0 && current! < n) canvas.drawCircle(at(v, current!), 4.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.series.toString() != series.toString() || old.current != current;
}

/// Income and spending side by side for each cycle; today's cycle is drawn brighter.
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.pairs, this.current);
  final List<(int, int)> pairs;
  final int? current;

  @override
  void paint(Canvas canvas, Size size) {
    final top = pairs.fold<int>(1, (a, p) => math.max(a, math.max(p.$1, p.$2)));
    final slot = size.width / pairs.length;
    final bar = math.min(14.0, slot * 0.32);
    for (var i = 0; i < pairs.length; i++) {
      final cx = slot * (i + 0.5);
      final alpha = current == null || i == current ? 1.0 : 0.55;
      void draw(int v, double dx, Color c) {
        final h = v / top * (size.height - 4);
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(cx + dx, size.height - h, bar, h), const Radius.circular(2)),
            Paint()..color = c.withValues(alpha: alpha));
      }

      draw(pairs[i].$1, -bar - 1, Palette.accent);
      draw(pairs[i].$2, 1, Palette.neg);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.pairs.toString() != pairs.toString() || old.current != current;
}
