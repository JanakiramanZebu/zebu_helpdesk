import 'package:flutter/material.dart';

import 'zebu_theme.dart';

/// The leading mark on a status badge, when a glyph would be too literal.
enum ZebuStatusMark {
  none,

  /// Solid dot — a settled, owned state.
  dot,

  /// Ring — deliberately empty, for states where nobody owns the ticket yet.
  hollowDot,

  /// Dot inside a faint ring — reads as motion, for work actively in flight.
  haloDot,

  // Signal-strength bars for priority. Always three bars drawn, with the
  // inactive ones ghosted: the empty slots are what make the level readable
  // at a glance, the way a battery gauge needs its empty portion.
  bars1,
  bars2,
  bars3,
}

/// Everything needed to paint one status badge.
///
/// A badge is more than a colour: this system distinguishes states by **fill
/// weight** as well as hue, and that carries most of the meaning. Only one
/// state in the whole app is solid-filled — Escalated — so exactly one thing
/// can ever win the page. Inactive states drop the fill entirely and recede
/// to an outline, which is how a list of forty closed tickets stays readable.
class ZebuStatusStyle {
  const ZebuStatusStyle({
    required this.bg,
    required this.ink,
    this.border,
    this.dashed = false,
    this.icon,
    this.mark = ZebuStatusMark.none,
    this.strikethrough = false,
  });

  final Color bg;
  final Color ink;

  /// Null for the solid badge, which needs no edge.
  final Color? border;

  /// Dashed edge — "provisional", used where the state is an absence
  /// (nobody assigned, record removed) rather than a decision.
  final bool dashed;

  /// Leading glyph. Takes precedence over [mark].
  final IconData? icon;
  final ZebuStatusMark mark;

  /// Struck-through label, for Deleted. Never red — red means *urgent* here,
  /// not *gone*.
  final bool strikethrough;
}

// Light-mode values. Kept as one table rather than derived from a base hue:
// the fills are hand-balanced so that at 11 px the inks all read at roughly
// equal weight, which arithmetic on a single hue does not give you.
const _escalatedBg = Color(0xFFB42318);
const _escalatedInk = Color(0xFFFFFFFF);

/// Resolves a status name to its badge style.
///
/// [overdue] wins over everything — a ticket past its SLA is the most urgent
/// thing about it, whatever its status says — and shares Escalated's solid
/// fill because they mean the same thing to an agent: act now.
///
/// Matching is on the whole name, not `contains()`. The old code gave
/// `Re-Open` the Open colour only because that string happens to contain
/// "open", so renaming a status silently changed its colour. Unknown statuses
/// fall back to neutral: admins can add their own in osTicket, and one of
/// those must never render as urgent.
ZebuStatusStyle zebuStatusStyle(
  String status,
  ZebuTheme t, {
  bool overdue = false,
}) {
  final light = t.isLight;
  if (overdue) {
    return const ZebuStatusStyle(
      bg: _escalatedBg,
      ink: _escalatedInk,
      icon: Icons.schedule_rounded,
    );
  }

  // Collapse spelling variants: osTicket installs name these freely, so
  // "Re-Open", "re open", and "reopen" all have to land in one place.
  final s = status.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

  switch (s) {
    // The only solid badge in the system. Reserved so it always wins.
    case 'escalated':
    case 'overdue':
      return const ZebuStatusStyle(
        bg: _escalatedBg,
        ink: _escalatedInk,
        icon: Icons.warning_amber_rounded,
      );

    // Grey, not amber. "Nobody owns this yet" is an absence, not an alarm —
    // painting it warm made it compete with Escalated for the same attention.
    case 'unassigned':
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFF2F4F7) : const Color(0xFF21262D),
        ink: light ? const Color(0xFF475467) : const Color(0xFF9BA5B4),
        border: light ? const Color(0xFFCDD3DD) : const Color(0xFF3D444D),
        dashed: true,
        mark: ZebuStatusMark.hollowDot,
      );

    // The product's accent blue — the default working state. Deliberately not
    // green: green has to mean *resolved*, and if Open were green a list
    // would show one colour for the two states furthest apart.
    case 'open':
    case 'new':
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFEEF2FD) : const Color(0xFF16263C),
        ink: light ? const Color(0xFF2B49B0) : const Color(0xFF8AB4FF),
        border: light ? const Color(0xFFDBE3FB) : const Color(0xFF1F3A5F),
        mark: ZebuStatusMark.dot,
      );

    case 'inprogress':
    case 'pending':
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFFFF7ED) : const Color(0xFF2E2113),
        ink: light ? const Color(0xFF9A4B06) : const Color(0xFFF0B266),
        border: light ? const Color(0xFFF3E3CD) : const Color(0xFF4A3820),
        mark: ZebuStatusMark.haloDot,
      );

    // Violet, deliberately not blue, so a regression doesn't look like an
    // ordinary open ticket — and not amber either, or it reads the same as
    // Unassigned.
    case 'reopen':
    case 'reopened':
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFF4F0FF) : const Color(0xFF241D3D),
        ink: light ? const Color(0xFF5B34C4) : const Color(0xFFB49CFF),
        border: light ? const Color(0xFFE3DBFA) : const Color(0xFF3A2F5C),
        icon: Icons.refresh_rounded,
      );

    /// Waiting on the customer — ours, not in the source spec. Indigo sits
    /// between Open's blue and Re-opened's violet: related to both, since the
    /// ticket is live, but distinct from the states an agent must act on.
    case 'answered':
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFEEF1FE) : const Color(0xFF1B1F3B),
        ink: light ? const Color(0xFF3730A3) : const Color(0xFFA5B4FC),
        border: light ? const Color(0xFFDDE1FB) : const Color(0xFF2E3566),
        icon: Icons.mark_chat_read_outlined,
      );

    case 'resolved':
    case 'completed':
    case 'complete':
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFE9F6EE) : const Color(0xFF10291F),
        ink: light ? const Color(0xFF17683A) : const Color(0xFF5DD6A0),
        border: light ? const Color(0xFFCFE8DB) : const Color(0xFF1E4433),
        icon: Icons.check_rounded,
      );

    // Desaturated green rather than grey: Closed belongs to the same family
    // as Resolved — the work landed — it is just no longer editable.
    case 'closed':
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFEFF3F1) : const Color(0xFF1B2420),
        ink: light ? const Color(0xFF3F5A4C) : const Color(0xFF8FB3A0),
        border: light ? const Color(0xFFD6E2DA) : const Color(0xFF2C3A33),
        icon: Icons.lock_outline_rounded,
      );

    // No fill at all. An archived row should recede in a list without
    // disappearing from it.
    case 'archived':
      return ZebuStatusStyle(
        bg: Colors.transparent,
        ink: light ? const Color(0xFF667085) : const Color(0xFF8B949E),
        border: light ? const Color(0xFFD9DCE3) : const Color(0xFF30363D),
        icon: Icons.inventory_2_outlined,
      );

    // Lowest contrast in the system, struck through. Never red: red is
    // reserved for *urgent*, and a deleted ticket is the opposite of urgent.
    case 'deleted':
      return ZebuStatusStyle(
        bg: Colors.transparent,
        ink: light ? const Color(0xFF98A2B3) : const Color(0xFF6E7681),
        border: light ? const Color(0xFFE4E7EC) : const Color(0xFF30363D),
        dashed: true,
        strikethrough: true,
      );

    default:
      return ZebuStatusStyle(
        bg: light ? const Color(0xFFF2F4F7) : const Color(0xFF21262D),
        ink: light ? const Color(0xFF475467) : const Color(0xFF9BA5B4),
        border: light ? const Color(0xFFE4E7EC) : const Color(0xFF30363D),
      );
  }
}

