// Fixed bills (contas fixas): the row used in lists and the add/edit form.
// The form is a bottom sheet on phones and a dialog on wider screens.

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../logic.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Common bills offered as one-tap starting points (amount and day still to fill in).
const billSuggestions = [
  Recurring(id: '', description: 'Salário', category: 'Receita', cents: 0, day: 1, variable: true),
  Recurring(id: '', description: 'Renda', category: 'Moradia', cents: 0, day: 1),
  Recurring(id: '', description: 'Luz', category: 'Moradia', cents: 0, day: 1, variable: true),
  Recurring(id: '', description: 'Água', category: 'Moradia', cents: 0, day: 1, variable: true),
  Recurring(id: '', description: 'Internet', category: 'Moradia', cents: 0, day: 1),
  Recurring(id: '', description: 'Telemóvel', category: 'Moradia', cents: 0, day: 1),
  Recurring(id: '', description: 'Ginásio', category: 'Subscrição', cents: 0, day: 1),
  Recurring(id: '', description: 'Streaming', category: 'Subscrição', cents: 0, day: 1),
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
    final m = AppScope.of(context).model;
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
            if (bill.variable) _pill('Variável'),
            if (bill.to != null) _pill('até ${cycleLabel(bill.to!).substring(0, 3).toLowerCase()}'),
          ]),
          trailing: [
            Text('${income ? '+' : ''}${fmtCents(bill.cents)}',
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

/// Accepts "1.234,56", "1234,56", "35" and also "35.50" (dot as decimal point).
int? parseAmount(String text) {
  final t = text.replaceAll(RegExp(r'[\s€]'), '');
  if (t.isEmpty) return null;
  if (!t.contains(',') && RegExp(r'^\d+\.\d{1,2}$').hasMatch(t)) return parseMoney(t.replaceFirst('.', ','));
  return parseMoney(t);
}

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
      text: (widget.bill?.cents ?? 0) > 0 ? fmtCents(widget.bill!.cents) : '');
  late String _cat = widget.bill?.category ?? 'Moradia';
  late int _day = widget.bill?.day ?? 1;
  late bool _variable = widget.bill?.variable ?? false;
  late String? _to = widget.bill?.to;
  String? _error;

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save(AppController app) {
    final desc = _desc.text.trim();
    final cents = parseAmount(_amount.text);
    if (desc.isEmpty) return setState(() => _error = 'Indica uma descrição.');
    if (cents == null || cents <= 0) return setState(() => _error = 'Indica um valor (ex.: 45,90).');
    final m = app.model;
    final old = widget.bill;
    app.store.saveRecurring(
      Recurring(
        id: _isNew ? Store.newRecurringId() : old!.id,
        description: desc,
        category: _cat,
        cents: cents,
        day: _day,
        variable: _variable,
        // a new bill starts in the current cycle; it never fills past months
        from: _isNew ? cycleIdOf(m.today, m.state.config.cycleStartDay) : old!.from,
        to: _to,
      ),
      m.today,
    );
    toast(context, _isNew ? 'Conta fixa adicionada' : 'Conta fixa atualizada');
    Navigator.of(context).pop();
  }

  Future<void> _delete(AppController app) async {
    if (!await confirm(context,
        'Apagar "${widget.bill!.description}"? Os movimentos já pagos ficam; os previstos saem da previsão.', 'Apagar')) {
      return;
    }
    if (!mounted) return;
    app.store.removeRecurring(widget.bill!.id, app.today);
    toast(context, 'Conta fixa apagada');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.model;
    final now = cycleIdOf(m.today, m.state.config.cycleStartDay);
    final endOptions = {
      ...cycleRange(now, nextCycleId(now, 23)),
      if (_to != null) _to!,
    }.toList()
      ..sort();

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
          Text(_isNew ? 'Nova conta fixa' : 'Editar conta fixa',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(controller: _desc, textCapitalization: TextCapitalization.sentences, decoration: deco('Descrição', hint: 'Ex.: Renda')),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: mono(size: 16),
            decoration: deco(_variable ? 'Valor estimado' : 'Valor', suffix: '€', hint: '0,00'),
          ),
          const SizedBox(height: 14),
          const Lbl('Categoria'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in m.state.categories)
              PillChip(label: c.name, selected: _cat == c.name, onTap: () => setState(() => _cat = c.name)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: InputDecorator(
                decoration: deco('Dia do mês'),
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
            const SizedBox(width: 10),
            Expanded(
              child: InputDecorator(
                decoration: deco('Termina'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _to,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: Palette.surface,
                    menuMaxHeight: 320,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Sem fim')),
                      for (final id in endOptions) DropdownMenuItem<String?>(value: id, child: Text(cycleLabel(id))),
                    ],
                    onChanged: (v) => setState(() => _to = v),
                  ),
                ),
              ),
            ),
          ]),
          if (_day > 28)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Nos meses mais curtos conta no último dia.', style: TextStyle(fontSize: 12, color: Palette.muted)),
            ),
          SwitchListTile(
            value: _variable,
            onChanged: (v) => setState(() => _variable = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('O valor muda todos os meses', style: TextStyle(fontSize: 15)),
            subtitle: const Text('Usa uma estimativa; ajusta quando souberes o valor.',
                style: TextStyle(fontSize: 12, color: Palette.muted)),
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
                child: const Text('Apagar'),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Palette.muted),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _save(app),
              style: FilledButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Palette.bg),
              child: const Text('Guardar'),
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
    final have = AppScope.of(context).store.state.recurring.map((r) => r.description.toLowerCase()).toSet();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final s in billSuggestions.where((s) => !have.contains(s.description.toLowerCase())))
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
        label: const Text('Outra', style: TextStyle(color: Palette.bg, fontWeight: FontWeight.w600)),
        backgroundColor: Palette.accent,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        onPressed: () => showBillEditor(context),
      ),
    ]);
  }
}
