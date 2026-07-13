import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';
import 'widgets/auth_ui.dart';

/// The stages of the forgot-password flow.
enum _Stage {
  /// Enter a username/email to request a reset email.
  request,

  /// The email has been sent; offer to enter the reset code.
  emailSent,

  /// Enter the emailed token + a new password.
  reset,

  /// The password was reset successfully.
  done,
}

/// Agent self-service "forgot password" screen. A fully native flow over the
/// `/auth/forgot-password` and `/auth/reset-password` JSON endpoints:
///   request email → check your email → enter code + new password → done.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _requestFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _login = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _Stage _stage = _Stage.request;
  bool _busy = false;
  bool _obscure = true;
  String? _sentMessage;
  String? _tokenError;
  String? _passwordError;

  @override
  void dispose() {
    _login.dispose();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _requestReset() async {
    FocusScope.of(context).unfocus();
    if (!_requestFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final message = await ref
          .read(passwordResetRepositoryProvider)
          .requestReset(_login.text.trim());
      if (!mounted) return;
      setState(() {
        _sentMessage = message;
        _stage = _Stage.emailSent;
      });
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } catch (_) {
      if (mounted) {
        AppSnack.error(context, 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeReset() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _tokenError = null;
      _passwordError = null;
    });
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(passwordResetRepositoryProvider)
          .completeReset(
            token: _token.text.trim(),
            newPassword: _password.text,
          );
      if (!mounted) return;
      setState(() => _stage = _Stage.done);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'invalid_token') {
          _tokenError = e.message;
        } else if (e.fields['new_password'] != null) {
          _passwordError = e.fields['new_password'];
        } else if (e.isValidation) {
          _passwordError = e.message;
        } else {
          AppSnack.error(context, e.message);
        }
      });
    } catch (_) {
      if (mounted) {
        AppSnack.error(context, 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToSignIn() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthUi.canvas(
        context,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: AuthUi.glassCard(
                      context,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _buildStage(context),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 8,
                child: AuthUi.circleBack(context, _backToSignIn),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) => switch (_stage) {
    _Stage.request => _buildRequest(context),
    _Stage.emailSent => _buildEmailSent(context),
    _Stage.reset => _buildReset(context),
    _Stage.done => _buildDone(context),
  };

  // --- Stage: request -------------------------------------------------------

  Widget _buildRequest(BuildContext context) {
    return Form(
      key: _requestFormKey,
      child: Column(
        key: const ValueKey(_Stage.request),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _logo(),
          const SizedBox(height: 40),
          AuthUi.overline(context, 'Forgot password'),
          const SizedBox(height: 10),
          AuthUi.heading(context, 'Reset it'),
          const SizedBox(height: 10),
          AuthUi.subtitle(
            context,
            'Enter your username or email and we’ll send you a link to reset '
            'your password.',
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _login,
            autofocus: true,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            onFieldSubmitted: (_) => _requestReset(),
            decoration: AuthUi.fieldDecoration(
              context,
              hint: 'Username or email',
              icon: Icons.person_outline,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 24),
          AuthUi.primaryButton(
            context,
            label: 'Send reset link',
            icon: Icons.send_outlined,
            busy: _busy,
            onPressed: _requestReset,
          ),
          const SizedBox(height: 14),
          Center(
            child: AuthUi.link(
              context,
              label: 'Already have a reset code from the email? Enter it',
              onPressed: _busy
                  ? null
                  : () => setState(() => _stage = _Stage.reset),
            ),
          ),
          Center(child: _backButton(context)),
        ],
      ),
    );
  }

  // --- Stage: email sent ----------------------------------------------------

  Widget _buildEmailSent(BuildContext context) {
    return Column(
      key: const ValueKey(_Stage.emailSent),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _iconBadge(Icons.mark_email_read_outlined, AppTheme.open),
        const SizedBox(height: 24),
        AppText.headText(
          context,
          'Check your email',
          fw: 2,
          align: TextAlign.center,
          color: AuthUi.headingColor(context),
        ),
        const SizedBox(height: 10),
        AppText.subText(
          context,
          _sentMessage ??
              'If an account matches, a password reset email has been sent. '
                  'Follow the link in the email to reset your password.',
          color: AuthUi.subtitleColor(context),
          align: TextAlign.center,
          lineHeight: 1.45,
        ),
        const SizedBox(height: 32),
        AuthUi.primaryButton(
          context,
          label: 'I have a reset code',
          icon: Icons.vpn_key_outlined,
          busy: _busy,
          onPressed: () => setState(() => _stage = _Stage.reset),
        ),
        const SizedBox(height: 14),
        Center(child: _backButton(context)),
      ],
    );
  }

  // --- Stage: reset ---------------------------------------------------------

  Widget _buildReset(BuildContext context) {
    return Form(
      key: _resetFormKey,
      child: Column(
        key: const ValueKey(_Stage.reset),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _logo(),
          const SizedBox(height: 40),
          AuthUi.overline(context, 'Reset password'),
          const SizedBox(height: 10),
          AuthUi.heading(context, 'New password'),
          const SizedBox(height: 10),
          AuthUi.subtitle(
            context,
            'Paste the reset code from your email and choose a new password.',
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _token,
            autofocus: true,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            decoration: AuthUi.fieldDecoration(
              context,
              hint: 'Reset code',
              icon: Icons.vpn_key_outlined,
              error: _tokenError,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: AuthUi.fieldDecoration(
              context,
              hint: 'New password',
              icon: Icons.lock_outline,
              error: _passwordError,
              suffix: IconButton(
                icon: Icon(
                  !_obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                color: AuthUi.mutedIconColor(context),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty)
                ? 'Required'
                : (v.length < 6 ? 'At least 6 characters' : null),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _completeReset(),
            decoration: AuthUi.fieldDecoration(
              context,
              hint: 'Confirm password',
              icon: Icons.lock_outline,
            ),
            validator: (v) =>
                (v != _password.text) ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 24),
          AuthUi.primaryButton(
            context,
            label: 'Reset password',
            icon: Icons.check,
            busy: _busy,
            onPressed: _completeReset,
          ),
          const SizedBox(height: 14),
          Center(child: _backButton(context)),
        ],
      ),
    );
  }

  // --- Stage: done ----------------------------------------------------------

  Widget _buildDone(BuildContext context) {
    return Column(
      key: const ValueKey(_Stage.done),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _iconBadge(Icons.check_circle_outline, AppTheme.open),
        const SizedBox(height: 24),
        AppText.headText(
          context,
          'Password reset',
          fw: 2,
          align: TextAlign.center,
          color: AuthUi.headingColor(context),
        ),
        const SizedBox(height: 10),
        AppText.subText(
          context,
          'Your password has been updated. You can now sign in with your new '
          'password.',
          color: AuthUi.subtitleColor(context),
          align: TextAlign.center,
          lineHeight: 1.45,
        ),
        const SizedBox(height: 32),
        AuthUi.primaryButton(
          context,
          label: 'Back to sign in',
          icon: Icons.arrow_forward,
          busy: _busy,
          onPressed: _backToSignIn,
        ),
      ],
    );
  }

  // --- Shared pieces --------------------------------------------------------

  Widget _logo() => Align(
    alignment: Alignment.centerLeft,
    child: SvgPicture.asset(Assets.zebuLogo, height: 40),
  );

  Widget _iconBadge(IconData icon, Color color) => Center(
    child: Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 34, color: color),
    ),
  );

  Widget _backButton(BuildContext context) => AuthUi.link(
    context,
    label: 'Back to sign in',
    onPressed: _busy ? null : _backToSignIn,
  );
}
