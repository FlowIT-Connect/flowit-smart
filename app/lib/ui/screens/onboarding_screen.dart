import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/language_menu.dart';

/// Aucune maison : créer la première ou rejoindre une maison existante.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlowIT Smart'),
        actions: [
          const LanguageMenu(),
          IconButton(tooltip: context.tr('auth.signOut'), onPressed: state.signOut, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : state.loadError != null
                  ? ErrorState(message: state.loadError!, onRetry: state.loadHomes)
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        EmptyState(
                          icon: Icons.add_home_outlined,
                          title: context.tr('onboarding.title'),
                          message: context.tr('onboarding.message'),
                          action: FilledButton.icon(
                            onPressed: () => createHomeFlow(context),
                            icon: const Icon(Icons.add),
                            label: Text(context.tr('home.create')),
                          ),
                        ),
                        if (state.myInvitations.isNotEmpty) ...[
                          SectionHeader(context.tr('invitations.received')),
                          for (final inv in state.myInvitations)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.mail_outline),
                                title: Text(inv.homeName ?? ''),
                                subtitle: Text(context.tr('role.${inv.role.name}')),
                                trailing: FilledButton.tonal(
                                  onPressed: () => acceptInvitationFlow(context, inv.token),
                                  child: Text(context.tr('invitations.accept')),
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: () async {
                              final token = await promptText(context, title: context.tr('invitations.join'), label: context.tr('invitations.code'));
                              if (token != null && context.mounted) await acceptInvitationFlow(context, token);
                            },
                            icon: const Icon(Icons.vpn_key_outlined),
                            label: Text(context.tr('invitations.haveCode')),
                          ),
                        ),
                      ],
                    ),
        ),
      ]),
    );
  }
}

Future<void> createHomeFlow(BuildContext context) async {
  final state = AppScope.read(context);
  final name = await promptText(context, title: context.tr('home.create'), label: context.tr('home.name'), hint: context.tr('home.nameHint'));
  if (name == null) return;
  String? id;
  final ok = await state.run(() async => id = (await state.backend.createHome(name, 'Africa/Algiers')).id);
  if (ok) await state.loadHomes(select: id);
}

Future<void> acceptInvitationFlow(BuildContext context, String token) async {
  final state = AppScope.read(context);
  String? homeId;
  final ok = await state.run(() async => homeId = await state.backend.acceptInvitation(token), success: state.tr('invitations.accepted'));
  if (ok) await state.loadHomes(select: homeId);
}
