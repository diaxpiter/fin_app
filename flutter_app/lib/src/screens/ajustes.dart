import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> openAjustes(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AjustesScreen()));

class AjustesScreen extends StatelessWidget {
  const AjustesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final startDay = app.store.state.config.cycleStartDay;

    Widget row(String title, String sub, {VoidCallback? onTap, Color color = Palette.text}) => InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, color: color)),
              const SizedBox(height: 3),
              Text(sub, style: const TextStyle(fontSize: 12, color: Palette.muted)),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
      body: ScreenList(bottom: 32, children: [
        Container(height: 1, color: Palette.line),
        row('Dia de início do ciclo', 'Os ciclos começam no dia $startDay'),
        row('Exportar dados', 'Copia uma cópia (JSON) para a área de transferência', onTap: () async {
          await Clipboard.setData(ClipboardData(text: app.store.exportJSON()));
          if (context.mounted) toast(context, 'Cópia copiada');
        }),
        row('Importar dados', 'Cola uma cópia exportada antes (também do painel web)',
            onTap: () => _import(context, app)),
        row('Repor dados de exemplo', 'Apaga os teus movimentos e volta ao início', color: Palette.neg,
            onTap: () async {
          if (await confirm(context, 'Repor os dados de exemplo? Os teus movimentos serão apagados.', 'Repor')) {
            app.store.resetToSeed();
            app.resetCycle();
            if (context.mounted) toast(context, 'Dados repostos');
          }
        }),
        const SizedBox(height: 24),
        const Text('Os dados ficam só neste dispositivo e nunca são enviados para nenhum servidor. '
            'Exporta uma cópia de vez em quando.',
            style: TextStyle(fontSize: 12, height: 1.5, color: Palette.muted)),
      ]),
    );
  }

  Future<void> _import(BuildContext context, AppController app) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: clip?.text?.trimLeft().startsWith('{') == true ? clip!.text : '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Importar dados'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            style: mono(size: 12),
            decoration: const InputDecoration(hintText: 'Cola aqui o JSON exportado', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Importar')),
        ],
      ),
    );
    if (text == null || !context.mounted) return;
    try {
      app.store.importJSON(text);
      app.resetCycle();
      toast(context, 'Dados importados');
    } catch (_) {
      toast(context, 'Ficheiro inválido');
    }
  }
}
