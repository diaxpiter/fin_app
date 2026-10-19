// Fixed bills (contas fixas): the row used in lists and the add/edit form.
// The form is a bottom sheet on phones and a dialog on wider screens.

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../holidays.dart';
import '../i18n.dart';
import '../layout.dart';
import '../logic.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Common bills offered as one-tap starting points (amount and day still to fill in).
List<Recurring> billSuggestions(S s) => [
      for (final (category, name, variable) in s.billSuggestions)
        Recurring(
          id: '',
          description: name,
          category: category,
          cents: 0,
          day: 1,
          variable: variable,
          // salaries are usually paid the business day before a weekend or holiday
          shift: category == 'Receita' ? DayShift.before : DayShift.none,
        ),
    ];

Widget _pill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: Palette.line2), borderRadius: BorderRadius.circular(6)),
      child: Text(text.toUpperCase(),
          style: mono(size: 10, weight: FontWeight.w500, color: Palette.muted).copyWith(letterSpacing: 0.4)),
    );

class BillRow extends StatelessWidget {
  const BillRow(this.bill, {super.key});
  final Recurring bill;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.model;
    final now = cycleIdOf(m.today, m.state.config.cycleStartDay);
    final income = m.isIncome(bill.category);
    final ended = bill.to != null && bill.to!.compareTo(now) < 0;
    return Opacity(
      opacity: ended ? 0.45 : 1,
      child: InkWell(
        onTap: () => showBillEditor(context, bill: bill),
        child: InfoRow(
          leading: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(border: Border.all(color: Palette.surface2), borderRadius: BorderRadius.circular(8)),
            child: Text('${bill.day}', style: mono(size: 13, color: Palette.soft)),
          ),
          title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(bill.description, style: const TextStyle(fontSize: 15)),
            if (bill.variable) _pill(app.s.variable),
            if (bill.shift != DayShift.none) _pill(app.s.shift(bill.shift)),
            if (bill.to != null) _pill(app.s.until(cycleLabel(bill.to!, app.lang).substring(0, 3))),
          ]),
          trailing: [
            Text('${income ? '+' : ''}${app.money.amount(bill.cents)}',
                style: mono(color: income ? Palette.accent : Palette.text)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}

/// Opens the form. [bill] with an empty id (e.g. a suggestion) creates a new bill.
Future<void> showBillEditor(BuildContext context, {Recurring? bill}) {
  const form = _formMaxWidth;
  if (sizeClassOf(context) == SizeClass.compact) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BillForm(bill: bill),
    );
  }
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Palette.surface,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: form), child: _BillForm(bill: bill)),
    ),
  );
}

const _formMaxWidth = 460.0;

class _BillForm extends StatefulWidget {
  const _BillForm({this.bill});
  final Recurring? bill;

  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  late final bool _isNew = widget.bill == null || widget.bill!.id.isEmpty;
  late final _desc = TextEditingController(text: widget.bill?.description ?? '');
  late final _amount = TextEditingController(
      text: (widget.bill?.cents ?? 0) > 0 ? AppScope.of(context, listen: false).money.amount(widget.bill!.cents) : '');
  late String _cat = widget.bill?.category ?? 'Moradia';
  late int _day = widget.bill?.day ?? 1;
  late bool _variable = widget.bill?.variable ?? false;
  late String? _from = (widget.bill?.id.isEmpty ?? true) ? null : widget.bill!.from;
  late String? _to = widget.bill?.to;
  late DayShift _shift = widget.bill?.shift ?? DayShift.none;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save(AppController app) {
    final s = app.s;
    final desc = _desc.text.trim();
    final cents = parseAmount(_amount.text);
    if (desc.isEmpty) return setState(() => _error = s.enterDescription);
    if (cents == null || cents <= 0) return setState(() => _error = s.enterAmountExample);
    final m = app.model;
    // a new bill starts in the current cycle unless a first payment was picked; it never fills past months
    final from = _from ?? (_isNew ? cycleIdOf(m.today, m.state.config.cycleStartDay) : null);
    if (from != null && _to != null && _to!.compareTo(from) < 0) return setState(() => _error = s.endBeforeStart);
    final old = widget.bill;
    app.store.saveRecurring(
      Recurring(
        id: _isNew ? Store.newRecurringId() : old!.id,
        description: desc,
        category: _cat,
        cents: cents,
        day: _day,
        variable: _variable,
        from: from,
        to: _to,
        shift: _shift,
      ),
      m.today,
    );
    toast(context, _isNew ? s.billAdded : s.billUpdated);
    Navigator.of(context).pop();
  }

  /// When the bill will next fall, with the weekend/holiday rule applied, e.g. "sexta, 23 out".
  String _nextDate(Model m) {
    final lang = AppScope.of(context, listen: false).lang;
    final start = m.state.config.cycleStartDay;
    var cycle = cycleIdOf(m.today, start);
    for (var i = 0; i < 3; i++, cycle = nextCycleId(cycle)) {
      final d = shiftToBusinessDay(occurrenceDate(_day, cycle, start), _shift, m.state.config.holidays);
      if (d.compareTo(m.today) >= 0) return '${weekday(d, lang)}, ${formatDay(d, lang)}';
    }
    return '';
  }

