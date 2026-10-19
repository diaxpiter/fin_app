// Language, currency and cycle start day pickers, shared by Ajustes and the
// first-login step. Changes save to the user's data (and sync with an account).

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../holidays.dart';
import '../i18n.dart';
import '../logic.dart';
import '../widgets.dart';
import '../theme.dart';

class _Box<T> extends StatelessWidget {
  const _Box({required this.value, required this.items, required this.onChanged});
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: Palette.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Palette.line2)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: Palette.surface,
            menuMaxHeight: 360,
            items: items,
            onChanged: onChanged,
          ),
        ),
      );
}

/// A labelled setting: label on the left, picker on the right (stacked on narrow screens).
class PrefRow extends StatelessWidget {
  const PrefRow({super.key, required this.label, required this.child, this.hint});
  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LayoutBuilder(builder: (context, c) {
          final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 15)),
            if (hint != null) ...[
              const SizedBox(height: 3),
              Text(hint!, style: const TextStyle(fontSize: 12, height: 1.35, color: Palette.muted)),
            ],
          ]);
          if (c.maxWidth < 420) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const SizedBox(height: 8), child]);
          }
          return Row(children: [Expanded(child: text), const SizedBox(width: 16), SizedBox(width: 220, child: child)]);
        }),
      );
}

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Box<String>(
      value: app.store.state.config.language ?? 'auto',
      items: [
        DropdownMenuItem(
            value: 'auto', child: Text('${app.s.automatic} (${languages[resolveLanguage(null, app.deviceLanguage)]})')),
        for (final e in languages.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) => app.store.setLanguage(v == null || v == 'auto' ? null : v),
    );
  }
}

class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Box<String>(
      value: app.store.state.config.currency,
      items: [
        for (final code in currencies.keys)
          DropdownMenuItem(
            value: code,
            child: Text('${Money(app.lang, code).symbol}  ${app.s.currencyName(code)}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) app.store.setCurrency(v);
      },
    );
  }
}

class HolidaysPicker extends StatelessWidget {
  const HolidaysPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Box<String>(
      value: app.store.state.config.holidays,
      items: [for (final c in holidayCountries) DropdownMenuItem(value: c, child: Text(app.s.holidayName(c)))],
      onChanged: (v) {
        if (v != null) app.store.setHolidays(v);
      },
    );
  }
}

class StartDayPicker extends StatelessWidget {
  const StartDayPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final current = app.store.state.config.cycleStartDay;
    return _Box<int>(
      value: current,
      items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d', style: mono(size: 15)))],
      onChanged: (d) {
        if (d != null && d != current) {
          app.store.setStartDay(d);
          app.resetCycle();
        }
      },
    );
  }
}

/// Asks "how much is in your account today?" and derives the opening balance from it.
Future<void> editBalance(BuildContext context) async {
  final app = AppScope.of(context, listen: false);
  final s = app.s;
  final ctrl = TextEditingController(text: app.money.amount(cashNow(app.store.state)).replaceFirst('−', '-'));
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.surface,
      title: Text(s.balanceQ),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: const [MoneyInputFormatter(signed: true)],
            style: mono(size: 18),
            decoration: InputDecoration(suffixText: app.money.symbol, border: const OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 10),
          Text(s.balanceHint, style: const TextStyle(fontSize: 12, height: 1.4, color: Palette.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
        TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(s.save)),
      ],
    ),
  );
  if (text == null) return;
  final negative = RegExp(r'^\s*[-−]').hasMatch(text);
  final cents = parseAmount(text);
  if (cents == null) return;
  app.store.setBalanceToday(negative ? -cents : cents);
  if (context.mounted) toast(context, s.balanceSet);
}

/// Shows the current balance; tapping it asks for today's balance.
class BalanceButton extends StatelessWidget {
  const BalanceButton({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return OutlinedButton(
      onPressed: () => editBalance(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: const BorderSide(color: Palette.line2),
        backgroundColor: Palette.surface,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerLeft,
      ),
      child: Text(app.money.full(cashNow(app.store.state)), style: mono(size: 15)),
    );
  }
}

/// Compact PT | EN switch for the sign-in screen.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final code in languages.keys)
        TextButton(
          onPressed: () => app.store.setLanguage(code),
          style: TextButton.styleFrom(
            foregroundColor: app.lang == code ? Palette.text : Palette.muted,
            minimumSize: const Size(44, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Text(code.toUpperCase(),
              style: TextStyle(fontWeight: app.lang == code ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
        ),
    ]);
  }
}
