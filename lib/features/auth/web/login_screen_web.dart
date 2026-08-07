import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/assets.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';
import '../login_screen.dart' show UpperCaseTextFormatter;

/// Web-only login screen, styled to the Zebu Premium spec in `skill.md`.
///
/// Same controller + auth flow as the mobile [LoginScreen] — only the layout
/// changes: centered Geist-typed card on a `bg-primary` page, 44-px inputs
/// with focused accent ring, 46-px primary CTA, sized for desktop browsers.
class LoginScreenWeb extends ConsumerStatefulWidget {
  const LoginScreenWeb({super.key});

  @override
  ConsumerState<LoginScreenWeb> createState() => _LoginScreenWebState();
}

class _LoginScreenWebState extends ConsumerState<LoginScreenWeb> {
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

  @override
  Widget build(BuildContext context) {
    // Apply Geist to this entire subtree — the auth screen sits outside the
    // shell, so we re-apply the typeface here instead of inheriting from
    // HomeShellWeb.
    final base = Theme.of(context);
    final t = ZebuTheme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: ZebuFonts.textTheme(base.textTheme),
      ),
      child: Scaffold(
        backgroundColor: t.bgPrimary,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ZebuSpacing.s6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _LoginCard(
                  formKey: _formKey,
                  username: _username,
                  password: _password,
                  obscure: _obscure,
                  busy: _busy,
                  error: _error,
                  fieldErrors: _fieldErrors,
                  onToggleObscure: () =>
                      setState(() => _obscure = !_obscure),
                  onSubmit: _submit,
                  onForgot: _forgotPassword,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.username,
    required this.password,
    required this.obscure,
    required this.busy,
    required this.error,
    required this.fieldErrors,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgot,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController username;
  final TextEditingController password;
  final bool obscure;
  final bool busy;
  final String? error;
  final Map<String, String> fieldErrors;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgot;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(ZebuRadius.rLg),
        border: Border.all(color: t.borderSubtle, width: 1),
        boxShadow: ZebuElevation.popoverShadow,
      ),
      padding: const EdgeInsets.all(ZebuSpacing.s8),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: SvgPicture.asset(Assets.zebuLogo, height: 38)),
            const SizedBox(height: ZebuSpacing.s8),
            Text('Sign in to Helpdesk', style: ZebuTextStyles.hero(context)),
            const SizedBox(height: ZebuSpacing.s2),
            Text(
              'Use your Zebu staff credentials',
              style: ZebuTextStyles.body(context).copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: ZebuSpacing.s8),

            if (error != null) ...[
              _ErrorBanner(message: error!),
              const SizedBox(height: ZebuSpacing.s6),
            ],

            _TextField(
              controller: username,
              label: 'Username / Email',
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              errorText: fieldErrors['username'],
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: ZebuSpacing.s5),

            _TextField(
              controller: password,
              label: 'Password',
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => onSubmit(),
              errorText: fieldErrors['passwd'],
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              suffix: _IconButton(
                icon: obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                onTap: onToggleObscure,
              ),
            ),
            const SizedBox(height: ZebuSpacing.s8),

            _PrimaryButton(
              label: 'Sign in',
              busy: busy,
              onPressed: busy ? null : onSubmit,
            ),
            const SizedBox(height: ZebuSpacing.s3),

            Align(
              alignment: Alignment.centerRight,
              child: _LinkButton(
                label: 'Forgot password?',
                onTap: busy ? null : onForgot,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Field components
// ---------------------------------------------------------------------------

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.textInputAction,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onFieldSubmitted,
    this.validator,
    this.errorText,
    this.suffix,
  });

  final TextEditingController controller;

  /// Material floating-label text. Renders inside the field at
  /// `bodyBase` size when empty/unfocused, then animates up above the
  /// underline (smaller, accent color) on focus or when a value is
  /// entered — mirrors the reference login mock.
  final String label;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final hasError = errorText != null;
    // Underline-only inputs: idle uses the soft `borderDefault` line;
    // focus/hover swap to accent; error switches to danger. No fill, no
    // rounded box — the label above + the hairline underline are the whole
    // field, matching the reference login mock.
    final idle = UnderlineInputBorder(
      borderSide: BorderSide(
        color: hasError ? t.danger : t.borderDefault,
        width: 1,
      ),
    );
    final focused = UnderlineInputBorder(
      borderSide: BorderSide(
        color: hasError ? t.danger : t.accent,
        width: 1.6,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          textInputAction: textInputAction,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          onFieldSubmitted: onFieldSubmitted,
          validator: validator,
          style: ZebuTextStyles.body(context).copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            filled: false,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            border: idle,
            enabledBorder: idle,
            focusedBorder: focused,
            errorBorder: idle,
            focusedErrorBorder: focused,
            isDense: true,
            // No horizontal padding — content sits flush with the
            // underline ends. Vertical padding gives the label room to
            // sit inside the field before it floats up on focus.
            contentPadding: const EdgeInsets.only(top: 14, bottom: 10),
            labelText: label,
            // Idle label = placeholder-sized, secondary text. Floats up
            // to the smaller `bodySm` size in accent color on focus /
            // when a value is entered.
            labelStyle: ZebuTextStyles.body(context).copyWith(color: t.textSecondary),
            floatingLabelStyle: ZebuTextStyles.small(context).copyWith(
              color: hasError ? t.danger : t.accent,
              fontWeight: FontWeight.w500,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: ZebuSpacing.s2),
          Text(
            errorText!,
            style: ZebuTextStyles.small(context).copyWith(
              color: t.danger,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final enabled = widget.onPressed != null && !widget.busy;
    return MouseRegion(
      cursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 52,
          decoration: BoxDecoration(
            // Stadium pill with the mobile brand gradient (mobile dialog
            // primary-button parity); hover deepens both gradient stops.
            // Disabled falls back to a flat washed fill — a washed-out
            // gradient reads as broken.
            gradient: enabled
                ? (_hover ? t.brandGradientHover : t.brandGradient)
                : null,
            color: enabled
                ? null
                : ZebuTheme.accentLight.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(ZebuRadius.rFull),
          ),
          child: Center(
            child: widget.busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.label,
                    style: ZebuTextStyles.body(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            widget.icon,
            size: 18,
            color: _hover ? t.accent : t.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatefulWidget {
  const _LinkButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_LinkButton> createState() => _LinkButtonState();
}

class _LinkButtonState extends State<_LinkButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: ZebuTextStyles.small(context).copyWith(
            color: enabled ? t.accent : t.textSecondary,
            fontWeight: FontWeight.w600,
            decoration: _hover ? TextDecoration.underline : null,
            decorationColor: t.accent,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(ZebuSpacing.s3),
      decoration: BoxDecoration(
        color: t.dangerLight,
        borderRadius: BorderRadius.circular(ZebuRadius.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: t.danger,
            size: 18,
          ),
          const SizedBox(width: ZebuSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: ZebuTextStyles.small(context).copyWith(
                color: t.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
