import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/profile.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Sign in / sign up / guest (FR-AU-02..06). Passwords are validated but
/// never stored (FR-AU-07). Cloud accounts use Firebase Authentication once
/// the project's google-services.json is added (see README).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with SingleTickerProviderStateMixin {
  bool _signUp = true;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _shake.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final err = (_signUp ? Validators.name(_name.text) : null) ??
        Validators.email(_email.text) ??
        Validators.password(_password.text);
    if (err != null) {
      setState(() => _error = err);
      _shake.forward(from: 0);
      HapticFeedback.lightImpact();
      return;
    }
    final name = _signUp ? _name.text.trim() : _email.text.trim().split('@').first;
    ref.read(appProvider).signIn(name: name, email: _email.text.trim(), guest: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 20),
            const FormFlowLogo(size: 34),
            const SizedBox(height: 8),
            Text(_signUp ? 'Create your account' : 'Welcome back',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Sign up')),
                ButtonSegment(value: false, label: Text('Log in')),
              ],
              selected: {_signUp},
              onSelectionChanged: (s) => setState(() {
                _signUp = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) =>
                  Transform.translate(offset: Offset(math.sin(_shake.value * math.pi * 6) * 10 * (1 - _shake.value), 0), child: child),
              child: Column(children: [
                if (_signUp) ...[
                  TextField(
                    key: const Key('auth_name'),
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  key: const Key('auth_email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('auth_password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (6+ characters)', prefixIcon: Icon(Icons.lock_outline)),
                ),
              ]),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: FF.bad, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_error!, style: const TextStyle(color: FF.bad))),
                ]),
              ),
            const SizedBox(height: 20),
            FilledButton(key: const Key('auth_submit'), onPressed: _submit, child: Text(_signUp ? 'Create account' : 'Log in')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('auth_guest'),
              onPressed: () => ref.read(appProvider).signIn(name: 'Guest', email: '', guest: true),
              icon: const Icon(Icons.person_off_outlined),
              label: const Text('Continue as guest'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Guest data stays on this phone and can be attached to an account later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: FF.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
