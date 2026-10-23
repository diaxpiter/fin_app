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
import 'preferences.dart';

enum _Kind { expense, income, transfer }

final _numpadDigits = {
  LogicalKeyboardKey.numpad0: '0',
  LogicalKeyboardKey.numpad1: '1',
  LogicalKeyboardKey.numpad2: '2',
  LogicalKeyboardKey.numpad3: '3',
  LogicalKeyboardKey.numpad4: '4',
  LogicalKeyboardKey.numpad5: '5',
  LogicalKeyboardKey.numpad6: '6',
  LogicalKeyboardKey.numpad7: '7',
  LogicalKeyboardKey.numpad8: '8',
  LogicalKeyboardKey.numpad9: '9',
};

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
  _Kind? _kind;
  String? _account, _toAccount;

  /// Picks the kind and sensible accounts: expenses from the everyday account,
  /// income into the current account, transfers from current to everyday.
  void _setKind(_Kind k, AppState state) {
    String first(bool Function(Account) test, {String? not}) =>
        state.accounts.where((a) => test(a) && a.id != not).firstOrNull?.id ??
        state.accounts.firstWhere((a) => a.id != not, orElse: () => state.accounts.first).id;
    final cats = state.categories;
    _kind = k;
    switch (k) {
      case _Kind.expense:
        _cat = cats.any((c) => c.name == _cat && c.type == 'Saída')
            ? _cat
            : cats.firstWhere((c) => c.type == 'Saída').name;
        _account = first((a) => a.kind == AccountKind.spending);
        _toAccount = null;
      case _Kind.income:
        _cat = cats.firstWhere((c) => c.type == 'Entrada').name;
        _account = first((a) => a.kind == AccountKind.current);
        _toAccount = null;
      case _Kind.transfer:
        _cat = transferCategory.name;
        _account = first((a) => a.kind == AccountKind.current);
        _toAccount = first((a) => a.kind == AccountKind.spending, not: _account);
    }
  }
  String? _error;
  late final _desc = TextEditingController(text: widget.editing?.description ?? '');

  // The amount and the description are selected separately. While the amount is
  // selected the on-screen keypad (and a physical keyboard's digits) type into it;
  // while the description is, the keypad steps aside for the system keyboard.
  final _amountFocus = FocusNode(debugLabel: 'amount');
  final _descFocus = FocusNode(debugLabel: 'description');

  @override
  void initState() {
    super.initState();
    _amountFocus.addListener(_focusChanged);
    _descFocus.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _desc.dispose();
    _amountFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  void _selectAmount() => _amountFocus.requestFocus();

  void _key(String v) => setState(() {
        _error = null;
        if (!_amountFocus.hasFocus) _selectAmount();
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
    final state = app.store.state;
    final transfer = _kind == _Kind.transfer;
    if (transfer && (_toAccount == null || _toAccount == _account)) {
      setState(() => _error = s.sameAccount);
      return;
    }
    final typed = _desc.text.trim();
    final desc = typed.isNotEmpty
        ? typed
        : transfer
            ? s.transferLabel(s.accountName(state.accountById(_account)!), s.accountName(state.accountById(_toAccount)!))
            : _cat;
    final messenger = ScaffoldMessenger.of(context);
    var message = switch (_kind!) {
      _Kind.expense => s.expenseAdded,
      _Kind.income => s.incomeAdded,
      _Kind.transfer => s.transferAdded,
    };

    final old = widget.editing;
    if (old != null) {
      app.store.updateMovement(old.copyWith(
          date: _date,
          description: desc,
          category: _cat,
          cents: _cents,
          estado: _estado,
          account: _account,
          toAccount: _toAccount,
          clearToAccount: !transfer));
      app.pickCycle(cycleOfMovement(app.store.state.movements.firstWhere((m) => m.id == old.id),
          app.store.state.config.cycle));
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
        app.addMovement(
            date: _date!,
            description: desc,
            category: _cat,
            cents: _cents,
            estado: _estado,
            account: _account,
            toAccount: _toAccount);
      } else {
        app.store.payPlanned(choice, cents: _cents, date: _date!);
        app.pickCycle(cycleIdOf(_date!, app.store.state.config.cycle));
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

  // Physical keyboard (desktop, web, tablets with keyboards) while the amount is selected:
  // digits, backspace, enter. A letter starts the description. Keys typed in the
  // description never reach here: they belong to the text field.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final ch = e.character;
    // the number pad's digits don't always come with a character (Num Lock, some browsers)
    final digit = ch != null && RegExp(r'^\d$').hasMatch(ch) ? ch : _numpadDigits[e.logicalKey];
    if (digit != null) {
      _key(digit);
      return KeyEventResult.handled;
    }
    final keys = HardwareKeyboard.instance;
    if (ch != null &&
        RegExp(r'^\p{L}$', unicode: true).hasMatch(ch) &&
        !keys.isControlPressed &&
        !keys.isMetaPressed &&
        !keys.isAltPressed) {
      final text = _desc.text + ch;
      _desc.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      _descFocus.requestFocus();
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

  /// The user's regular expenses as chips: one tap fills the amount, category and description.
  List<Widget> _frequentChips(AppController app, AppState state, String today) {
    final frequent = frequentExpenses(state, today);
    if (frequent.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          for (final f in frequent)
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text('${f.description} · ${app.money.amount(f.cents)}', style: const TextStyle(fontSize: 12)),
              onPressed: () => setState(() {
                _error = null;
                _cents = f.cents;
                _cat = f.category;
                _desc.text = f.description;
              }),
            ),
        ]),
      ),
      const SizedBox(height: 10),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final lang = app.lang;
    final m = app.model;
    _date ??= m.today;
    final state = m.state;
    final multi = state.accounts.length > 1;
    if (_kind == null) {
      final e = widget.editing;
      if (e == null) {
        _setKind(_Kind.expense, state);
      } else {
        // editing: keep what the movement is, on its accounts
        _kind = isTransfer(e, typesOf(state)) ? _Kind.transfer : (m.isIncome(e.category) ? _Kind.income : _Kind.expense);
        _account = e.account ?? state.defaultAccount;
        _toAccount = e.toAccount;
      }
    }
    final kind = _kind!;
    final typingDesc = _descFocus.hasFocus;
    final amountActive = !typingDesc;
    final amountSize = MediaQuery.sizeOf(context).height < 720 ? 52.0 : 60.0;
    final cats = state.categories.where((c) => c.type == (kind == _Kind.income ? 'Entrada' : 'Saída'));
    final kinds = [_Kind.expense, _Kind.income, if (multi || kind == _Kind.transfer) _Kind.transfer];
    String kindLabel(_Kind k) => switch (k) {
          _Kind.expense => s.kindExpense,
          _Kind.income => s.kindIncome,
          _Kind.transfer => s.kindTransfer,
        };

    final fields = <Widget>[
      const SizedBox(height: 4),
      _Segmented<_Kind>(
        value: kind,
        items: kinds,
        label: kindLabel,
        onChanged: (k) => setState(() => _setKind(k, state)),
      ),
      const SizedBox(height: 10),
      Focus(
        focusNode: _amountFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Semantics(
          button: true,
          selected: amountActive,
          label: s.amount,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _selectAmount,
            child: AnimatedContainer(
              key: const ValueKey('nova-amount'),
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: amountActive ? Palette.accent : Palette.surface2, width: amountActive ? 2 : 1))),
              child: BigAmount(_cents,
                  size: amountSize, alignment: Alignment.center, color: _error != null ? Palette.neg : Palette.text),
            ),
          ),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Palette.neg, fontSize: 13)),
        ),
      const SizedBox(height: 14),
      if (widget.editing == null && kind == _Kind.expense) ..._frequentChips(app, state, m.today),
      AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: typingDesc ? Palette.accent : Palette.surface2, width: typingDesc ? 2 : 1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Lbl(s.description),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            focusNode: _descFocus,
            textInputAction: TextInputAction.done,
            // "done" (or Enter) goes back to the amount and its keypad
            onSubmitted: (_) => _selectAmount(),
            // tapping anywhere else (a category, the date, the keypad) closes the system keyboard
            onTapOutside: (_) {
              if (_descFocus.hasFocus) _selectAmount();
            },
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            decoration: InputDecoration.collapsed(
                hintText: switch (kind) {
                  _Kind.expense => s.expenseHint,
                  _Kind.income => s.incomeHint,
                  _Kind.transfer => s.optional,
                },
                hintStyle: const TextStyle(color: Color(0xFF55555B))),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (kind == _Kind.transfer) ...[
        Lbl(s.from),
        const SizedBox(height: 8),
        AccountChips(
            value: _account!,
            onChanged: (v) => setState(() {
                  _account = v;
                  if (_toAccount == v) _toAccount = null;
                })),
        const SizedBox(height: 14),
        Lbl(s.to),
        const SizedBox(height: 8),
        AccountChips(value: _toAccount ?? '', exclude: _account, onChanged: (v) => setState(() => _toAccount = v)),
      ] else ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cats)
            PillChip(label: s.category(c.name), selected: _cat == c.name, onTap: () => setState(() => _cat = c.name)),
        ]),
        if (multi) ...[
          const SizedBox(height: 14),
          Lbl(s.account),
          const SizedBox(height: 8),
          AccountChips(value: _account!, onChanged: (v) => setState(() => _account = v)),
        ],
      ],
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
        Expanded(
            child: _Segmented<String>(
                value: _estado,
                items: const ['Pago', 'Previsto'],
                label: s.estado,
                onChanged: (v) => setState(() => _estado = v))),
      ]),
    ];

    return Scaffold(
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
                  child: Text(
                      widget.editing != null
                          ? s.editMovement
                          : switch (kind) {
                              _Kind.expense => s.newExpense,
                              _Kind.income => s.newIncome,
                              _Kind.transfer => s.newTransfer,
                            },
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 48),
              ]),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LayoutBuilder(builder: (context, c) {
                    // keys shrink on short screens so categories, date and status stay in view
                    final keyH = ((c.maxHeight - 430) / 4 - 6).clamp(40.0, 52.0);
                    final side = c.maxWidth >= 600 && c.maxHeight < 520;
                    final pad = _Keypad(
                        keyHeight: keyH,
                        // the system keyboard takes the keypad's place while typing the description
                        showKeys: side || !typingDesc,
                        onKey: _key,
                        onSave: _save,
                        s: s,
                        label: widget.editing != null
                            ? s.saveChanges
                            : switch (kind) {
                                _Kind.expense => s.addExpense,
                                _Kind.income => s.addIncome,
                                _Kind.transfer => s.addTransfer,
                              });
                    // landscape phones / short windows: fields and keypad side by side
                    if (side) {
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: ListView(children: fields)),
                        const SizedBox(width: 24),
                        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.only(top: 14, bottom: 16), child: pad)),
                      ]);
                    }
                    return Column(children: [
                      Expanded(child: ListView(children: fields)),
                      const SizedBox(height: 10),
                      pad,
                      const SizedBox(height: 12),
                    ]);
                  }),
                ),
              ),
            ]),
          ),
        ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.items, required this.label, required this.onChanged});
  final T value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Palette.surface2),
        ),
        child: Row(children: [
          for (final e in items)
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
      {required this.keyHeight,
      required this.onKey,
      required this.onSave,
      required this.s,
      required this.label,
      this.showKeys = true});
  final S s;
  final String label;
  final double keyHeight;
  final bool showKeys;
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
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: showKeys ? _keys() : const SizedBox(width: double.infinity),
        ),
        SizedBox(
          width: double.infinity,
          height: 50,
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

  Widget _keys() => Column(mainAxisSize: MainAxisSize.min, children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
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
        const SizedBox(height: 2),
      ]);
}
