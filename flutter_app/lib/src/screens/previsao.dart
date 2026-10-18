import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';

class PrevisaoScreen extends StatelessWidget {
  const PrevisaoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
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
        const TopRow(children: [H1('Previsão')]),
        const SizedBox(height: 6),
        Text('${plan.length} ciclos${plan.isNotEmpty ? ' · ${plan.first.label} – ${last.label}' : ''}',
            style: mono(size: 12, color: Palette.muted)),
        const SizedBox(height: 26),
        Lbl('Saldo acumulado em ${cycleLabel(last.id).toLowerCase()}'),
        const SizedBox(height: 14),
        BigAmount(last.endBalance, size: 52),
        const SizedBox(height: 26),
        const Lbl('Sobra por ciclo'),
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
                        child: Text(cycleLabel(bars[i].id).substring(0, 3),
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
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            const Expanded(flex: 12, child: Lbl('Ciclo')),
            for (final h in ['Entra', 'Sai', 'Sobra', if (showSaldo) 'Saldo'])
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
                cell(c.label,
                    flex: 12,
                    first: true,
                    style: TextStyle(fontSize: 15, color: c.id == m.cycle.id ? Palette.accent : Palette.text)),
                cell(fmtCents(c.receitas)),
                cell(fmtCents(c.despesas), color: Palette.neg),
                cell(fmtCents(c.sobra), color: c.sobra < 0 ? Palette.neg : Palette.text),
                if (showSaldo) cell(fmtCents(c.endBalance), color: Palette.muted),
              ]),
            ),
          ),
      ],
    );
  }
}