  /// The date the bill falls on in [cycle], e.g. "25 nov 2026".
  String _dateIn(Model m, String cycle, String lang) {
    final d = shiftToBusinessDay(
        occurrenceDate(_day, cycle, m.state.config.cycleStartDay), _shift, m.state.config.holidays);
    return '${formatDay(d, lang)} ${parseISO(d).y}';
  }

  Future<void> _pickFirst(Model m) async {
    final start = m.state.config.cycleStartDay;
    final initial = _from == null ? m.today : occurrenceDate(_day, _from!, start);
    final d = await pickDate(context, initial);
    if (d == null) return;
    setState(() {
      _day = parseISO(d).d; // the first payment's day becomes the day of the month
      _from = cycleIdOf(d, start);
      _error = null;
    });
  }

  Future<void> _pickLast(Model m) async {
    final start = m.state.config.cycleStartDay;
    final initial = _to != null
        ? occurrenceDate(_day, _to!, start)
        : occurrenceDate(_day, nextCycleId(_from ?? cycleIdOf(m.today, start), 11), start);
    final d = await pickDate(context, initial);
    if (d == null) return;
    setState(() {
      _to = cycleIdOf(d, start);
      _error = null;
    });
  }

  Future<void> _delete(AppController app) async {
    final s = app.s;
    if (!await confirm(context, s.deleteBillQ(widget.bill!.description), s.delete)) return;
    if (!mounted) return;
    app.store.removeRecurring(widget.bill!.id, app.today);
    toast(context, s.billDeleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final m = app.model;
    final now = cycleIdOf(m.today, m.state.config.cycleStartDay);

    InputDecoration deco(String label, {String? suffix, String? hint}) => InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          filled: true,
          fillColor: Palette.bg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        );

    return Padding(
      // keep the form above the on-screen keyboard
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(_isNew ? s.newBill : s.editBill,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(controller: _desc, textCapitalization: TextCapitalization.sentences, decoration: deco(s.description, hint: s.billHint)),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [MoneyInputFormatter()],
            style: mono(size: 16),
            decoration: deco(_variable ? s.estimatedAmount : s.amount, suffix: app.money.symbol, hint: app.money.amount(0)),
          ),
          const SizedBox(height: 14),
          Lbl(s.categoryLabel),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in m.state.categories)
              PillChip(label: s.category(c.name), selected: _cat == c.name, onTap: () => setState(() => _cat = c.name)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: deco(s.dayOfMonth),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _day,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: Palette.surface,
                    menuMaxHeight: 320,
                    items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                    onChanged: (v) => setState(() => _day = v ?? _day),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DateField(
                label: s.firstPayment,
                text: _dateIn(m, _from ?? now, app.lang),
                onTap: () => _pickFirst(m),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DateField(
                label: s.lastPayment,
                text: _to == null ? s.noEnd : _dateIn(m, _to!, app.lang),
                onTap: () => _pickLast(m),
                onClear: _to == null ? null : () => setState(() => _to = null),
              ),
            ),
          ]),
          if (_day > 28)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(s.shortMonths, style: const TextStyle(fontSize: 12, color: Palette.muted)),
            ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: deco(s.weekendRule),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DayShift>(
                value: _shift,
                isDense: true,
                isExpanded: true,
                dropdownColor: Palette.surface,
                items: [for (final d in DayShift.values) DropdownMenuItem(value: d, child: Text(s.shift(d)))],
                onChanged: (v) => setState(() => _shift = v ?? _shift),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s.nextOn(_nextDate(m)), style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ),
          SwitchListTile(
            value: _variable,
            onChanged: (v) => setState(() => _variable = v),
            contentPadding: EdgeInsets.zero,
            title: Text(s.variableTitle, style: const TextStyle(fontSize: 15)),
            subtitle: Text(s.variableSub, style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, style: const TextStyle(color: Palette.neg, fontSize: 13)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            if (!_isNew)
              TextButton(
                onPressed: () => _delete(app),
                style: TextButton.styleFrom(foregroundColor: Palette.neg),
                child: Text(s.delete),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Palette.muted),
              child: Text(s.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _save(app),
              style: FilledButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Palette.bg),
              child: Text(s.save),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// "Add" button plus one-tap suggestions for bills the user doesn't have yet.
class BillSuggestions extends StatelessWidget {
  const BillSuggestions({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final have = app.store.state.recurring.map((r) => r.description.toLowerCase()).toSet();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final s in billSuggestions(app.s).where((s) => !have.contains(s.description.toLowerCase())))
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: Text(s.description),
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: Palette.line2),
          shape: const StadiumBorder(),
          onPressed: () => showBillEditor(context, bill: s),
        ),
      ActionChip(
        avatar: const Icon(Icons.add, size: 16, color: Palette.bg),
        label: Text(app.s.otherBill, style: const TextStyle(color: Palette.bg, fontWeight: FontWeight.w600)),
        backgroundColor: Palette.accent,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        onPressed: () => showBillEditor(context),
      ),
    ]);
  }
}
