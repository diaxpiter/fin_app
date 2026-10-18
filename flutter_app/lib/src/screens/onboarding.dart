// First login of a new account: when the month starts and the fixed bills.
// Everything here can be changed later in Fixas and Ajustes.

import 'package:flutter/material.dart';

import '../account.dart';
import '../app_controller.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth.dart';
import 'bills.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final account = AccountScope.of(context, listen: false);
    final state = app.store.state;
    final bills = [...state.recurring]..sort((a, b) => a.day.compareTo(b.day));
    final startDay = state.config.cycleStartDay;
    final income = bills.where((r) => app.model.isIncome(r.category)).fold(0, (a, r) => a + r.cents);
    final out = bills.where((r) => !app.model.isIncome(r.category)).fold(0, (a, r) => a + r.cents);

    return AuthFrame(maxWidth: 560, children: [
      const Lbl('Bem-vindo'),
      const SizedBox(height: 12),
      const H1('As tuas contas fixas', size: 26),
      const SizedBox(height: 10),
      const Text(
        'Diz-nos o que entra e sai todos os meses. Com isto a previsão fica pronta. '
        'Podes mudar tudo mais tarde em Fixas.',
        style: TextStyle(fontSize: 14, height: 1.45, color: Palette.muted),
      ),
      const SizedBox(height: 24),
      const Lbl('O teu mês começa no dia'),
      const SizedBox(height: 8),
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: Palette.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Palette.line2)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: startDay,
              dropdownColor: Palette.surface,
              menuMaxHeight: 320,
              style: mono(size: 16),
              items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (d) {
                if (d != null && d != startDay) {
                  app.store.setStartDay(d);
                  app.resetCycle();
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Normalmente o dia em que recebes o salário. Usa 1 para meses de calendário.',
              style: TextStyle(fontSize: 12, height: 1.4, color: Palette.muted)),
        ),
      ]),
      const SizedBox(height: 28),
      if (bills.isNotEmpty) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Lbl('Contas fixas'),
          Text('+${fmtCents(income)}  −${fmtCents(out)}', style: mono(size: 12, color: Palette.muted)),
        ]),
        const SizedBox(height: 4),
        for (final r in bills) BillRow(r),
        const SizedBox(height: 16),
        const Lbl('Adicionar'),
        const SizedBox(height: 10),
      ],
      const BillSuggestions(),
      const SizedBox(height: 28),
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: account.finishOnboarding,
          style: FilledButton.styleFrom(
            backgroundColor: Palette.accent,
            foregroundColor: Palette.bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          child: Text(bills.isEmpty ? 'Saltar por agora' : 'Concluir'),
        ),
      ),
    ]);
  }
}
