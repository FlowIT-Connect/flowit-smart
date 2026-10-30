import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/plan_card.dart';
import 'admin_payments_screen.dart';
import 'onboarding_screen.dart';

/// Paramètres : compte, langue, maison, membres, intégrations, journal.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final home = state.home;
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    final f = context.flow;
    final theme = Theme.of(context);
    final email = state.backend.currentEmail ?? '—';

    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      // Carte de profil.
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: f.brandGradient, shape: BoxShape.circle),
                child: Text(
                  email.isEmpty || email == '—' ? '?' : email.characters.first.toUpperCase(),
                  style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(email, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  if (home != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.tr('settings.roleIn', {'role': context.tr('role.${state.role.name}'), 'home': home.name}),
                      style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
      SettingsGroup(title: context.tr('settings.appearance'), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.instance,
            builder: (context, mode, _) => SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded), label: Text(context.tr('theme.system'))),
                  ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded), label: Text(context.tr('theme.light'))),
                  ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded), label: Text(context.tr('theme.dark'))),
                ],
                selected: {mode},
                onSelectionChanged: (s) => ThemeController.instance.set(s.first),
              ),
            ),
          ),
        ),
        ListTile(
          leading: TileIcon(Icons.translate_rounded, color: f.blue),
          title: Text(context.tr('settings.language')),
          trailing: DropdownButton<String>(
            value: state.locale.languageCode,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(16),
            items: [for (final l in L10n.supported) DropdownMenuItem(value: l.languageCode, child: Text(L10n.languageName(l.languageCode)))],
            onChanged: (v) => v == null ? null : state.setLocale(Locale(v)),
          ),
        ),
      ]),
      SettingsGroup(title: context.tr('settings.account'), children: [
        if (state.myInvitations.isNotEmpty)
          ListTile(
            leading: TileIcon(Icons.mail_rounded, color: f.pink),
            title: Text(context.tr('invitations.received')),
            trailing: Badge(label: Text('${state.myInvitations.length}')),
            onTap: () => push(const _ReceivedInvitationsPage()),
          ),
        ListTile(
          leading: TileIcon(Icons.vpn_key_rounded, color: f.amber),
          title: Text(context.tr('invitations.haveCode')),
          trailing: const ForwardChevron(),
          onTap: () async {
            final token = await promptText(context, title: context.tr('invitations.join'), label: context.tr('invitations.code'));
            if (token != null && context.mounted) await acceptInvitationFlow(context, token);
          },
        ),
      ]),
      if (home != null && state.plan != null) const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: PlanCard()),
      if (home != null)
        SettingsGroup(title: context.tr('settings.home'), children: [
          ListTile(
            leading: const TileIcon(Icons.home_rounded),
            title: Text(home.name),
            subtitle: Text(home.timezone),
            trailing: state.canManage ? Icon(Icons.edit_rounded, color: f.inkFaint) : null,
            onTap: state.canManage
                ? () async {
                    final name = await promptText(context, title: context.tr('home.rename'), initial: home.name, label: context.tr('home.name'));
                    if (name != null && await state.run(() => state.backend.renameHome(home.id, name))) {
                      await state.loadHomes(select: home.id);
                    }
                  }
                : null,
          ),
          ListTile(
            leading: TileIcon(Icons.group_rounded, color: f.violet),
            title: Text(context.tr('members.title')),
            trailing: const ForwardChevron(),
            onTap: () => push(const MembersPage()),
          ),
          if (state.canManage)
            ListTile(
              leading: TileIcon(Icons.hub_rounded, color: f.cyan),
              title: Text(context.tr('integrations.title')),
              trailing: const ForwardChevron(),
              onTap: () => push(const IntegrationsPage()),
            ),
          ListTile(
            leading: TileIcon(Icons.history_rounded, color: f.orange),
            title: Text(context.tr('events.title')),
            trailing: const ForwardChevron(),
            onTap: () => push(const EventsPage()),
          ),
          if (state.role == HomeRole.owner)
            ListTile(
              leading: TileIcon(Icons.delete_forever_rounded, color: f.danger),
              title: Text(context.tr('home.delete'), style: TextStyle(color: f.danger)),
              onTap: () async {
                final typed = await promptText(context, title: context.tr('home.deleteTitle'), label: context.tr('home.deleteConfirm', {'name': home.name}));
                if (typed != home.name) {
                  if (typed != null) state.notify(state.tr('home.deleteMismatch'), error: true);
                  return;
                }
                if (await state.run(() => state.backend.deleteHome(home.id))) await state.loadHomes();
              },
            ),
        ]),
      if (state.isPlatformAdmin)
        SettingsGroup(title: context.tr('admin.title'), children: [
          ListTile(
            leading: TileIcon(Icons.payments_rounded, color: f.brand),
            title: Text(context.tr('admin.payments')),
            subtitle: Text(context.tr('admin.paymentsHelp')),
            trailing: const ForwardChevron(),
            onTap: () => push(const AdminPaymentsScreen()),
          ),
        ]),
      SettingsGroup(title: context.tr('settings.session'), children: [
        ListTile(leading: TileIcon(Icons.logout_rounded, color: f.inkSoft), title: Text(context.tr('auth.signOut')), onTap: state.signOut),
        ListTile(
          leading: TileIcon(Icons.person_remove_rounded, color: f.danger),
          title: Text(context.tr('account.delete'), style: TextStyle(color: f.danger)),
          subtitle: Text(context.tr('account.deleteHelp')),
          onTap: () async {
            final ok = await confirmDialog(context,
                title: context.tr('account.deleteTitle'), message: context.tr('account.deleteMessage'), destructive: true, confirmLabel: context.tr('account.delete'));
            if (ok) await state.run(state.backend.deleteAccount);
          },
        ),
      ]),
      const SizedBox(height: 12),
      SettingsGroup(children: [
        ListTile(
          leading: const Padding(padding: EdgeInsets.all(2), child: SoleaLogo(size: 30)),
          title: const Text('Solea 1.0.0'),
          subtitle: Text(state.backend.isDemo ? context.tr('demo.about') : context.tr('settings.about')),
          trailing: const ForwardChevron(),
          onTap: () => showLicensePage(context: context, applicationName: 'Solea', applicationVersion: '1.0.0'),
        ),
      ]),
    ]);
  }
}

