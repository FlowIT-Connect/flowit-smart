import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../state/app_state.dart';
import '../widgets/language_menu.dart';

enum _Mode { signIn, signUp, reset }

/// Connexion, inscription et récupération de compte (§5.1).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _info;

  @override
  void initState() {
    super.initState();
    if (AppScope.read(context).backend.isDemo) {
      _email.text = 'demo@flowit.dz';
      _password.text = 'demo';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final state = AppScope.read(context);
    setState(() {
      _busy = true;
      _info = null;
    });
    final b = state.backend;
    final ok = await state.run(() => switch (_mode) {
          _Mode.signIn => b.signIn(_email.text, _password.text),
          _Mode.signUp => b.signUp(_email.text, _password.text, _name.text),
          _Mode.reset => b.resetPassword(_email.text),
        });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok && _mode == _Mode.reset) _info = context.tr('auth.resetSent');
      if (ok && _mode == _Mode.signUp && b.currentUserId == null) _info = context.tr('auth.checkEmail');
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final title = switch (_mode) {
      _Mode.signIn => context.tr('auth.signIn'),
      _Mode.signUp => context.tr('auth.signUp'),
      _Mode.reset => context.tr('auth.reset'),
    };

    return Scaffold(
      appBar: AppBar(actions: const [LanguageMenu()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.home_work_outlined, size: 56, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('FlowIT Smart', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Text(context.tr('app.tagline'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 24),
                      if (state.backend.isDemo)
                        Card(
                          color: theme.colorScheme.tertiaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(context.tr('demo.banner'), style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      if (_mode == _Mode.signUp) ...[
                        TextFormField(
                          controller: _name,
                          decoration: InputDecoration(labelText: context.tr('auth.displayName')),
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v ?? '').trim().isEmpty ? context.tr('validation.required') : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        decoration: InputDecoration(labelText: context.tr('auth.email')),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: _mode == _Mode.reset ? TextInputAction.done : TextInputAction.next,
                        validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : context.tr('validation.email'),
                        onFieldSubmitted: _mode == _Mode.reset ? (_) => _submit() : null,
                      ),
                      if (_mode != _Mode.reset) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: context.tr('auth.password'),
                            suffixIcon: IconButton(
                              tooltip: context.tr(_obscure ? 'auth.showPassword' : 'auth.hidePassword'),
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          autofillHints: [_mode == _Mode.signUp ? AutofillHints.newPassword : AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) {
                            if ((v ?? '').isEmpty) return context.tr('validation.required');
                            if (_mode == _Mode.signUp && v!.length < 8) return context.tr('validation.password');
                            return null;
                          },
                        ),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: 12),
                        Text(_info!, style: TextStyle(color: theme.colorScheme.primary)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(switch (_mode) {
                                _Mode.signIn => context.tr('auth.signInAction'),
                                _Mode.signUp => context.tr('auth.signUpAction'),
                                _Mode.reset => context.tr('auth.resetAction'),
                              }),
                      ),
                      const SizedBox(height: 8),
                      if (_mode == _Mode.signIn) ...[
                        TextButton(onPressed: () => setState(() => _mode = _Mode.reset), child: Text(context.tr('auth.forgot'))),
                        TextButton(onPressed: () => setState(() => _mode = _Mode.signUp), child: Text(context.tr('auth.noAccount'))),
                      ] else
                        TextButton(onPressed: () => setState(() => _mode = _Mode.signIn), child: Text(context.tr('auth.haveAccount'))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Saisie du nouveau mot de passe après un lien de récupération.
Future<void> showNewPasswordDialog(BuildContext context) async {
  final state = AppScope.read(context);
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(context.tr('auth.newPassword')),
      content: TextField(controller: controller, obscureText: true, autofocus: true, decoration: InputDecoration(labelText: context.tr('auth.password'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.length >= 8), child: Text(context.tr('common.save'))),
      ],
    ),
  );
  state.passwordRecovery = false;
  if (ok == true) {
    await state.run(() => state.backend.updatePassword(controller.text), success: state.tr('auth.passwordUpdated'));
  }
}
