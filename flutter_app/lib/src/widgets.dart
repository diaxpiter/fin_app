// Shared pieces used by several screens.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'layout.dart';
import 'logic.dart';
import 'models.dart';
import 'screens/nova.dart';
import 'theme.dart';

/// Money fields accept only digits and the separators "." and ","; [signed] also
/// allows a leading minus. Anything else typed or pasted is ignored.
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter({this.signed = false});
  final bool signed;

  static final _unsigned = RegExp(r'^[0-9.,]{0,15}$');
  static final _signed = RegExp(r'^[-−]?[0-9.,]{0,15}$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      (signed ? _signed : _unsigned).hasMatch(newValue.text) ? newValue : oldValue;
}

/// A form field that opens a calendar. Shows [text]; [onClear] adds a clear button.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.text, required this.onTap, this.onClear});
  final String label, text;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Palette.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            suffixIcon: onClear == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                    onPressed: onClear,
                  ),
          ),
          child: Text(text, overflow: TextOverflow.ellipsis),
        ),
      );
}

/// Opens the calendar on [initial] (YYYY-MM-DD) and returns the picked date as YYYY-MM-DD.
Future<String?> pickDate(BuildContext context, String initial) async {
  final d = DateTime.parse(initial);
  final picked = await showDatePicker(
    context: context,
    initialDate: d,
    firstDate: DateTime(d.year - 5),
    lastDate: DateTime(d.year + 10),
    builder: (context, child) => _FittedDatePicker(child: child!),
  );
  return picked == null ? null : todayISO(picked);
}

/// The calendar's header ("segunda, 19/10") is a fixed 32px headline. In landscape
/// windows (desktop browsers, phones on their side) it sits in a 152px column, where
/// long weekdays broke mid-word; on narrow phones in portrait it was cut with "…".
/// This shrinks the headline just enough: in portrait the whole date fits on one line,
/// in landscape each word does (weekday on one line, day/month on the next).
class _FittedDatePicker extends StatelessWidget {
  const _FittedDatePicker({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    // text width Material leaves for the headline (see date_picker.dart):
    // portrait dialog ≤ 360 wide with 16px screen margins, minus paddings and the edit button;
    // landscape header column 152 minus 16px each side
    final room = portrait ? math.min(MediaQuery.sizeOf(context).width - 32, 360.0) - 24 - 12 - 48 - 4 : 152.0 - 32 - 4;
    final base = theme.textTheme.headlineLarge ?? const TextStyle(fontSize: 32);
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
    var widest = 0.0;
    for (var i = 0; i < 7; i++) {
      // a week of two-digit days covers every weekday name
      final text = loc.formatMediumDate(DateTime(2026, 10, 19 + i));
      for (final part in portrait ? [text] : text.split(' ')) {
        final painter = TextPainter(text: TextSpan(text: part, style: base), textDirection: TextDirection.ltr, textScaler: scaler)
          ..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
    }
    final size = (base.fontSize ?? 32) * math.min(1.0, room / widest);
    return Theme(
      data: theme.copyWith(
        datePickerTheme: theme.datePickerTheme.copyWith(
          headerForegroundColor: Palette.text,
          headerHeadlineStyle: base.copyWith(fontSize: size.floorToDouble()),
        ),
      ),
      child: child,
    );
  }
}

class Lbl extends StatelessWidget {
  const Lbl(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: mono(size: 11, weight: FontWeight.w500, color: Palette.muted).copyWith(letterSpacing: 0.9, height: 1),
      );
}

class H1 extends StatelessWidget {
  const H1(this.text, {super.key, this.size = 30});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, letterSpacing: -0.9));
}

/// Title on the left, actions on the right; wraps onto two lines on very narrow screens.
class TopRow extends StatelessWidget {
  const TopRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 12,
          children: children,
        ),
      );
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Big amount + "€", shrinks to fit narrow screens instead of overflowing.
class BigAmount extends StatelessWidget {
  const BigAmount(this.cents, {super.key, this.size = 68, this.color = Palette.text, this.alignment = Alignment.centerLeft});
  final int cents;
  final double size;
  final Color color;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final money = AppScope.of(context).money;
    final symbol = Text(money.symbol,
        style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w500, color: Palette.muted));
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (money.symbolFirst) ...[symbol, const SizedBox(width: 6)],
          Text(money.amount(cents),
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w600,
                letterSpacing: -size * 0.045,
                height: 1,
                color: color,
                fontFeatures: mono().fontFeatures,
              )),
          if (!money.symbolFirst) ...[const SizedBox(width: 6), symbol],
        ],
      ),
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Palette.text : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? Palette.text : Palette.line2)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          // Center(widthFactor: 1) hugs the label: an aligned Container would fill a whole Wrap row
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500, color: selected ? Palette.bg : Palette.soft)),
            ),
          ),
        ),
      );
}