class _ReceivedInvitationsPage extends StatelessWidget {
  const _ReceivedInvitationsPage();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('invitations.received'))),
      body: ListView(children: [
        for (final inv in state.myInvitations)
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(inv.homeName ?? ''),
            subtitle: Text(context.tr('role.${inv.role.name}')),
            trailing: FilledButton.tonal(
              onPressed: () async {
                await acceptInvitationFlow(context, inv.token);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(context.tr('invitations.accept')),
            ),
          ),
      ]),
    );
  }
}

// ----------------------------------------------------------------------------- Membres
class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  List<Member>? _members;
  List<Invitation> _invitations = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    final homeId = state.home!.id;
    try {
      final members = await state.backend.listMembers(homeId);
      final invitations = state.canManage ? await state.backend.listInvitations(homeId) : const <Invitation>[];
      if (mounted) {
        setState(() {
          _members = members;
          _invitations = invitations;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _invite() async {
    final state = AppScope.read(context);
    final email = TextEditingController();
    var role = HomeRole.member;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(context.tr('members.invite')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: email, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: context.tr('auth.email'))),
            const SizedBox(height: 12),
            DropdownButtonFormField<HomeRole>(
              initialValue: role,
              decoration: InputDecoration(labelText: context.tr('members.role')),
              items: [
                for (final r in [HomeRole.member, HomeRole.admin, HomeRole.installer])
                  if (r != HomeRole.admin || state.role == HomeRole.owner || state.role == HomeRole.admin)
                    DropdownMenuItem(value: r, child: Text(context.tr('role.${r.name}'))),
              ],
              onChanged: (v) => setLocal(() => role = v ?? HomeRole.member),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, email.text.contains('@')), child: Text(context.tr('members.send'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    Invitation? inv;
    if (await state.run(() async => inv = await state.backend.invite(state.home!.id, email.text, role))) {
      await _load();
      if (mounted && inv != null) _showCode(inv!);
    }
  }

  void _showCode(Invitation inv) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('members.invitationCreated')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('members.invitationHelp', {'email': inv.email ?? ''})),
          const SizedBox(height: 12),
          SelectableText(inv.token, style: const TextStyle(fontFamily: 'monospace')),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: inv.token)),
            icon: const Icon(Icons.copy),
            label: Text(context.tr('common.copy')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('common.close'))),
        ],
      ),
    );
  }

  Future<void> _editMember(Member m) async {
    final state = AppScope.read(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(m.displayName, style: Theme.of(context).textTheme.titleMedium), subtitle: Text(context.tr('role.${m.role.name}'))),
          for (final r in [HomeRole.admin, HomeRole.member, HomeRole.installer])
            if (r != m.role)
              ListTile(leading: const Icon(Icons.badge_outlined), title: Text(context.tr('members.makeRole', {'role': context.tr('role.${r.name}')})), onTap: () => Navigator.pop(ctx, 'role:${r.name}')),
          if (m.role == HomeRole.member)
            ListTile(leading: const Icon(Icons.devices_other_outlined), title: Text(context.tr('members.restrict')), onTap: () => Navigator.pop(ctx, 'devices')),
          if (state.role == HomeRole.owner)
            ListTile(leading: const Icon(Icons.swap_horiz), title: Text(context.tr('members.transfer')), onTap: () => Navigator.pop(ctx, 'transfer')),
          ListTile(
            leading: Icon(Icons.person_remove_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(context.tr('members.revoke'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final homeId = state.home!.id;
    if (action.startsWith('role:')) {
      await state.run(() => state.backend.updateMember(homeId, m.userId, role: homeRoleFrom(action.substring(5))));
    } else if (action == 'devices') {
      final selected = await _pickDevices(m);
      if (selected == null) return;
      final all = selected.length == state.devices.length;
      await state.run(() => state.backend.updateMember(homeId, m.userId, allowedDevices: all ? null : selected, clearRestriction: all));
    } else if (action == 'transfer') {
      if (!await confirmDialog(context, title: context.tr('members.transfer'), message: context.tr('members.transferMessage', {'name': m.displayName}), destructive: true)) return;
      if (await state.run(() => state.backend.transferOwnership(homeId, m.userId))) await state.loadHomes(select: homeId);
    } else if (action == 'remove') {
      if (!mounted) return;
      if (!await confirmDialog(context, title: context.tr('members.revoke'), message: context.tr('members.revokeMessage', {'name': m.displayName}), destructive: true)) return;
      await state.run(() => state.backend.removeMember(homeId, m.userId));
    }
    await _load();
  }

  Future<List<String>?> _pickDevices(Member m) {
    final state = AppScope.read(context);
    final selected = <String>{...m.allowedDevices ?? state.devices.keys};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(context.tr('members.restrict')),
          content: SizedBox(
            width: 360,
            child: ListView(shrinkWrap: true, children: [
              for (final d in state.devices.values)
                CheckboxListTile(
                  value: selected.contains(d.id),
                  title: Text(d.name),
                  onChanged: (v) => setLocal(() => v == true ? selected.add(d.id) : selected.remove(d.id)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected.toList()), child: Text(context.tr('common.save'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final members = _members;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('members.title'))),
      floatingActionButton: state.canManage
          ? FloatingActionButton.extended(onPressed: _invite, icon: const Icon(Icons.person_add_alt), label: Text(context.tr('members.invite')))
          : null,
      body: _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : members == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                    for (final m in members)
                      ListTile(
                        leading: CircleAvatar(child: Text(m.displayName.isEmpty ? '?' : m.displayName.characters.first.toUpperCase())),
                        title: Text(m.userId == state.backend.currentUserId ? '${m.displayName} (${context.tr('members.you')})' : m.displayName),
                        subtitle: Text([
                          context.tr('role.${m.role.name}'),
                          if (m.allowedDevices != null) context.tr('members.limited', {'n': m.allowedDevices!.length}),
                          if (m.expiresAt != null) context.tr('members.until', {'date': MaterialLocalizations.of(context).formatShortDate(m.expiresAt!)}),
                        ].join(' · ')),
                        trailing: state.canManage && m.role != HomeRole.owner && m.userId != state.backend.currentUserId ? const Icon(Icons.more_vert) : null,
                        onTap: state.canManage && m.role != HomeRole.owner && m.userId != state.backend.currentUserId ? () => _editMember(m) : null,
                      ),
                    if (_invitations.isNotEmpty) ...[
                      SectionHeader(context.tr('members.pending')),
                      for (final inv in _invitations)
                        ListTile(
                          leading: const Icon(Icons.schedule_send_outlined),
                          title: Text(inv.email ?? ''),
                          subtitle: Text('${context.tr('role.${inv.role.name}')} · ${context.tr('members.expires', {'date': MaterialLocalizations.of(context).formatShortDate(inv.expiresAt)})}'),
                          onTap: () => _showCode(inv),
                          trailing: IconButton(
                            tooltip: context.tr('members.cancelInvite'),
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              await state.run(() => state.backend.revokeInvitation(inv.id));
                              await _load();
                            },
                          ),
                        ),
                    ],
                  ]),
                ),
    );
  }
}

// ----------------------------------------------------------------------------- Intégrations
class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  List<Integration>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    try {
      final items = await state.backend.listIntegrations(state.home!.id);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _add() async {
    final state = AppScope.read(context);
    var provider = 'home_assistant';
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(context.tr('integrations.add')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: provider,
              decoration: InputDecoration(labelText: context.tr('integrations.provider')),
              items: [
                for (final p in const ['home_assistant', 'zigbee2mqtt', 'tuya', 'mqtt', 'ble', 'other'])
                  DropdownMenuItem(value: p, child: Text(context.tr('provider.$p'))),
              ],
              onChanged: (v) => setLocal(() => provider = v ?? provider),
            ),
            const SizedBox(height: 12),
            TextField(controller: label, decoration: InputDecoration(labelText: context.tr('integrations.label'))),
            const SizedBox(height: 12),
            Text(context.tr('integrations.secretNotice'), style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('common.create'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    String? id;
    if (await state.run(() async => id = await state.backend.createIntegration(state.home!.id, provider, label.text))) {
      await _load();
      if (mounted && id != null) _showBridgeConfig(id!);
    }
  }

  void _showBridgeConfig(String integrationId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('integrations.bridgeTitle')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('integrations.bridgeHelp')),
          const SizedBox(height: 12),
          SelectableText('INTEGRATION_ID=$integrationId', style: const TextStyle(fontFamily: 'monospace')),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: integrationId)),
            icon: const Icon(Icons.copy),
            label: Text(context.tr('common.copy')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('common.close'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('integrations.title'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: Text(context.tr('integrations.add'))),
      body: _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? EmptyState(icon: Icons.hub_outlined, title: context.tr('integrations.emptyTitle'), message: context.tr('integrations.emptyHelp'))
                  : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                      for (final i in items)
                        ListTile(
                          leading: Icon(switch (i.status) {
                            'connected' => Icons.check_circle,
                            'error' => Icons.error,
                            'disabled' => Icons.pause_circle,
                            _ => Icons.hourglass_top,
                          }, color: switch (i.status) {
                            'connected' => context.flow.success,
                            'error' => scheme.error,
                            _ => scheme.outline,
                          }),
                          title: Text(i.label ?? context.tr('provider.${i.provider}')),
                          subtitle: Text([
                            context.tr('provider.${i.provider}'),
                            context.tr('integrations.status.${i.status}'),
                            if (i.lastSyncAt != null) context.tr('integrations.synced', {'when': relativeTime(context, i.lastSyncAt)}),
                            if (i.lastError != null) i.lastError!,
                          ].join(' · ')),
                          onTap: () => _showBridgeConfig(i.id),
                          trailing: Switch(
                            value: i.status != 'disabled',
                            onChanged: (v) async {
                              await state.run(() => state.backend.setIntegrationEnabled(i.id, v));
                              await _load();
                            },
                          ),
                        ),
                    ]),
    );
  }
}

