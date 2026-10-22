import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../download.dart';
import '../import_csv.dart';
import '../layout.dart';
import '../logic.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> openImport(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen()));

/// Reads a bank's CSV, sorts the rows by what the user already filed, and lets them check it before it is saved.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  List<ImportItem>? _items;
  String? _error, _account;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final text = await pickTextFile();
    if (text == null || !mounted) return;
    _text.text = text;
    _analyse();
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text == null || !mounted) return;
    _text.text = clip!.text!;
    _analyse();
  }

  void _analyse() {
    final app = AppScope.of(context, listen: false);
    final parsed = parseBankCsv(_text.text);
    setState(() {
      if (parsed == null) {
        _items = null;
        _error = app.s.importUnknown;
      } else {
        _error = null;
        _items = planImport(app.store.state, parsed.rows);
      }
    });
  }

  void _import() {
    final app = AppScope.of(context, listen: false);
    final n = app.store.importMovements(_items!, account: _account);
    app.resetCycle();
    toast(context, app.s.importDone(n));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final state = app.store.state;
    final items = _items;
    final chosen = items?.where((i) => i.include).length ?? 0;
    final counts = items == null
        ? null
        : (
            items.where((i) => i.action == ImportAction.add).length,
            items.where((i) => i.action == ImportAction.markPaid).length,
            items.where((i) => i.action == ImportAction.skip).length,
          );

    return Scaffold(
      appBar: AppBar(title: Text(s.importStatement, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
      body: ScreenList(bottom: 32, children: [
        Text(s.importHow, style: const TextStyle(fontSize: 14, height: 1.45, color: Palette.muted)),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 8, children: [
          if (canPickFile)
            FilledButton.icon(
              onPressed: _pickFile,
              style: FilledButton.styleFrom(backgroundColor: Palette.accent, foregroundColor: Palette.bg),
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(s.importPick),
            ),
          OutlinedButton.icon(
              onPressed: _paste, icon: const Icon(Icons.content_paste, size: 18), label: Text(s.importPaste)),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          maxLines: 5,
          style: mono(size: 12),
          decoration: InputDecoration(hintText: s.importHint, border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: _analyse, child: Text(s.importAnalyse)),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Palette.neg, fontSize: 13)),
          ),
        if (items != null) ...[
          const SizedBox(height: 14),
          Text(s.importSummary(counts!.$1, counts.$2, counts.$3), style: const TextStyle(fontSize: 13, color: Palette.muted)),
          if (state.accounts.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: _account,
              decoration: InputDecoration(labelText: s.goalAccount, border: const OutlineInputBorder()),
              dropdownColor: Palette.surface2,
              items: [for (final a in state.accounts) DropdownMenuItem(value: a.id, child: Text(s.accountName(a)))],
              onChanged: (v) => setState(() => _account = v),
            ),
          ],
          const SizedBox(height: 8),
          for (final it in items) _ImportRow(it, onChanged: () => setState(() {})),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: chosen == 0 ? null : _import,
            style: FilledButton.styleFrom(
                backgroundColor: Palette.accent, foregroundColor: Palette.bg, minimumSize: const Size.fromHeight(48)),
            child: Text(s.importRows(chosen)),
          ),
        ],
      ]),
    );
  }
}

class _ImportRow extends StatelessWidget {
  const _ImportRow(this.item, {required this.onChanged});
  final ImportItem item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final r = item.row;
    final income = r.cents > 0;
    final note = switch (item.action) {
      ImportAction.markPaid => s.importMarksPaid(item.plannedName ?? ''),
      ImportAction.skip => s.importDuplicate,
      ImportAction.add => null,
    };
    final cats = app.store.state.categories.where((c) => c.type == (income ? 'Entrada' : 'Saída')).toList();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(
          value: item.include,
          onChanged: (v) {
            item.include = v ?? false;
            onChanged();
          },
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.description.isEmpty ? '—' : r.description, style: const TextStyle(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(formatDay(r.date, app.lang), style: mono(size: 11, color: Palette.muted)),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(note, style: TextStyle(fontSize: 12, color: item.action == ImportAction.markPaid ? Palette.accent : Palette.muted)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: PopupMenuButton<String>(
                  tooltip: s.category(item.category),
                  color: Palette.surface2,
                  onSelected: (v) {
                    item.category = v;
                    onChanged();
                  },
                  itemBuilder: (_) => [for (final c in cats) PopupMenuItem(value: c.name, child: Text(s.category(c.name)))],
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Dot(app.model.colorOf(item.category)),
                    const SizedBox(width: 8),
                    Text(s.category(item.category), style: const TextStyle(fontSize: 12, color: Palette.soft)),
                    const Icon(Icons.arrow_drop_down, size: 18, color: Palette.muted),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Text(app.money.amount(r.cents, sign: true), style: mono(color: income ? Palette.accent : Palette.text)),
      ]),
    );
  }
}
