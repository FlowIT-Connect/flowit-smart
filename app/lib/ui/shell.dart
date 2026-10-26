import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../state/app_state.dart';
import 'screens/automations_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/rooms_screen.dart';
import 'screens/scenes_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/common.dart';

/// Navigation principale (§5.11) : Accueil, Pièces, Appareils, Scènes,
/// Automatisations, Paramètres. Barre du bas sur mobile, rail sur grand écran.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _icons = [
    (Icons.home_outlined, Icons.home),
    (Icons.meeting_room_outlined, Icons.meeting_room),
    (Icons.devices_other_outlined, Icons.devices_other),
    (Icons.auto_awesome_outlined, Icons.auto_awesome),
    (Icons.schedule_outlined, Icons.schedule),
    (Icons.settings_outlined, Icons.settings),
  ];
  static const _labels = ['nav.home', 'nav.rooms', 'nav.devices', 'nav.scenes', 'nav.automations', 'nav.settings'];

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final pages = <Widget>[
      DashboardScreen(onNavigate: go),
      const RoomsScreen(),
      const DevicesScreen(),
      const ScenesScreen(),
      const AutomationsScreen(),
      const SettingsScreen(),
    ];

    final body = Column(children: [
      const ConnectionBanner(),
      Expanded(
        child: state.loadError != null && state.devices.isEmpty
            ? ErrorState(message: state.loadError!, onRetry: state.refreshHome)
            : (state.loading && state.devices.isEmpty && state.rooms.isEmpty)
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: state.refreshHome,
                    child: IndexedStack(index: _index, children: pages),
                  ),
      ),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: const HomeSwitcher(),
        actions: [
          if (state.backend.isDemo)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Chip(label: Text(context.tr('demo.chip')), visualDensity: VisualDensity.compact),
            ),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: go,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (var i = 0; i < _labels.length; i++)
                    NavigationRailDestination(icon: Icon(_icons[i].$1), selectedIcon: Icon(_icons[i].$2), label: Text(context.tr(_labels[i]))),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: go,
              labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: [
                for (var i = 0; i < _labels.length; i++)
                  NavigationDestination(icon: Icon(_icons[i].$1), selectedIcon: Icon(_icons[i].$2), label: context.tr(_labels[i])),
              ],
            ),
    );
  }
}

/// Sélecteur de maison dans la barre d'application.
class HomeSwitcher extends StatelessWidget {
  const HomeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopupMenuButton<String>(
      tooltip: context.tr('home.switch'),
      onSelected: (id) {
        if (id == '+') {
          createHomeFlow(context);
        } else {
          state.selectHome(state.homes.firstWhere((h) => h.id == id));
        }
      },
      itemBuilder: (_) => [
        for (final h in state.homes)
          CheckedPopupMenuItem(value: h.id, checked: h.id == state.home?.id, child: Text(h.name)),
        const PopupMenuDivider(),
        PopupMenuItem(value: '+', child: ListTile(leading: const Icon(Icons.add_home_outlined), title: Text(context.tr('home.create')))),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(state.home?.name ?? 'FlowIT Smart', overflow: TextOverflow.ellipsis)),
        const Icon(Icons.arrow_drop_down),
      ]),
    );
  }
}
