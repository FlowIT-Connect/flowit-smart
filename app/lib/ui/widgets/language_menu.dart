import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../state/app_state.dart';

/// Choix de langue : français, anglais, arabe (RTL).
class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopupMenuButton<String>(
      tooltip: context.tr('settings.language'),
      icon: const Icon(Icons.translate),
      initialValue: state.locale.languageCode,
      onSelected: (code) => state.setLocale(Locale(code)),
      itemBuilder: (_) => [
        for (final l in L10n.supported)
          PopupMenuItem(value: l.languageCode, child: Text(L10n.languageName(l.languageCode))),
      ],
    );
  }
}
