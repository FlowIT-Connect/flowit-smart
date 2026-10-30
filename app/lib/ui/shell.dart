import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
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
    (Icons.home_outlined, Icons.home_rounded),
    (Icons.meeting_room_outlined, Icons.meeting_room_rounded),
    (Icons.lightbulb_outline_rounded, Icons.lightbulb_rounded),
    (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
    (Icons.schedule_outlined, Icons.schedule_rounded),
    (Icons.settings_outlined, Icons.settings_rounded),
  ];
  static const _labels = ['nav.home', 'nav.rooms', 'nav.devices', 'nav.scenes', 'nav.automations', 'nav.settings'];

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
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
                    child: ContentWidth(child: IndexedStack(index: _index, children: pages)),
                  ),
      ),
    ]);

    final appBar = AppBar(
      toolbarHeight: 76,
      titleSpacing: wide ? 28 : 16,
      leadingWidth: 64,
      leading: wide ? null : const Padding(padding: EdgeInsetsDirectional.only(start: 16), child: Center(child: SoleaLogo(size: 38))),
      title: _index == 0
          ? const HomeSwitcher(large: true)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const HomeSwitcher(),
              Text(context.tr(_labels[_index]), style: Theme.of(context).textTheme.headlineSmall),
            ]),
      actions: [
        if (state.backend.isDemo)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: f.brandSoft, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.science_rounded, size: 15, color: f.brandInk),
                const SizedBox(width: 6),
                Text(context.tr('demo.chip'), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: f.brandInk, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
      ],
    );

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: wide
            ? Row(children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 0, 16),
                  child: GlassPanel(
                    child: NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: go,
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(padding: EdgeInsets.only(top: 12, bottom: 20), child: SoleaLogo(size: 46)),
                      destinations: [
                        for (var i = 0; i < _labels.length; i++)
                          NavigationRailDestination(icon: Icon(_icons[i].$1), selectedIcon: Icon(_icons[i].$2), label: Text(context.tr(_labels[i]))),
                      ],
                    ),
                  ),
                ),
                Expanded(child: body),
              ])
            : body,
        bottomNavigationBar: wide
            ? null
            // Barre du bas flottante en verre dépoli.
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: GlassPanel(
                  radius: 32,
                  child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: go,
                  labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
                  destinations: [
                    for (var i = 0; i < _labels.length; i++)
                      NavigationDestination(
                        icon: Icon(_icons[i].$1),
                        selectedIcon: Icon(_icons[i].$2),
                        // Libellé court sous l'icône, nom complet dans l'infobulle.
                        label: context.tr(i == 4 ? 'nav.automationsShort' : _labels[i]),
                        tooltip: context.tr(_labels[i]),
                      ),
                  ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Sélecteur de maison dans la barre d'application.
class HomeSwitcher extends StatelessWidget {
  const HomeSwitcher({super.key, this.large = false});

  /// Grand titre (accueil) plutôt que libellé discret au-dessus du titre de page.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final theme = Theme.of(context);
    final style = large
        ? theme.textTheme.headlineSmall
        : theme.textTheme.labelLarge?.copyWith(color: f.inkSoft, fontWeight: FontWeight.w700);
    return PopupMenuButton<String>(
      tooltip: context.tr('home.switch'),
      position: PopupMenuPosition.under,
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
        PopupMenuItem(value: '+', child: ListTile(leading: const Icon(Icons.add_home_rounded), title: Text(context.tr('home.create')))),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(state.home?.name ?? 'Solea', overflow: TextOverflow.ellipsis, style: style)),
        const SizedBox(width: 2),
        Icon(Icons.keyboard_arrow_down_rounded, size: large ? 26 : 18, color: large ? f.ink : f.inkSoft),
      ]),
    );
  }
}
