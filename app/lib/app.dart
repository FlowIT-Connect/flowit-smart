import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/l10n.dart';
import 'core/theme.dart';
import 'state/app_state.dart';
import 'ui/screens/auth_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/shell.dart';

class FlowItApp extends StatefulWidget {
  const FlowItApp({super.key, required this.state});

  final AppState state;

  @override
  State<FlowItApp> createState() => _FlowItAppState();
}

class _FlowItAppState extends State<FlowItApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  late final StreamSubscription<Notice> _noticeSub;

  @override
  void initState() {
    super.initState();
    _noticeSub = widget.state.notices.listen((n) {
      final messenger = _messenger.currentState;
      if (messenger == null) return;
      final scheme = Theme.of(_navigator.currentContext ?? context).colorScheme;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(n.message, style: n.isError ? TextStyle(color: scheme.onErrorContainer) : null),
          backgroundColor: n.isError ? scheme.errorContainer : null,
          duration: Duration(seconds: n.isError ? 5 : 3),
        ));
    });
    widget.state.addListener(_onState);
  }

  void _onState() {
    if (widget.state.passwordRecovery && _navigator.currentContext != null) {
      widget.state.passwordRecovery = false;
      showNewPasswordDialog(_navigator.currentContext!);
    }
  }

  @override
  void dispose() {
    _noticeSub.cancel();
    widget.state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: Builder(builder: (context) {
        final state = AppScope.of(context);
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.instance,
          builder: (context, mode, _) => MaterialApp(
          title: 'FlowIT Smart',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigator,
          scaffoldMessengerKey: _messenger,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          locale: state.locale,
          supportedLocales: L10n.supported,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // La direction (RTL pour l'arabe) est fournie par GlobalWidgetsLocalizations.
          home: !state.signedIn
              ? const AuthScreen()
              : (state.home == null ? const OnboardingScreen() : const Shell()),
          ),
        );
      }),
    );
  }
}
