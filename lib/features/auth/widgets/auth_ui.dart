import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Shared visual language for the sign-in / forgot-password screens.
///
/// The auth flow is an **aurora glass** experience that follows the app's theme
/// toggle: a deep navy-to-black canvas lit by cyan/indigo "aurora" glows in dark
/// mode, or a soft blue-white twin in light mode — each with a luminous
/// frosted-glass card, a display heading and a cyan accent with an indigo→cyan
/// primary button.
///
/// **Readability first.** Glassmorphism easily fails contrast, so the card fill
/// stays opaque *enough* that text keeps a solid backing, the glows are dimmed
/// so they don't bleed under words, and the matching [ThemeData] is applied over
/// the subtree (see [canvas]) so Material widgets — text fields, cursors, icon
/// buttons — render with the right contrast. Everything stays on Inter.
class AuthUi {
  AuthUi._();

  /// The auth palette follows the app's active brightness so the sign-in flow
  /// matches the theme toggle (dark navy glass, or the light blue-white twin).
  static _AuthPalette _p(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? _AuthPalette.dark
      : _AuthPalette.light;

  /// Themes applied over the auth subtree so Material widgets (fields, cursors,
  /// icon buttons) render with the right contrast. Built once and cached.
  static final ThemeData _darkTheme = AppTheme.dark();
  static final ThemeData _lightTheme = AppTheme.light();

  /// The resolved accent color, exposed for callers that need it directly.
  static Color accent(BuildContext context) => _p(context).accent;

  /// Heading / subtitle / muted-icon tones, exposed so screens that mix in
  /// [AppText]-style widgets can match the dark auth palette exactly.
  static Color headingColor(BuildContext context) => _p(context).heading;
  static Color subtitleColor(BuildContext context) => _p(context).subtitle;
  static Color mutedIconColor(BuildContext context) => _p(context).icon;

  // --- Canvas ----------------------------------------------------------------

  /// Full-bleed aurora canvas: a gradient lit by cyan/indigo glows behind
  /// [child]. In dark mode this is the deep navy-to-black experience; in light
  /// mode a soft blue-white twin. Sets the matching status-bar icon brightness
  /// and applies the corresponding auth theme over the subtree so Material
  /// widgets match.
  static Widget canvas(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = isDark ? _AuthPalette.dark : _AuthPalette.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Theme(
        data: isDark ? _darkTheme : _lightTheme,
        child: Stack(
          children: [
            // Deep vertical gradient: navy at the top fading to near-black.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.bgA, p.bgB, p.bgC],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // Aurora glows — cyan and indigo bloom behind the card.
            Positioned(top: -110, right: -80, child: _blob(320, p.blobBlue)),
            Positioned(bottom: -130, left: -90, child: _blob(340, p.blobTeal)),
            Positioned(top: 200, left: -70, child: _blob(220, p.blobNavy)),
            child,
          ],
        ),
      ),
    );
  }

