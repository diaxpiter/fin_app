import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';

/// Full-screen page on phones (portrait or landscape), a centred dialog on tablets and desktop.
Future<void> openNova(BuildContext context) {
  if (sizeClassOf(context) == SizeClass.compact || isShort(context)) {
    return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const NovaScreen()));
  }
  final h = MediaQuery.sizeOf(context).height;
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Palette.bg,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Palette.line2)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 460, height: math.min(h - 48, 780), child: const NovaScreen()),
    ),
  );
}

class NovaScreen extends StatefulWidget {
  const NovaScreen({super.key});

  @override
  State<NovaScreen> createState() => _NovaScreenState();
}

class _NovaScreenState extends State<NovaScreen> {
  int _cents = 0;
  String _cat = 'Alimentação';
  String _estado = 'Pago';
  String? _date;
  String? _error;
  final _desc = TextEditingController();

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

  void _save() {
    if (_cents <= 0) {
      setState(() => _error = 'Indica um valor.');
      return;
    }
    final app = AppScope.of(context, listen: false);
    final desc = _desc.text.trim();
    app.addMovement(
        date: _date!, description: desc.isEmpty ? _cat : desc, category: _cat, cents: _cents, estado: _estado);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Despesa adicionada')));
  }

  Future<void> _pickDate() async {
    final d = DateTime.parse(_date!);
    final picked = await showDatePicker(
      context: context,
      initialDate: d,
      firstDate: DateTime(d.year - 5),
      lastDate: DateTime(d.year + 5),
    );
    if (picked != null) setState(() => _date = todayISO(picked));
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
    final m = app.model;
    _date ??= m.today;
    final cats = m.state.categories.where((c) => c.type == 'Saída');

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
          const Lbl('Descrição'),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            decoration: const InputDecoration.collapsed(
                hintText: 'Ex.: Supermercado', hintStyle: TextStyle(color: Color(0xFF55555B))),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in cats)
          PillChip(label: c.name, selected: _cat == c.name, onTap: () => setState(() => _cat = c.name)),
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
                    child: Text('${_date == m.today ? 'Hoje, ' : ''}${formatDay(_date!)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _Segmented(value: _estado, onChanged: (v) => setState(() => _estado = v))),
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
                  tooltip: 'Fechar',
                  color: Palette.muted,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Expanded(
                  child: Text('Nova despesa',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 48),
              ]),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LayoutBuilder(builder: (context, c) {
                    final keyH = c.maxHeight < 600 ? 44.0 : 52.0;
                    final pad = _Keypad(keyHeight: keyH, onKey: _key, onSave: _save);
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
  const _Segmented({required this.value, required this.onChanged});
  final String value;
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
                      child: Text(e,
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
  const _Keypad({required this.keyHeight, required this.onKey, required this.onSave});
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
                              ? const Icon(Icons.backspace_outlined, size: 22, semanticLabel: 'Apagar')
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
            child: const Text('Adicionar despesa'),
          ),
        ),
      ]);
}
