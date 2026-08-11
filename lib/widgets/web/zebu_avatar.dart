import 'package:flutter/material.dart';

import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';

/// One participant swatch — a pale fill with a deep label of the same hue.
///
/// The same device the status pills use (`color @ 12%` behind a `zebuOnTint`
/// label), applied to people. The previous palette was eight saturated
/// mid-tones with white initials, which read as candy against an otherwise
/// slate-and-white thread, and two of its eight entries (`#F6B93B` amber and
/// `#F5A623` orange) were near-identical, so distinct participants kept
/// landing on visually the same swatch.
class _Swatch {
  const _Swatch(this.fillLight, this.textLight, this.fillDark, this.textDark);
  final Color fillLight;
  final Color textLight;
  final Color fillDark;
  final Color textDark;
}

/// Eight hues, each clearly separable from the other seven at 32 px.
const _kSwatches = <_Swatch>[
  // blue
  _Swatch(Color(0xFFEFF4FF), Color(0xFF175CD3), Color(0xFF172A45),
      Color(0xFF7CB0FF)),
  // violet
  _Swatch(Color(0xFFF4F0FF), Color(0xFF5B3FBF), Color(0xFF241D3D),
      Color(0xFFB49CFF)),
  // green
  _Swatch(Color(0xFFECFDF5), Color(0xFF027A48), Color(0xFF10291F),
      Color(0xFF5DD6A0)),
  // amber
  _Swatch(Color(0xFFFFF4ED), Color(0xFFB54708), Color(0xFF2E2113),
      Color(0xFFF0B266)),
  // pink
  _Swatch(Color(0xFFFDF2F8), Color(0xFFB4297A), Color(0xFF2E1826),
      Color(0xFFF08CC4)),
  // teal
  _Swatch(Color(0xFFEFFCFB), Color(0xFF0E7490), Color(0xFF10272B),
      Color(0xFF5CC8D8)),
  // red
  _Swatch(Color(0xFFFEF3F2), Color(0xFFB42318), Color(0xFF2E1A19),
      Color(0xFFF08A82)),
  // slate
  _Swatch(Color(0xFFF2F4F7), Color(0xFF475467), Color(0xFF21262D),
      Color(0xFFA9B4C4)),
];

/// Picks a swatch from a name. Deterministic, so the same actor keeps the same
/// colour across reloads and across screens — the ticket thread, the task
/// thread, the org contacts list, and the user panel all hash identically.
_Swatch _swatchFor(String s) {
  if (s.isEmpty) return _kSwatches[0];
  var hash = 0;
  for (final c in s.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return _kSwatches[hash % _kSwatches.length];
}

/// The deep label tone for a name — exposed so a screen can colour the author
/// name to match its avatar without reaching into the palette itself.
Color zebuAvatarTone(String name, ZebuTheme t) {
  final s = _swatchFor(name);
  return t.isLight ? s.textLight : s.textDark;
}

/// Circular avatar showing up to two initials, coloured from [name].
///
/// Replaces the four hand-copied `_ActorAvatar` classes that used to live in
/// the ticket, task, org, and user detail panels — all four were identical,
/// and all four drifted from the design system in the same way.
class ZebuAvatar extends StatelessWidget {
  const ZebuAvatar({super.key, required this.name, this.size = 32});

  final String name;
  final double size;

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final s = _swatchFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.isLight ? s.fillLight : s.fillDark,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: ZebuTextStyles.small(
          context,
          color: t.isLight ? s.textLight : s.textDark,
          fontWeight: ZebuFonts.semiBold,
          // Scales with the circle so a larger avatar isn't a big ring around
          // small initials.
        ).copyWith(fontSize: size * 0.40, height: 1.0, letterSpacing: 0.2),
      ),
    );
  }
}
