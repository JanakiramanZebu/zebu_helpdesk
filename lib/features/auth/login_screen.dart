import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/theme/app_theme.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _fieldErrors = {};
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            // Shown uppercase, but the backend treats usernames/emails as
            // case-insensitive, so submit the canonical lowercase form.
            username: _username.text.trim().toLowerCase(),
            password: _password.text,
          );
      // Router redirect handles navigation on auth state change.
    } on ApiException catch (e) {
      setState(() {
        _fieldErrors = e.fields;
        _error = e.fields.isEmpty ? e.message : null;
      });
    } catch (_) {
      setState(() => _error = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgotPassword() {
    showAppMessageDialog(
      context,
      title: 'Forgot password?',
      message:
          'Helpdesk password resets are handled by your administrator. '
          'Please reach out to your team admin to reset your password.',
    );
  }

  /// Clean underline-style field used by the login form (overrides the global
  /// filled-pill input theme for a lighter sign-in look).
  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    Widget? suffix,
    String? error,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      filled: false,
      suffixIcon: suffix,
      errorText: error,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.brand, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SvgPicture.asset(Assets.zebuLogo, height: 54),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      'Sign in to Helpdesk',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use your Zebu staff credentials',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_error != null) _ErrorBanner(message: _error!),
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                      style: const TextStyle(letterSpacing: 0.4),
                      decoration: _fieldDecoration(
                        context,
                        label: 'Username / Email',
                        error: _fieldErrors['username'],
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: _fieldDecoration(
                        context,
                        label: 'Password',
                        error: _fieldErrors['passwd'],
                        suffix: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          color: theme.colorScheme.onSurfaceVariant,
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Login'),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Forces the visible username text to uppercase while typing. The value is
/// lowercased again at submit time (helpdesk logins are case-insensitive).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
