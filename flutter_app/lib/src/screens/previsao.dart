import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';

class PrevisaoScreen extends StatelessWidget {
  const PrevisaoScreen({super.key, this.header});

  /// Shown above the title (the Plano tab's switcher).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final lang = app.lang;
    final money = app.money;
    final m = app.model;
    final plan = m.cycles.where((c) => c.items.isNotEmpty).toList();
    final last = plan.isNotEmpty ? plan.last : m.cycle;
    final showSaldo = sizeClassOf(context) != SizeClass.compact;

    Widget cell(String text, {Color color = Palette.text, int flex = 10, bool first = false, TextStyle? style}) => Expanded(
          flex: flex,
          child: first
              ? Text(text, style: style ?? const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(text, style: style ?? mono(size: 13, color: color)),
                ),
        );

    return ScreenList(
      maxWidth: 900,
      bottom: 32,
      children: [
        if (header != null) header!,
        TopRow(children: [H1(s.navForecast)]),
        const SizedBox(height: 6),
        Text(
            '${s.cycleCount(plan.length)}'
            '${plan.isNotEmpty ? ' · ${cycleLabel(plan.first.id, lang)} – ${cycleLabel(last.id, lang)}' : ''}',
            style: mono(size: 12, color: Palette.muted)),
        TwoPane(
          leftFlex: 2,
          rightFlex: 3,
          left: [
        const SizedBox(height: 26),
        Lbl(s.balanceBy(cycleLabel(last.id, lang))),
        const SizedBox(height: 14),
        BigAmount(last.endBalance, size: 52),
        const SizedBox(height: 26),
        Lbl(s.leftPerCycle),
        const SizedBox(height: 14),
        // as many bars as fit: 7 on a phone, the whole plan on a wide screen
        LayoutBuilder(builder: (context, c) {
          final fit = math.max(1, (c.maxWidth / 40).floor());
          final bars = plan.take(fit).toList();
          final max = math.max(1, bars.fold(0, (a, x) => math.max(a, x.sobra.abs())));
          return Container(
            height: 150,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.surface2))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < bars.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => app.pickCycle(bars[i].id),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(
                        height: math.max(4, (bars[i].sobra.abs() / max * 112).round()).toDouble(),
                        decoration: BoxDecoration(
                          color: bars[i].id == m.cycle.id
                              ? Palette.accent
                              : (bars[i].sobra < 0 ? const Color(0x80FF7A64) : Palette.line2),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(cycleLabel(bars[i].id, lang).substring(0, 3),
                            maxLines: 1,
                            style: mono(
                                size: 11,
                                weight: FontWeight.w500,
                                color: bars[i].id == m.cycle.id ? Palette.text : Palette.muted)),
                      ),
                      const SizedBox(height: 4),
                    ]),
                  ),
                ),
              ],
            ]),
          );
        }),
          ],
          right: [
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(flex: 12, child: Lbl(s.colCycle)),
            for (final h in [s.colIn, s.colOut, s.colLeft, if (showSaldo) s.colBalance])
              Expanded(flex: 10, child: Align(alignment: Alignment.centerRight, child: Lbl(h))),
          ]),
        ),
        for (final c in plan)
          InkWell(
            onTap: () => app.pickCycle(c.id),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
              child: Row(children: [
                cell(cycleLabel(c.id, lang),
                    flex: 12,
                    first: true,
                    style: TextStyle(fontSize: 15, color: c.id == m.cycle.id ? Palette.accent : Palette.text)),
                cell(money.amount(c.receitas)),
                cell(money.amount(c.despesas), color: Palette.neg),
                cell(money.amount(c.sobra), color: c.sobra < 0 ? Palette.neg : Palette.text),
                if (showSaldo) cell(money.amount(c.endBalance), color: Palette.muted),
              ]),
            ),
          ),
          ],
        ),
      ],
    );
  }
}
