// First login of a new account: language, currency, when the month starts,
// and the fixed bills. Everything here can be changed later in Ajustes / Fixas.

import 'package:flutter/material.dart';

import '../account.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'auth.dart';
import 'bills.dart';
import 'preferences.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final account = AccountScope.of(context, listen: false);
    final bills = [...app.store.state.recurring]..sort((a, b) => a.day.compareTo(b.day));
    final income = bills.where((r) => app.model.isIncome(r.category)).fold(0, (a, r) => a + r.cents);
    final out = bills
        .where((r) => !app.model.isIncome(r.category) && !app.model.isTransferCategory(r.category))
        .fold(0, (a, r) => a + r.cents);

    return AuthFrame(maxWidth: 560, children: [
      Lbl(s.welcome),
      const SizedBox(height: 12),
      H1(s.onboardingTitle, size: 26),
      const SizedBox(height: 10),
      Text(s.onboardingIntro, style: const TextStyle(fontSize: 14, height: 1.45, color: Palette.muted)),
      const SizedBox(height: 16),
      PrefRow(label: s.language, child: const LanguagePicker()),
      PrefRow(label: s.currency, child: const CurrencyPicker()),
      PrefRow(label: s.monthStartsOn, hint: s.startDayHint, child: const StartDayPicker()),
      const SizedBox(height: 20),
      Lbl(s.accounts),
      const SizedBox(height: 4),
      Text(s.balanceHint, style: const TextStyle(fontSize: 12, height: 1.4, color: Palette.muted)),
      const AccountsList(),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Lbl(s.billsTitle),
        if (bills.isNotEmpty)
          Text('+${app.money.amount(income)}  −${app.money.amount(out)}', style: mono(size: 12, color: Palette.muted)),
      ]),
      const SizedBox(height: 4),
      for (final r in bills) BillRow(r),
      const SizedBox(height: 14),
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
          child: Text(bills.isEmpty ? s.skipForNow : s.done),
        ),
      ),
    ]);
  }
}