/// Badge style for a ticket / task priority.
///
/// A separate vocabulary from status, sharing the same rendering. The two
/// scales meet at one point: **Emergency wears the same solid red as
/// Escalated**, because to an agent they mean the identical thing — drop what
/// you are doing. Everything below it is deliberately quiet, and Normal
/// quietest of all: around 70 % of tickets land there, so if Normal had any
/// colour at all the column would be a wall of it and the two priorities that
/// matter would be lost in it.
ZebuStatusStyle zebuPriorityStyle(String? priority, ZebuTheme t) {
  final light = t.isLight;
  final p = (priority ?? '').trim().toLowerCase();

  if (p.contains('emergency') || p.contains('urgent')) {
    // A burnt red-brown rather than Escalated's `#B42318`. The two are the
    // only solid badges in the app and they sit in adjacent table columns, so
    // keeping them at the same value made a row with both read as one wide
    // red smear. This is darker and lower-chroma: still unmistakably the
    // top of the scale, but it doesn't compete with a status alarm.
    return const ZebuStatusStyle(
      bg: Color(0xFF9C4221),
      ink: _escalatedInk,
      icon: Icons.warning_amber_rounded,
    );
  }
  if (p.contains('high')) {
    return ZebuStatusStyle(
      bg: light ? const Color(0xFFFFF4E8) : const Color(0xFF2E2113),
      ink: light ? const Color(0xFFB54708) : const Color(0xFFF0B266),
      border: light ? const Color(0xFFFBE0C4) : const Color(0xFF4A3820),
      mark: ZebuStatusMark.bars3,
    );
  }
  if (p.contains('low')) {
    return ZebuStatusStyle(
      bg: light ? const Color(0xFFF2F4F7) : const Color(0xFF21262D),
      ink: light ? const Color(0xFF667085) : const Color(0xFF8B949E),
      border: light ? const Color(0xFFE4E7EC) : const Color(0xFF30363D),
      mark: ZebuStatusMark.bars1,
    );
  }
  // Normal, and anything an admin has added that isn't one of the above.
  return ZebuStatusStyle(
    bg: light ? const Color(0xFFF2F4F7) : const Color(0xFF21262D),
    ink: light ? const Color(0xFF344054) : const Color(0xFFC9D1D9),
    border: light ? const Color(0xFFE4E7EC) : const Color(0xFF30363D),
    mark: ZebuStatusMark.bars2,
  );
}
