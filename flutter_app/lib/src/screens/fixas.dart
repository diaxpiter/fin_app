import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';
import '../layout.dart';

class FixasScreen extends StatelessWidget {
  const FixasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context).model;
    final rec = [...m.state.recurring]..sort((a, b) => a.day.compareTo(b.day));
    final now = cycleIdOf(m.today, m.state.config.cycleStartDay);
    final active = rec.where((r) => r.to == null || r.to!.compareTo(now) >= 0);
    final out = active.where((r) => !m.isIncome(r.category)).fold(0, (a, r) => a + r.cents);
    final inn = active.where((r) => m.isIncome(r.category)).fold(0, (a, r) => a + r.cents);

    Widget stat(String label, int cents, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Lbl(label),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(fmtCents(cents), style: mono(size: 22, weight: FontWeight.w500, color: color)),
            ),
          ]),
        );

    Widget pill(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: Palette.line2), borderRadius: BorderRadius.circular(6)),
          child: Text(text.toUpperCase(),
              style: mono(size: 10, weight: FontWeight.w500, color: Palette.muted).copyWith(letterSpacing: 0.4)),
        );

    return ScreenList(
      maxWidth: 760,
      bottom: 32,
      children: [
        const TopRow(children: [H1('Contas fixas')]),
        const SizedBox(height: 24),
        Container(
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.line), bottom: BorderSide(color: Palette.line))),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: stat('Sai por mês', out, Palette.text)),
              const VerticalDivider(width: 1, thickness: 1, color: Palette.line),
              const SizedBox(width: 16),
              Expanded(child: stat('Entra por mês', inn, Palette.accent)),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        const Lbl('Por dia do mês'),
        const SizedBox(height: 6),
        for (final r in rec)
          Opacity(
            opacity: r.to != null && r.to!.compareTo(now) < 0 ? 0.45 : 1,
            child: InfoRow(
              leading: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    border: Border.all(color: Palette.surface2), borderRadius: BorderRadius.circular(8)),
                child: Text('${r.day}', style: mono(size: 13, color: Palette.soft)),
              ),
              title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(r.description, style: const TextStyle(fontSize: 15)),
                if (r.variable) pill('Variável'),
                if (r.to != null) pill('até ${cycleLabel(r.to!).substring(0, 3).toLowerCase()}'),
              ]),
              trailing: [
                Text('${m.isIncome(r.category) ? '+' : ''}${fmtCents(r.cents)}',
                    style: mono(color: m.isIncome(r.category) ? Palette.accent : Palette.text)),
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Text('Por agora as contas fixas só se consultam. Editá-las vem na próxima versão.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted)),
      ],
    );
  }
}
