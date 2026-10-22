import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../widgets.dart';
import 'fixas.dart';
import 'previsao.dart';

/// Forecast and fixed bills under one tab: both describe what is coming.
class PlanoScreen extends StatelessWidget {
  const PlanoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.s;
    final switcher = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        PillChip(label: s.navForecast, selected: app.planView == 0, onTap: () => app.setPlanView(0)),
        const SizedBox(width: 8),
        PillChip(label: s.navBills, selected: app.planView == 1, onTap: () => app.setPlanView(1)),
      ]),
    );
    return app.planView == 0 ? PrevisaoScreen(header: switcher) : FixasScreen(header: switcher);
  }
}
