// Language, currency and cycle start day pickers, shared by Ajustes and the
// first-login step. Changes save to the user's data (and sync with an account).

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../holidays.dart';
import '../i18n.dart';
import '../logic.dart';
import '../models.dart';
import '../store.dart';
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

/// Moves the cycle start off weekends/holidays, like the salary bill does.
class CycleShiftPicker extends StatelessWidget {
  const CycleShiftPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return _Box<DayShift>(
      value: app.store.state.config.cycleShift,
      items: [for (final d in DayShift.values) DropdownMenuItem(value: d, child: Text(app.s.shift(d)))],
      onChanged: (d) {
        if (d != null && d != app.store.state.config.cycleShift) {
          app.store.setCycleShift(d);
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

/// Pill chips to pick one of the accounts.
class AccountChips extends StatelessWidget {
  const AccountChips({super.key, required this.value, required this.onChanged, this.exclude});
  final String value;
  final ValueChanged<String> onChanged;
  final String? exclude;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final a in app.store.state.accounts.where((a) => a.id != exclude))
        PillChip(label: app.s.accountName(a), selected: a.id == value, onTap: () => onChanged(a.id)),
    ]);
  }
}

/// The user's accounts with today's balance and this cycle's low point; tap one to edit it.
class AccountsList extends StatelessWidget {
  const AccountsList({super.key, this.showAdd = true});
  final bool showAdd;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final m = app.model;
    final state = m.state;
    final total = state.accounts.fold(0, (a, x) => a + accountCash(state, x.id));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final a in state.accounts)
        InkWell(
          onTap: () => editAccount(context, account: a),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
            child: Row(children: [
              Icon(_kindIcon(a.kind), size: 18, color: Palette.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.accountName(a), style: const TextStyle(fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(s.accountKind(a.kind), style: const TextStyle(fontSize: 12, color: Palette.muted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(app.money.amount(accountCash(state, a.id)), style: mono()),
                if (m.cycle.accountLowestDate[a.id] != null && !a.isSavings) ...[
                  const SizedBox(height: 3),
                  Text(
                    s.lowestOn(app.money.amount(m.cycle.accountLowest[a.id]!),
                        formatDay(m.cycle.accountLowestDate[a.id]!, app.lang)),
                    style: mono(
                        size: 11, color: m.cycle.accountLowest[a.id]! < 0 ? Palette.neg : Palette.muted),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      if (state.accounts.length > 1)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Expanded(child: Text(s.total, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            Text(app.money.amount(total), style: mono(weight: FontWeight.w600)),
          ]),
        ),
      if (showAdd)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => editAccount(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(s.newAccount),
          ),
        ),
    ]);
  }
}

IconData _kindIcon(AccountKind k) => switch (k) {
      AccountKind.current => Icons.account_balance_outlined,
      AccountKind.spending => Icons.credit_card_outlined,
      AccountKind.savings => Icons.savings_outlined,
      AccountKind.investment => Icons.show_chart,
    };

/// Add or edit an account: name, type and today's balance (or current value, for investments).
Future<void> editAccount(BuildContext context, {Account? account}) {
  final app = AppScope.of(context, listen: false);
  final isNew = account == null;
  final s = app.s;
  final name = TextEditingController(text: isNew ? '' : s.accountName(account));
  final balance = TextEditingController(
      text: isNew ? '' : app.money.amount(accountCash(app.store.state, account.id)).replaceFirst('−', '-'));
  var kind = account?.kind ?? AccountKind.spending;
  String? error;
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text(isNew ? s.newAccount : s.editAccount),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: s.account, hintText: s.accountHint, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              Lbl(s.accountType),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in AccountKind.values)
                  PillChip(label: s.accountKind(k), selected: kind == k, onTap: () => setState(() => kind = k)),
              ]),
              const SizedBox(height: 6),
              Text(s.accountKindHint(kind), style: const TextStyle(fontSize: 12, color: Palette.muted)),
              const SizedBox(height: 14),
              TextField(
                controller: balance,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: const [MoneyInputFormatter(signed: true)],
                style: mono(size: 16),
                decoration: InputDecoration(
                    labelText: s.valueToday, suffixText: app.money.symbol, border: const OutlineInputBorder()),
              ),
              if (kind == AccountKind.investment)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.investmentHint, style: const TextStyle(fontSize: 12, color: Palette.muted)),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: const TextStyle(color: Palette.neg, fontSize: 13)),
                ),
            ]),
          ),
        ),
        actions: [
          if (!isNew)
            TextButton(
              onPressed: () async {
                if (app.store.accountInUse(account.id) || app.store.state.accounts.length <= 1) {
                  setState(() => error = s.accountInUse);
                  return;
                }
                if (!await confirm(ctx, s.deleteAccountQ2(s.accountName(account)), s.delete)) return;
                app.store.removeAccount(account.id);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) toast(context, s.accountDeleted);
              },
              style: TextButton.styleFrom(foregroundColor: Palette.neg),
              child: Text(s.delete),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isEmpty) return setState(() => error = s.enterName);
              final cents = parseAmount(balance.text);
              final negative = RegExp(r'^\s*[-−]').hasMatch(balance.text);
              // keep the stored name of the default account unless it was really renamed
              final stored = !isNew && n == s.accountName(account) ? account.name : n;
              app.store.saveAccount(
                (account ?? Account(id: Store.newAccountId(), name: n)).copyWith(name: stored, kind: kind),
                balanceToday: cents == null ? (isNew ? 0 : null) : (negative ? -cents : cents),
              );
              Navigator.pop(ctx);
              toast(context, s.accountSaved);
            },
            child: Text(s.save),
          ),
        ],
      ),
    ),
  );
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