  static Widget _blob(double size, Color color) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ),
      ),
    ),
  );

  // --- Glass card ------------------------------------------------------------

  /// Frosted-glass card that holds the auth form. Translucent + blurred for the
  /// glass effect, but opaque enough that text stays readable.
  static Widget glassCard(BuildContext context, {required Widget child}) {
    final p = _p(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: p.glassShadow,
            blurRadius: 50,
            offset: const Offset(0, 26),
          ),
          // Faint accent bloom so the card feels lit from within.
          BoxShadow(
            color: p.accent.withValues(alpha: 0.10),
            blurRadius: 44,
            spreadRadius: -6,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p.glassFillTop, p.glassFillBottom],
              ),
              border: Border.all(color: p.glassBorder, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  // --- Text ------------------------------------------------------------------

  /// Uppercase, letter-spaced overline, e.g. "STAFF PORTAL".
  static Widget overline(BuildContext context, String text) => Text(
    text.toUpperCase(),
    style: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.8,
      color: _p(context).overline,
    ),
  );

  /// Large display heading with a teal accent period, e.g. "Welcome back.".
  /// [title] must NOT include the trailing dot — it is appended in the accent.
  static Widget heading(BuildContext context, String title) {
    final p = _p(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: title),
          TextSpan(text: '.', style: TextStyle(color: p.accent)),
        ],
        style: GoogleFonts.inter(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.08,
          letterSpacing: -0.6,
          color: p.heading,
        ),
      ),
    );
  }

  /// Supporting line under the heading, with theme-aware contrast.
  static Widget subtitle(BuildContext context, String text) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: _p(context).subtitle,
    ),
  );

  // --- Inputs / buttons ------------------------------------------------------

  /// Pill field decoration with a leading [icon] and a teal focus ring.
  ///
  /// Pass [label] to get a **floating label** that rests inside the field and
  /// animates up (in the accent color) on focus/fill — the premium alternative
  /// to a static [hint]. Both can be supplied; the hint then only shows while
  /// the field is focused and empty.
  static InputDecoration fieldDecoration(
    BuildContext context, {
    required IconData icon,
    String? hint,
    String? label,
    Widget? suffix,
    String? error,
  }) {
    final p = _p(context);
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.hint),
      labelText: label,
      labelStyle: GoogleFonts.inter(color: p.hint, fontWeight: FontWeight.w500),
      floatingLabelStyle: GoogleFonts.inter(
        color: p.accent,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      prefixIcon: Icon(icon, size: 20, color: p.icon),
      suffixIcon: suffix,
      errorText: error,
      // Full-sentence messages must never truncate to "…" — let them wrap.
      errorMaxLines: 2,
      filled: true,
      fillColor: p.fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
      border: border(p.fieldBorder),
      enabledBorder: border(p.fieldBorder),
      focusedBorder: border(p.accent, 1.6),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 1.6),
    );
  }

  /// Compact, accessible "Remember me" toggle: a rounded custom checkbox that
  /// fills with the accent color when [value] is set. The whole row is one tap
  /// target and exposes a semantic `checked` state to screen readers.
  static Widget rememberMe(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final p = _p(context);
    return Semantics(
      container: true,
      checked: value,
      label: 'Remember me',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? p.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value ? p.accent : p.icon,
                    width: 1.6,
                  ),
                ),
                child: value
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                'Remember me',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: p.subtitle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Navy-gradient primary action button with a teal leading [icon],
  /// collapsing to a spinner while [busy] and dipping slightly on press.
  static Widget primaryButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback? onPressed,
  }) => _PrimaryButton(
    label: label,
    icon: icon,
    busy: busy,
    onPressed: onPressed,
  );

  /// Teal text link used beneath the form (e.g. "Forgot password?").
  static Widget link(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
  }) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: _p(context).link,
      textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );

  /// Circular, frosted back button for the top-left of secondary auth screens.
  static Widget circleBack(BuildContext context, VoidCallback onPressed) {
    final p = _p(context);
    return Material(
      color: p.circleBackFill,
      shape: CircleBorder(side: BorderSide(color: p.glassBorder)),
      elevation: 1,
      shadowColor: p.glassShadow,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.arrow_back, size: 20, color: p.circleBackIcon),
        ),
      ),
    );
  }
}

