import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../i18n.dart';
import '../layout.dart';
import '../logic.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// Full-screen page on phones (portrait or landscape), a centred dialog on tablets and desktop.
/// With [editing], the same form edits an existing movement.
Future<void> openNova(BuildContext context, {Movement? editing}) {
  if (sizeClassOf(context) == SizeClass.compact || isShort(context)) {
    return Navigator.of(context)
        .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => NovaScreen(editing: editing)));
  }
  final h = MediaQuery.sizeOf(context).height;
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Palette.bg,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Palette.line2)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 460, height: math.min(h - 48, 780), child: NovaScreen(editing: editing)),
    ),
  );
}

class NovaScreen extends StatefulWidget {
  const NovaScreen({super.key, this.editing});
  final Movement? editing;

  @override
  State<NovaScreen> createState() => _NovaScreenState();
}

class _NovaScreenState extends State<NovaScreen> {
  late int _cents = widget.editing?.cents ?? 0;
  late String _cat = widget.editing?.category ?? 'Alimentação';
  late String _estado = widget.editing?.estado ?? 'Pago';
  late String? _date = widget.editing?.date;
  String? _error;
  late final _desc = TextEditingController(text: widget.editing?.description ?? '');

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  void _key(String v) => setState(() {
        _error = null;
        if (v == 'back') {
          _cents ~/= 10;
        } else {
          _cents = math.min(_cents * (v == '00' ? 100 : 10) + (v == '00' ? 0 : int.parse(v)), 99999999);
        }
      });

  Future<void> _save() async {
    final app = AppScope.of(context, listen: false);
    final s = app.s;
    if (_cents <= 0) {
      setState(() => _error = s.enterAmount);
      return;
    }
    final typed = _desc.text.trim();
    final desc = typed.isEmpty ? _cat : typed;
    final messenger = ScaffoldMessenger.of(context);
    var message = s.expenseAdded;

    final old = widget.editing;
    if (old != null) {
      app.store.updateMovement(
          old.copyWith(date: _date, description: desc, category: _cat, cents: _cents, estado: _estado));
      app.pickCycle(cycleOfMovement(app.store.state.movements.firstWhere((m) => m.id == old.id),
          app.store.state.config.cycleStartDay));
      message = s.movementUpdated;
    } else {
      // a payment for a bill that's already planned settles it instead of adding a duplicate
      final matches = matchPlanned(app.store.state, date: _date!, description: typed, category: _cat);
      String? choice = '';
      if (matches.isNotEmpty) {
        choice = await _askMatch(matches.take(3).toList(), app);
        if (choice == null || !mounted) return; // dismissed: stay on the form
      }
      if (choice.isEmpty) {
        app.addMovement(date: _date!, description: desc, category: _cat, cents: _cents, estado: _estado);
      } else {
        app.store.payPlanned(choice, cents: _cents, date: _date!);
        app.pickCycle(cycleIdOf(_date!, app.store.state.config.cycleStartDay));
        app.setTab(0);
        message = s.markedPaid;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Returns the id of the planned movement to settle, '' for "a new expense", null if dismissed.
  Future<String?> _askMatch(List<Movement> matches, AppController app) {
    final s = app.s, lang = app.lang;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text(s.matchTitle),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.matchBody(app.money.full(_cents)), style: const TextStyle(fontSize: 14, height: 1.4, color: Palette.muted)),
            const SizedBox(height: 12),
            for (final m in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, m.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.text,
                    side: const BorderSide(color: Palette.line2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    alignment: Alignment.centerLeft,
                  ),
                  child: Row(children: [
                    Expanded(child: Text('${m.description} · ${formatDay(m.date, lang)}', overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text(app.money.full(m.cents), style: mono(size: 13, color: Palette.muted)),
                  ]),
                ),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(s.matchNo))],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, _date!);
    if (picked != null) setState(() => _date = picked);
  }

  // Physical keyboard (desktop, web, tablets with keyboards): digits, backspace, enter.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _key(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _key('back');
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final lang = app.lang;
    final m = app.model;
    _date ??= m.today;
    // a new entry is an expense; when editing, keep the movement's side (income / expense)
    final editingIncome = widget.editing != null && m.isIncome(widget.editing!.category);
    final cats = m.state.categories.where((c) => (c.type == 'Entrada') == editingIncome);

    final fields = <Widget>[
      const SizedBox(height: 14),
      BigAmount(_cents, size: 60, alignment: Alignment.center, color: _error != null ? Palette.neg : Palette.text),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Palette.neg, fontSize: 13)),
        ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.surface2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Lbl(s.description),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            decoration: InputDecoration.collapsed(
                hintText: s.expenseHint, hintStyle: const TextStyle(color: Color(0xFF55555B))),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in cats)
          PillChip(label: s.category(c.name), selected: _cat == c.name, onTap: () => setState(() => _cat = c.name)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: Material(
            color: Palette.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Palette.surface2)),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _pickDate,
              child: SizedBox(
                height: 44,
                child: Row(children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.calendar_today_outlined, size: 16, color: Palette.muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('${_date == m.today ? s.todayPrefix : ''}${formatDay(_date!, lang)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _Segmented(value: _estado, label: s.estado, onChanged: (v) => setState(() => _estado = v))),
      ]),
    ];

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Palette.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Column(children: [
              Row(children: [
                IconButton(
                  tooltip: s.close,
                  color: Palette.muted,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(widget.editing == null ? s.newExpense : s.editMovement,
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 48),
              ]),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LayoutBuilder(builder: (context, c) {
                    final keyH = c.maxHeight < 600 ? 44.0 : 52.0;
                    final pad = _Keypad(
                        keyHeight: keyH,
                        onKey: _key,
                        onSave: _save,
                        s: s,
                        label: widget.editing == null ? s.addExpense : s.saveChanges);
                    // landscape phones / short windows: fields and keypad side by side
                    if (c.maxWidth >= 600 && c.maxHeight < 520) {
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: ListView(children: fields)),
                        const SizedBox(width: 24),
                        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.only(top: 14, bottom: 16), child: pad)),
                      ]);
                    }
                    return Column(children: [
                      Expanded(child: ListView(children: fields)),
                      const SizedBox(height: 16),
                      pad,
                      const SizedBox(height: 16),
                    ]);
                  }),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.label, required this.onChanged});
  final String value;
  final String Function(String) label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Palette.surface2),
        ),
        child: Row(children: [
          for (final e in const ['Pago', 'Previsto'])
            Expanded(
              child: Material(
                color: value == e ? Palette.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onChanged(e),
                  child: SizedBox(
                    height: 36,
                    child: Center(
                      child: Text(label(e),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: value == e ? Palette.text : Palette.muted)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class _Keypad extends StatelessWidget {
  const _Keypad(
      {required this.keyHeight, required this.onKey, required this.onSave, required this.s, required this.label});
  final S s;
  final String label;
  final double keyHeight;
  final ValueChanged<String> onKey;
  final VoidCallback onSave;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['00', '0', 'back'],
  ];

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onKey(row[i]),
                      child: SizedBox(
                        height: keyHeight,
                        child: Center(
                          child: row[i] == 'back'
                              ? Icon(Icons.backspace_outlined, size: 22, semanticLabel: s.delete)
                              : Text(row[i], style: mono(size: 22, weight: FontWeight.w500)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.accent,
              foregroundColor: Palette.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: Text(label),
          ),
        ),
      ]);
}