class CyclePicker extends StatelessWidget {
  const CyclePicker(this.m, {super.key});
  final Model m;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lang = app.lang;
    return PopupMenuButton<String>(
      tooltip: app.s.chooseCycle,
      initialValue: m.cycle.id,
      onSelected: app.pickCycle,
      color: Palette.surface,
      constraints: const BoxConstraints(maxHeight: 420),
      itemBuilder: (_) => [
        for (final c in m.cycles)
          PopupMenuItem(
              value: c.id,
              child: Text('${cycleLabel(c.id, lang)} · ${formatDay(c.start, lang)} – ${formatDay(c.end, lang)}')),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Palette.surface,
          border: Border.all(color: Palette.line2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${formatDay(m.cycle.start, lang)} – ${formatDay(m.cycle.end, lang)}', style: mono(size: 13)),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more, size: 16, color: Palette.muted),
        ]),
      ),
    );
  }
}

const _rowBorder = BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line)));

class MovementRow extends StatelessWidget {
  const MovementRow(this.mv, this.m, {super.key});
  final Movement mv;
  final Model m;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final income = m.isIncome(mv.category);
    final transfer = mv.toAccount != null && m.isTransferCategory(mv.category);
    final paid = mv.estado == 'Pago';
    String acc(String? id) => app.s.accountName(m.state.accountById(id) ?? m.state.accounts.first);
    final sub = transfer
        ? app.s.transferLabel(acc(mv.account), acc(mv.toAccount))
        : '${app.s.category(mv.category)}${m.multiAccount ? ' · ${acc(mv.account)}' : ''}';
    return InkWell(
      onTap: () => showMovementActions(context, mv),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: _rowBorder,
        child: Row(children: [
          Dot(m.colorOf(mv.category)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mv.description, style: const TextStyle(fontSize: 15), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(sub, style: const TextStyle(fontSize: 12, color: Palette.muted), overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${transfer ? '⇄ ' : (income ? '+' : '−')}${app.money.amount(mv.cents)}',
                style: mono(color: income ? Palette.accent : (transfer ? Palette.muted : Palette.text))),
            const SizedBox(height: 3),
            Text(app.s.estado(mv.estado).toUpperCase(),
                style: mono(size: 11, weight: FontWeight.w500, color: paid ? Palette.muted : Palette.warn)
                    .copyWith(letterSpacing: 0.4)),
          ]),
        ]),
      ),
    );
  }
}

/// A static list row: leading widget, title, trailing widgets.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.leading, required this.title, this.trailing = const []});
  final Widget leading;
  final Widget title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: _rowBorder,
        child: Row(children: [leading, const SizedBox(width: 12), Expanded(child: title), ...trailing]),
      );
}

// ---------- movement actions: bottom sheet on phones, dialog elsewhere ----------

enum _Act { toggle, edit, delete }

Future<void> showMovementActions(BuildContext context, Movement mv) async {
  final app = AppScope.of(context, listen: false);
  final s = app.s;
  final income = app.model.isIncome(mv.category);
  final compact = sizeClassOf(context) == SizeClass.compact;

  Widget content(BuildContext ctx) {
    Widget btn(String label, VoidCallback onTap, {Color color = Palette.text, bool last = false}) => InkWell(
          onTap: onTap,
          child: Container(
            height: 52,
            alignment: Alignment.centerLeft,
            decoration: last ? null : _rowBorder,
            child: Text(label, style: TextStyle(fontSize: 16, color: color)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: _rowBorder,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mv.description, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 3),
            Text(
                '${s.category(mv.category)} · ${formatDay(mv.date, app.lang)} · '
                '${app.money.full(income ? mv.cents : -mv.cents, sign: true)}',
                style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        ),
        btn(
          mv.estado == 'Pago' ? s.markPlanned : (income ? s.markReceived : s.markPaid),
          () => Navigator.pop(ctx, _Act.toggle),
        ),
        btn(s.edit, () => Navigator.pop(ctx, _Act.edit)),
        btn(s.delete, () => Navigator.pop(ctx, _Act.delete), color: Palette.neg),
        btn(s.close, () => Navigator.pop(ctx), color: Palette.muted, last: true),
      ]),
    );
  }

  final act = compact
      ? await showModalBottomSheet<_Act>(
          context: context,
          backgroundColor: Palette.surface,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => SafeArea(child: content(ctx)),
        )
      : await showDialog<_Act>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Palette.surface,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: content(ctx)),
          ),
        );

  if (!context.mounted) return;
  switch (act) {
    case _Act.toggle:
      app.store.setEstado(mv.id, mv.estado == 'Pago' ? 'Previsto' : 'Pago');
    case _Act.edit:
      await openNova(context, editing: mv);
    case _Act.delete:
      if (await confirm(context, s.deleteMovementQ, s.delete)) app.store.removeMovement(mv.id);
    case null:
      break;
  }
}

Future<bool> confirm(BuildContext context, String question, String action) async {
  final cancel = AppScope.of(context, listen: false).s.cancel;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.surface,
      content: Text(question),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancel)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Palette.neg),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1600)));
}