/// Primary action button with a subtle scale-down on press. Kept private —
/// callers use [AuthUi.primaryButton], whose signature it mirrors exactly.
class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = AuthUi._p(context);
    final enabled = !widget.busy && widget.onPressed != null;

    void setPressed(bool v) {
      if (enabled && _pressed != v) setState(() => _pressed = v);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          height: 54,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [p.buttonA, p.buttonB],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: p.buttonA.withValues(alpha: 0.42),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: enabled ? widget.onPressed : null,
                onTapDown: (_) => setPressed(true),
                onTapUp: (_) => setPressed(false),
                onTapCancel: () => setPressed(false),
                child: Center(
                  child: widget.busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.label,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(widget.icon, size: 18, color: p.arrow),
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

/// Staggered fade-and-rise entrance for a single element, driven by a shared
/// [controller]. Higher [order] values start slightly later, so a column of
/// these reads as a smooth cascade rather than everything popping at once.
///
/// Purely decorative: it wraps [child] in opacity + a small vertical offset and
/// never intercepts input, so layout and semantics are unchanged.
class AuthFadeSlideIn extends StatelessWidget {
  const AuthFadeSlideIn({
    required this.controller,
    required this.order,
    required this.child,
    super.key,
  });

  final AnimationController controller;
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Each element opens a 55% window that begins a touch after the previous
    // one; clamped so later items still finish within the controller's run.
    final start = (order * 0.07).clamp(0.0, 0.45);
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.55).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Resolved color set for one brightness. Alphas are baked into the ARGB hex so
/// the palettes can be `const`.
class _AuthPalette {
  const _AuthPalette({
    required this.bgA,
    required this.bgB,
    required this.bgC,
    required this.blobBlue,
    required this.blobTeal,
    required this.blobNavy,
    required this.glassFillTop,
    required this.glassFillBottom,
    required this.glassBorder,
    required this.glassShadow,
    required this.heading,
    required this.subtitle,
    required this.overline,
    required this.fieldFill,
    required this.hint,
    required this.icon,
    required this.fieldBorder,
    required this.accent,
    required this.link,
    required this.buttonA,
    required this.buttonB,
    required this.arrow,
    required this.circleBackFill,
    required this.circleBackIcon,
  });

  final Color bgA, bgB, bgC;
  final Color blobBlue, blobTeal, blobNavy;
  final Color glassFillTop, glassFillBottom, glassBorder, glassShadow;
  final Color heading, subtitle, overline;
  final Color fieldFill, hint, icon, fieldBorder;
  final Color accent, link;
  final Color buttonA, buttonB, arrow;
  final Color circleBackFill, circleBackIcon;

  /// Cool, moody dark palette — deep navy-to-black canvas, cyan/indigo aurora
  /// glows, a luminous frosted panel, a cyan accent and an indigo→cyan CTA.
  static const dark = _AuthPalette(
    bgA: Color(0xFF0B1120),
    bgB: Color(0xFF0A0E1A),
    bgC: Color(0xFF05070D),
    blobBlue: Color(0x3322D3EE), // cyan bloom
    blobTeal: Color(0x336366F1), // indigo bloom
    blobNavy: Color(0x2238BDF8), // sky bloom
    glassFillTop: Color(0x2620304F),
    glassFillBottom: Color(0x12121A2E),
    glassBorder: Color(0x24FFFFFF),
    glassShadow: Color(0x99000000),
    heading: Color(0xFFF2F6FC),
    subtitle: Color(0xA8FFFFFF),
    overline: Color(0xFF67E8F9),
    fieldFill: Color(0x14FFFFFF),
    hint: Color(0x73FFFFFF),
    icon: Color(0x99FFFFFF),
    fieldBorder: Color(0x24FFFFFF),
    accent: Color(0xFF22D3EE),
    link: Color(0xFF38BDF8),
    buttonA: Color(0xFF6366F1), // indigo
    buttonB: Color(0xFF22D3EE), // cyan
    arrow: Color(0xFFFFFFFF),
    circleBackFill: Color(0x1FFFFFFF),
    circleBackIcon: Color(0xFFF2F6FC),
  );

  /// Light twin — a soft blue-white canvas, subtle cyan/indigo/sky glows, a
  /// frosted white panel, a deeper cyan accent and sky link (darkened for
  /// contrast on white) and the same indigo→cyan CTA.
  static const light = _AuthPalette(
    bgA: Color(0xFFEDF2FB),
    bgB: Color(0xFFF4F6FB),
    bgC: Color(0xFFFCFDFF),
    blobBlue: Color(0x1F6366F1), // indigo bloom
    blobTeal: Color(0x1A22D3EE), // cyan bloom
    blobNavy: Color(0x1F38BDF8), // sky bloom
    glassFillTop: Color(0xF2FFFFFF),
    glassFillBottom: Color(0xE6FFFFFF),
    glassBorder: Color(0x14101828),
    glassShadow: Color(0x1A0B1E4D),
    heading: Color(0xFF101828),
    subtitle: Color(0xFF5B6472),
    overline: Color(0xFF0891B2),
    fieldFill: Color(0xFFF1F4FA),
    hint: Color(0xFF98A2B3),
    icon: Color(0xFF667085),
    fieldBorder: Color(0xFFE2E8F0),
    accent: Color(0xFF0891B2),
    link: Color(0xFF0A6CD8),
    buttonA: Color(0xFF6366F1), // indigo
    buttonB: Color(0xFF0891B2), // cyan (deepened for white-text contrast)
    arrow: Color(0xFFFFFFFF),
    circleBackFill: Color(0xE6FFFFFF),
    circleBackIcon: Color(0xFF344054),
  );
}
