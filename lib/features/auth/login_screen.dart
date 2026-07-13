import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';
import 'widgets/auth_ui.dart';

/// Vertical rhythm for the sign-in card, on an 8dp grid so spacing stays
/// consistent and easy to reason about.
class _Gap {
  _Gap._();
  static const afterLogo = 28.0;
  static const label = 10.0; // between overline / heading / subtitle
  static const beforeForm = 28.0;
  static const betweenFields = 14.0;
  static const beforeActions = 20.0;
  static const beforeButton = 22.0;
  static const beforeFooter = 12.0;
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _remember = false;
  Map<String, String> _fieldErrors = {};

  /// Drives the staggered fade-and-rise entrance of the card's contents.
  late final AnimationController _entrance;

  /// SharedPreferences key for the remembered (lowercase) username.
  static const _kRememberedUser = 'remembered_username';

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _loadRemembered();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Prefill and tick "Remember me" if a username was saved on a prior sign-in.
  /// Stored lowercase; shown uppercase to match the in-field formatting.
  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kRememberedUser);
    if (!mounted || saved == null || saved.trim().isEmpty) return;
    setState(() {
      _username.text = saved.trim().toUpperCase();
      _remember = true;
    });
  }

  /// Persist (or clear) the remembered username per the checkbox state. The
  /// password is never stored.
  Future<void> _persistRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    if (_remember) {
      await prefs.setString(
        _kRememberedUser,
        _username.text.trim().toLowerCase(),
      );
    } else {
      await prefs.remove(_kRememberedUser);
    }
  }

  /// Surface a login failure as an error SnackBar rather than an inline banner.
  void _showError(String message) {
    AppSnack.error(context, message);
  }

  Future<void> _submit() async {
    setState(() => _fieldErrors = {});
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
      // Remember the username only once the credentials are known good.
      await _persistRemembered();
      // Router redirect handles navigation on auth state change.
    } on ApiException catch (e) {
      setState(() => _fieldErrors = e.fields);
      if (e.fields.isEmpty && mounted) _showError(e.message);
    } catch (_) {
      if (mounted) _showError('Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgotPassword() => context.push(Routes.forgotPassword);

  @override
  Widget build(BuildContext context) {
    // Wrap each row in a staggered entrance; `order` yields the cascade.
    var order = 0;
    Widget stagger(Widget child) =>
        AuthFadeSlideIn(controller: _entrance, order: order++, child: child);

    return Scaffold(
      body: AuthUi.canvas(
        context,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: AuthUi.glassCard(
                  context,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        stagger(
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SvgPicture.asset(
                              Assets.zebuLogo,
                              height: 38,
                            ),
                          ),
                        ),
                        const SizedBox(height: _Gap.afterLogo),
                        stagger(AuthUi.overline(context, 'Staff portal')),
                        const SizedBox(height: _Gap.label),
                        stagger(AuthUi.heading(context, 'Welcome back')),
                        const SizedBox(height: _Gap.label),
                        stagger(
                          AuthUi.subtitle(
                            context,
                            'Sign in to continue to your helpdesk',
                          ),
                        ),
                        const SizedBox(height: _Gap.beforeForm),
                        stagger(
                          TextFormField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [UpperCaseTextFormatter()],
                            style: const TextStyle(letterSpacing: 0.4),
                            decoration: AuthUi.fieldDecoration(
                              context,
                              label: 'Email or username',
                              icon: Icons.person_outline,
                              error: _fieldErrors['username'],
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const SizedBox(height: _Gap.betweenFields),
                        stagger(
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: AuthUi.fieldDecoration(
                              context,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              error: _fieldErrors['passwd'],
                              suffix: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  !_obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                color: AuthUi.mutedIconColor(context),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                        const SizedBox(height: _Gap.beforeActions),
                        stagger(
                          Row(
                            children: [
                              AuthUi.rememberMe(
                                context,
                                value: _remember,
                                onChanged: (v) {
                                  if (!_busy) setState(() => _remember = v);
                                },
                              ),
                              const Spacer(),
                              AuthUi.link(
                                context,
                                label: 'Forgot password?',
                                onPressed: _busy ? null : _forgotPassword,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: _Gap.beforeButton),
                        stagger(
                          AuthUi.primaryButton(
                            context,
                            label: 'Sign in',
                            icon: Icons.arrow_forward,
                            busy: _busy,
                            onPressed: _submit,
                          ),
                        ),
                        const SizedBox(height: _Gap.beforeFooter),
                        stagger(
                          AppText.paraText(
                            context,
                            'Trouble signing in? Contact your administrator.',
                            align: TextAlign.center,
                            color: AuthUi.subtitleColor(context),
                          ),
                        ),
                      ],
                    ),
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