// ----------------------------------------------------------------------------- Journal
class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  List<EventLog>? _events;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    try {
      final items = await state.backend.listEvents(state.home!.id, limit: 200);
      if (mounted) setState(() => _events = items);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final events = _events;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('events.title')), actions: [IconButton(tooltip: context.tr('common.refresh'), onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : events == null
              ? const Center(child: CircularProgressIndicator())
              : events.isEmpty
                  ? EmptyState(icon: Icons.history, title: context.tr('events.empty'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (context, i) {
                          final e = events[i];
                          final failed = e.eventType == 'command_failed' || e.eventType == 'device_unavailable' || e.result == 'failed';
                          final device = state.devices[e.deviceId]?.name;
                          final detail = [
                            ?device,
                            if (e.result != null) context.tryTr('events.result.${e.result}') ?? e.result!,
                            if (e.details['error'] != null) '${e.details['error']}',
                            if (e.details['name'] != null) '${e.details['name']}',
                          ].join(' · ');
                          return ListTile(
                            dense: true,
                            leading: Icon(switch (e.eventType) {
                              'command' => Icons.send_outlined,
                              'command_failed' => Icons.error_outline,
                              'device_unavailable' => Icons.link_off,
                              'device_available' => Icons.link,
                              'member_changed' => Icons.group_outlined,
                              'scene_started' || 'scene_finished' => Icons.auto_awesome_outlined,
                              _ => Icons.tune,
                            }, color: failed ? scheme.error : null),
                            title: Text(context.tryTr('events.type.${e.eventType}') ?? e.eventType),
                            subtitle: detail.isEmpty ? null : Text(detail),
                            trailing: Text(
                              '${MaterialLocalizations.of(context).formatShortDate(e.createdAt)}\n${timeOfDay(context, e.createdAt)}',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
