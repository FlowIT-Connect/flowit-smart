import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
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

    final f = context.flow;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final form = AutofillGroup(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[
              const Center(child: FlowLogo(size: 72)),
              const SizedBox(height: 18),
              Text('FlowIT Smart', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(context.tr('app.tagline'), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
              const SizedBox(height: 28),
            ],
            if (state.backend.isDemo) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: f.brandSoft, borderRadius: BorderRadius.circular(18)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.science_rounded, size: 20, color: f.brandInk),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.tr('demo.banner'), style: TextStyle(color: f.brandInk, fontWeight: FontWeight.w600, height: 1.4))),
                ]),
              ),
              const SizedBox(height: 20),
            ],
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 18),
            if (_mode == _Mode.signUp) ...[
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: context.tr('auth.displayName'), prefixIcon: const Icon(Icons.person_rounded)),
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty ? context.tr('validation.required') : null,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _email,
              decoration: InputDecoration(labelText: context.tr('auth.email'), prefixIcon: const Icon(Icons.alternate_email_rounded)),
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
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    tooltip: context.tr(_obscure ? 'auth.showPassword' : 'auth.hidePassword'),
                    icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
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
              Text(_info!, style: TextStyle(color: f.brandInk, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(switch (_mode) {
                      _Mode.signIn => context.tr('auth.signInAction'),
                      _Mode.signUp => context.tr('auth.signUpAction'),
                      _Mode.reset => context.tr('auth.resetAction'),
                    }),
            ),
            const SizedBox(height: 10),
            if (_mode == _Mode.signIn) ...[
              TextButton(onPressed: () => setState(() => _mode = _Mode.reset), child: Text(context.tr('auth.forgot'))),
              TextButton(onPressed: () => setState(() => _mode = _Mode.signUp), child: Text(context.tr('auth.noAccount'))),
            ] else
              TextButton(onPressed: () => setState(() => _mode = _Mode.signIn), child: Text(context.tr('auth.haveAccount'))),
          ],
        ),
      ),
    );

    final formPane = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: form),
      ),
    );

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(actions: const [LanguageMenu(), SizedBox(width: 8)]),
        extendBodyBehindAppBar: wide,
        body: SafeArea(
          child: wide
              ? Row(children: [
                  const Expanded(flex: 5, child: Padding(padding: EdgeInsets.all(20), child: _BrandPanel())),
                  Expanded(flex: 4, child: formPane),
                ])
              : formPane,
        ),
      ),
    );
  }
}

/// Panneau de marque (grand écran) : logo, promesse et points forts.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    const white = Colors.white;
    return Container(
      decoration: BoxDecoration(
        gradient: f.brandGradient,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [BoxShadow(color: f.brand.withValues(alpha: .3), blurRadius: 40, offset: const Offset(0, 18))],
      ),
      padding: const EdgeInsets.all(44),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: white.withValues(alpha: .5), width: 1.5)),
            child: const FlowLogo(size: 56),
          ),
          const SizedBox(width: 14),
          Text('FlowIT Smart', style: theme.textTheme.titleLarge?.copyWith(color: white, fontWeight: FontWeight.w800)),
        ]),
        const Spacer(),
        Text(context.tr('auth.hero'), style: theme.textTheme.displaySmall?.copyWith(color: white, fontWeight: FontWeight.w800, height: 1.1)),
        const SizedBox(height: 14),
        Text(context.tr('app.tagline'), style: theme.textTheme.titleMedium?.copyWith(color: white.withValues(alpha: .85))),
        const SizedBox(height: 32),
        for (final (icon, key) in const [
          (Icons.bolt_rounded, 'auth.feature1'),
          (Icons.auto_awesome_rounded, 'auth.feature2'),
          (Icons.shield_rounded, 'auth.feature3'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: white.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(context.tr(key), style: theme.textTheme.bodyLarge?.copyWith(color: white, fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
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
