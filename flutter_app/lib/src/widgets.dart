// Shared pieces used by several screens.

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'layout.dart';
import 'logic.dart';
import 'models.dart';
import 'theme.dart';

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
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500, color: selected ? Palette.bg : Palette.soft)),
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
    final paid = mv.estado == 'Pago';
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
              Text(app.s.category(mv.category), style: const TextStyle(fontSize: 12, color: Palette.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${income ? '+' : '−'}${app.money.amount(mv.cents)}',
                style: mono(color: income ? Palette.accent : Palette.text)),
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

enum _Act { toggle, delete }

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
