import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bills.dart';

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

    return ScreenList(
      maxWidth: 760,
      bottom: 32,
      children: [
        TopRow(children: [
          const H1('Contas fixas'),
          FilledButton.icon(
            onPressed: () => showBillEditor(context),
            style: FilledButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Palette.bg),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nova'),
          ),
        ]),
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
        if (rec.isEmpty) ...[
          const Text('Ainda não tens contas fixas. Começa pelo salário e pelas contas da casa:',
              style: TextStyle(fontSize: 14, height: 1.45, color: Palette.muted)),
          const SizedBox(height: 14),
          const BillSuggestions(),
        ] else ...[
          const Lbl('Por dia do mês'),
          const SizedBox(height: 6),
          for (final r in rec) BillRow(r),
        ],
        const SizedBox(height: 24),
        const Text(
            'As contas fixas aparecem como previstas nos próximos $recurringHorizon ciclos. '
            'Alterar uma conta muda só os movimentos que ainda estão previstos; os já pagos ficam como estão.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted)),
      ],
    );
  }
}
