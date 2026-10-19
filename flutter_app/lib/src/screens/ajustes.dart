import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account.dart';
import '../app_controller.dart';
import '../backend.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets.dart';
import 'preferences.dart';

Future<void> openAjustes(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AjustesScreen()));

class AjustesScreen extends StatelessWidget {
  const AjustesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;

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

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 10),
          child: Lbl(title),
        );

    final account = AccountScope.of(context);
    final signedIn = account.status == AccountStatus.unlocked;
    // back to the root so the account screens (sign-in…) aren't hidden behind this page
    void toRoot() => Navigator.of(context).popUntil((r) => r.isFirst);

    return Scaffold(
      appBar: AppBar(title: Text(s.settings, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
      body: ScreenList(bottom: 32, children: [
        Lbl(s.account),
        const SizedBox(height: 10),
        Container(height: 1, color: Palette.line),
        if (signedIn) ...[
          row(account.email ?? s.account, switch (account.sync) {
            SyncState.idle => s.synced,
            SyncState.syncing => s.syncing,
            SyncState.offline => s.offline,
          }, onTap: account.pull),
          row(s.signOut, s.signOutSub, onTap: () async {
            toRoot();
            await account.signOut();
          }),
          row(s.deleteAccount, s.deleteAccountSub, color: Palette.neg, onTap: () async {
            if (!await confirm(context, s.deleteAccountQ, s.delete)) return;
            try {
              await account.deleteAccount();
              if (context.mounted) toRoot();
            } on BackendError catch (e) {
              if (context.mounted) toast(context, s.error(e));
            }
          }),
        ] else if (account.available)
          row(s.createOrSignIn, s.createOrSignInSub, onTap: () {
            toRoot();
            account.showSignIn();
          }),
        section(s.preferences),
        PrefRow(label: s.language, child: const LanguagePicker()),
        PrefRow(label: s.currency, child: const CurrencyPicker()),
        PrefRow(label: s.startDay, hint: s.startDayHint, child: const StartDayPicker()),
        PrefRow(label: s.holidays, hint: s.holidaysHint, child: const HolidaysPicker()),
        section(s.data),
        Container(height: 1, color: Palette.line),
        row(s.exportData, s.exportSub, onTap: () async {
          await Clipboard.setData(ClipboardData(text: app.store.exportJSON()));
          if (context.mounted) toast(context, s.exported);
        }),
        row(s.importData, s.importSub, onTap: () => _import(context, app)),
        row(s.resetData, s.resetSub, color: Palette.neg, onTap: () async {
          if (await confirm(context, s.resetQ, s.resetAction)) {
            app.store.resetToSeed();
            app.resetCycle();
            if (context.mounted) toast(context, s.resetDone);
          }
        }),
        const SizedBox(height: 24),
        Text(signedIn ? s.privacySignedIn : s.privacyLocal,
            style: const TextStyle(fontSize: 12, height: 1.5, color: Palette.muted)),
      ]),
    );
  }

  Future<void> _import(BuildContext context, AppController app) async {
    final s = app.s;
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: clip?.text?.trimLeft().startsWith('{') == true ? clip!.text : '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text(s.importData),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            style: mono(size: 12),
            decoration: InputDecoration(hintText: s.pasteHint, border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(s.importAction)),
        ],
      ),
    );
    if (text == null || !context.mounted) return;
    try {
      app.store.importJSON(text);
      app.resetCycle();
      toast(context, s.imported);
    } catch (_) {
      toast(context, s.invalidBackup);
    }
  }
}
