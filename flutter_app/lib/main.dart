import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/app_controller.dart';
import 'src/layout.dart';
import 'src/screens/ajustes.dart';
import 'src/screens/fixas.dart';
import 'src/screens/home.dart';
import 'src/screens/movimentos.dart';
import 'src/screens/nova.dart';
import 'src/screens/previsao.dart';
import 'src/store.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  runApp(FinApp(controller: AppController(store)));
}

class FinApp extends StatelessWidget {
  const FinApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AppScope(
        controller: controller,
        child: MaterialApp(
          title: 'Painel Financeiro',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          themeMode: ThemeMode.dark,
          locale: const Locale('pt', 'PT'),
          supportedLocales: const [Locale('pt', 'PT')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Shell(),
        ),
      );
}

const _destinations = [
  (Icons.home_outlined, Icons.home, 'Início'),
  (Icons.format_list_bulleted, Icons.format_list_bulleted, 'Movimentos'),
  (Icons.bar_chart_outlined, Icons.bar_chart, 'Previsão'),
  (Icons.repeat, Icons.repeat, 'Fixas'),
];

/// Navigation adapts to the window: bottom bar on phones, rail on tablets,
/// extended rail with labels on desktop / large tablets.
class Shell extends StatelessWidget {
  const Shell({super.key});

  static const _pages = [HomeScreen(), MovimentosScreen(), PrevisaoScreen(), FixasScreen()];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final size = sizeClassOf(context);
    final page = _pages[app.tab];

    if (size == SizeClass.compact) {
      return Scaffold(
        body: SafeArea(bottom: false, child: page),
        floatingActionButton: app.tab < 2
            ? FloatingActionButton(
                tooltip: 'Nova despesa', onPressed: () => openNova(context), child: const Icon(Icons.add, size: 26))
            : null,
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Palette.line))),
          child: NavigationBar(
            selectedIndex: app.tab,
            onDestinationSelected: app.setTab,
            destinations: [
              for (final (icon, selected, label) in _destinations)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ),
      );
    }

    final extended = size == SizeClass.expanded;
    // phones in landscape: too short for labels + buttons in the rail
    final short = isShort(context);
    return Scaffold(
      floatingActionButton: short
          ? FloatingActionButton(
              tooltip: 'Nova despesa', onPressed: () => openNova(context), child: const Icon(Icons.add))
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
                      tooltip: 'Nova despesa',
                      onPressed: () => openNova(context),
                      shape: const StadiumBorder(),
                      icon: const Icon(Icons.add),
                      label: const Text('Nova despesa', style: TextStyle(fontWeight: FontWeight.w600)),
                    )
                  : FloatingActionButton(
                      tooltip: 'Nova despesa', onPressed: () => openNova(context), child: const Icon(Icons.add)),
            ),
            trailing: short ? null : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: IconButton(
                tooltip: 'Ajustes',
                color: Palette.muted,
                icon: const Icon(Icons.tune),
                onPressed: () => openAjustes(context),
              ),
            ),
            destinations: [
              for (final (icon, selected, label) in _destinations)
                NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Palette.line),
          Expanded(child: page),
        ]),
      ),
    );
  }
}
