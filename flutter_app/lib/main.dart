import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'src/account.dart';
import 'src/app_controller.dart';
import 'src/backend.dart';
import 'src/config.dart';
import 'src/i18n.dart';
import 'src/layout.dart';
import 'src/screens/ajustes.dart';
import 'src/screens/auth.dart';
import 'src/screens/categorias.dart';
import 'src/screens/home.dart';
import 'src/screens/movimentos.dart';
import 'src/screens/nova.dart';
import 'src/screens/onboarding.dart';
import 'src/screens/plano.dart';
import 'src/screens/dashboard.dart';
import 'src/store.dart';
import 'src/theme.dart';
import 'src/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  Backend? backend;
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
    // email links (confirm account, reset password) come back to this page
    backend = SupabaseBackend(Supabase.instance.client,
        redirectTo: kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : null);
  } catch (_) {/* accounts unavailable: the app still works on-device */}
  final account = AccountController(store: store, backend: backend, prefs: prefs);
  await account.init();
  store.ensureRecurring(); // bills roll into the forecast as months pass
  runApp(FinApp(controller: AppController(store), account: account));
}

class FinApp extends StatelessWidget {
  const FinApp({super.key, required this.controller, required this.account});
  final AppController controller;
  final AccountController account;

  @override
  Widget build(BuildContext context) => AccountScope(
        account: account,
        child: AppScope(
          controller: controller,
          // rebuilt when the language changes, so dialogs and pickers follow it
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => MaterialApp(
              title: controller.s.appName,
              debugShowCheckedModeBanner: false,
              theme: buildTheme(),
              themeMode: ThemeMode.dark,
              locale: controller.lang == 'pt' ? const Locale('pt', 'PT') : const Locale('en'),
              supportedLocales: const [Locale('pt', 'PT'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: const AccountGate(),
            ),
          ),
        ),
      );
}

/// Picks the screen from the account state; pulls changes when the app comes back to the foreground.
class AccountGate extends StatefulWidget {
  const AccountGate({super.key});

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: () => AccountScope.of(context, listen: false).pull());
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    final notice = account.takeNotice();
    if (notice != null) {
      final text = switch (notice) { Notice.syncConflict => AppScope.of(context, listen: false).s.syncConflict };
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? toast(context, text) : null);
    }
    return switch (account.status) {
      AccountStatus.signedOut => const AuthScreen(),
      AccountStatus.setup => const SetupScreen(),
      AccountStatus.recovering => const RecoveryScreen(),
      AccountStatus.unlocked || AccountStatus.guest when account.needsOnboarding => const OnboardingScreen(),
      AccountStatus.guest || AccountStatus.unlocked => const Shell(),
    };
  }
}

List<(IconData, IconData, String)> _destinations(S s) => [
      (Icons.home_outlined, Icons.home, s.navHome),
      (Icons.format_list_bulleted, Icons.format_list_bulleted, s.navMovements),
      (Icons.pie_chart_outline, Icons.pie_chart, s.navCategories),
      (Icons.savings_outlined, Icons.savings, s.navDashboard),
      (Icons.event_note_outlined, Icons.event_note, s.navPlan),
    ];

/// Navigation adapts to the window: bottom bar on phones, rail on tablets,
/// extended rail with labels on desktop / large tablets.
class Shell extends StatelessWidget {
  const Shell({super.key});

  static const _pages = [HomeScreen(), MovimentosScreen(), CategoriasScreen(), DashboardScreen(), PlanoScreen()];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final size = sizeClassOf(context);
    final page = _pages[app.tab];

    if (size == SizeClass.compact) {
      return Scaffold(
        body: SafeArea(bottom: false, child: page),
        floatingActionButton: app.tab < 2
            ? FloatingActionButton(
                tooltip: s.newExpense, onPressed: () => openNova(context), child: const Icon(Icons.add, size: 26))
            : null,
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Palette.line))),
          child: NavigationBar(
            selectedIndex: app.tab,
            onDestinationSelected: app.setTab,
            destinations: [
              for (final (icon, selected, label) in _destinations(s))
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ),
      );
    }

    final extended = size == SizeClass.expanded;
    // phones in landscape: too short for labels + buttons in the rail
    final short = isShort(context);
    return Focus(
      autofocus: true,
      onKeyEvent: extended ? (_, e) => _shortcut(context, app, e) : null,
      child: Scaffold(
      floatingActionButton: short
          ? FloatingActionButton(
              tooltip: s.newExpense, onPressed: () => openNova(context), child: const Icon(Icons.add))
          : null,
      body: SafeArea(
        child: Row(children: [
          NavigationRail(
            extended: extended && !short,
            minExtendedWidth: 220,
            labelType: extended || short ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            selectedIndex: app.tab,
            onDestinationSelected: app.setTab,
            leading: short ? null : Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: extended
                  ? FloatingActionButton.extended(
                      tooltip: s.newExpense,
                      onPressed: () => openNova(context),
                      shape: const StadiumBorder(),
                      icon: const Icon(Icons.add),
                      label: Text(s.newExpense, style: const TextStyle(fontWeight: FontWeight.w600)),
                    )
                  : FloatingActionButton(
                      tooltip: s.newExpense, onPressed: () => openNova(context), child: const Icon(Icons.add)),
            ),
            trailing: short ? null : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: s.settings,
                  color: Palette.muted,
                  icon: const Icon(Icons.tune),
                  onPressed: () => openAjustes(context),
                ),
                if (extended) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 190,
                    child: Text(s.shortcutsHint,
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.4, color: Palette.muted)),
                  ),
                ],
              ]),
            ),
            destinations: [
              for (final (icon, selected, label) in _destinations(s))
                NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Palette.line),
          Expanded(child: page),
        ]),
      ),
      ),
    );
  }

  /// Desktop keys: N opens a new expense, 1–5 switch tab. Left alone while a text field has focus.
  static KeyEventResult _shortcut(BuildContext context, AppController app, KeyEvent e) {
    if (e is! KeyDownEvent || HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyN) {
      openNova(context);
      return KeyEventResult.handled;
    }
    final i = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ].indexOf(k);
    if (i < 0) return KeyEventResult.ignored;
    app.setTab(i);
    return KeyEventResult.handled;
  }
}
