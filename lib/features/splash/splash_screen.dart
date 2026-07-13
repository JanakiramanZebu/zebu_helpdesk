import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/assets.dart';
import '../../core/theme/app_text.dart';
import '../../widgets/glass.dart';

/// Shown while the auth controller bootstraps the session.
///
/// Speaks the same **aurora glass** language as the auth flow and the main
/// tabs: the app-wide [Glass.canvas] (applied in `app.dart`) shows through the
/// transparent scaffold, and over it floats a frosted logo badge lit by a cyan
/// accent bloom, the branded heading with a "STAFF PORTAL" overline, and a
/// three-dot cyan loader. Everything is theme-driven so it follows the toggle.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // One-shot entrance: the badge + text fade and rise into place.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  // Continuous heartbeat driving the accent bloom's breathing and the loader.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enter = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AnimatedBuilder(
          animation: enter,
          builder: (context, child) => Opacity(
            opacity: enter.value,
            child: Transform.translate(
              offset: Offset(0, (1 - enter.value) * 20),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _logoBadge(context),
              const SizedBox(height: 26),
              AppText.custmText(
                context,
                'Zebu Helpdesk',
                fs: 24,
                fw: 2,
                letterSpacing: -0.4,
                color: Glass.textPrimary(context),
              ),
              const SizedBox(height: 8),
              AppText.custmText(
                context,
                'STAFF PORTAL',
                fs: 12,
                fw: 1,
                letterSpacing: 3.2,
                color: Glass.accent,
              ),
              const SizedBox(height: 34),
              _DotsLoader(animation: _pulse),
            ],
          ),
        ),
      ),
    );
  }

  /// Frosted rounded-square badge holding the brand mark, with a breathing
  /// cyan bloom behind it so it feels lit from within.
  Widget _logoBadge(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // 0..1..0 breathe over the loop.
        final t = (math.sin(_pulse.value * 2 * math.pi) + 1) / 2;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Glass.accent.withValues(alpha: 0.18 + t * 0.22),
                    blurRadius: 44 + t * 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: Glass.surfaceFill(context),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Glass.border(context, 0.16)),
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(Assets.brandLogo, width: 52, height: 52),
      ),
    );
  }
}

/// Three cyan dots that fill and fade in sequence — a calm, on-brand
/// indeterminate loader that reads on both the dark and light canvas.
class _DotsLoader extends StatelessWidget {
  const _DotsLoader({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              // Each dot peaks a third of the loop after the previous one.
              final phase = (animation.value - i * 0.18) % 1.0;
              final t = (math.sin(phase.clamp(0.0, 1.0) * math.pi)).abs();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Glass.accent.withValues(alpha: 0.28 + t * 0.72),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
