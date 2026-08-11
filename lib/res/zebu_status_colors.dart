import 'package:flutter/material.dart';

import 'zebu_theme.dart';

/// Semantic colours for ticket / task statuses and priorities.
///
/// One shared map so Tickets, Tasks, and the detail panels can't disagree —
/// each screen used to carry its own copy, and they had already drifted.
///
/// The scheme reads on one axis: **warm means it needs an agent, cool means
/// it is in hand, green means done, grey means over.**
///
///   red     Escalated, Overdue      — act now
///   amber   Unassigned, Re-Open     — needs picking up
///   blue    Open, In-progress       — active and owned
///   indigo  Answered                — waiting on the customer
///   green   Resolved                — fixed, pending closure
///   grey    Closed, Archived        — finished
///   dull red Deleted                — gone
///
/// Note that **Open is blue, not green**. Green has to mean *resolved*; if
/// Open were green too, a list would show the same colour for "needs work"
/// and "done" — the two states furthest apart.
///
/// Matching is on the whole name, not `contains()`. The old code gave
/// `Re-Open` the Open colour only because that string happens to contain
/// "open", so renaming a status silently changed its colour.

/// Filed away — quieter than Closed so archived rows recede further.
const _archivedLight = Color(0xFF8B93A1);
const _archivedDark = Color(0xFF6E7681);

/// Removed. Desaturated so it reads as "gone" without competing with the
/// alarm red that Escalated and Overdue use.
const _deletedLight = Color(0xFFB4666A);
const _deletedDark = Color(0xFFC98287);

/// Colour for a ticket or task status.
///
/// [overdue] wins over everything — a ticket past its SLA is the most urgent
/// thing about it, whatever its status says.
///
/// Unknown statuses fall back to grey. Statuses come from the API
/// (`MetaKind.statuses`) and admins can add more, so an unrecognised one must
/// never render as urgent.
Color zebuStatusColor(String status, ZebuTheme t, {bool overdue = false}) {
  if (overdue) return t.danger;
  // Collapse spelling variants: osTicket installs name these freely, so
  // "Re-Open", "re open", and "reopen" all have to land in one place.
  final s = status.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  switch (s) {
    case 'escalated':
    case 'overdue':
      return t.danger;

    case 'unassigned':
    case 'reopen':
    case 'reopened':
      return ZebuTheme.warning;

    case 'open':
    case 'new':
    case 'inprogress':
    case 'pending':
      return ZebuTheme.info;

    case 'answered':
      return ZebuTheme.indigo;

    case 'resolved':
    case 'completed':
    case 'complete':
      return ZebuTheme.success;

    case 'closed':
      return t.textSecondary;

    case 'archived':
      return t.isLight ? _archivedLight : _archivedDark;

    case 'deleted':
      return t.isLight ? _deletedLight : _deletedDark;

    default:
      return t.textSecondary;
  }
}

/// The label tone to use when text sits on a *tint* of [base].
///
/// The semantic colours come from Mynt Plus Web's trading palette, where
/// vividness is the point — `#FF1717` and `#00B14F` have to be unmissable
/// because they signal money. On a status pill they do a quieter job, and at
/// 12 px on a 12 % wash of themselves they read as harsh and score poorly for
/// contrast. Amber is the worst: `#FFB038` on amber-12 % is barely legible.
///
/// So the fill keeps the bright hue and the label drops to a deeper, lower
/// chroma version of it — the pale-fill / dark-text pairing GitHub, Linear,
/// and most design systems use for badges.
///
/// Dark mode returns [base] untouched: those palette values are already
/// picked to sit on dark surfaces, and darkening them further would sink
/// them into the tint.
Color zebuOnTint(Color base, ZebuTheme t) {
  if (!t.isLight) return base;
  if (base == ZebuTheme.dangerBrandLight) return const Color(0xFFB42318);
  if (base == ZebuTheme.warning) return const Color(0xFFB54708);
  if (base == ZebuTheme.success) return const Color(0xFF027A48);
  if (base == ZebuTheme.info) return const Color(0xFF175CD3);
  if (base == ZebuTheme.indigo) return const Color(0xFF4338CA);
  // Greys and the already-muted Deleted red need no adjustment.
  return base;
}

/// Colour for a ticket or task priority. Kept here beside the status map
/// because the two were duplicated together on every screen.
Color zebuPriorityColor(String? priority, ZebuTheme t) {
  final p = (priority ?? '').trim().toLowerCase();
  if (p.isEmpty) return t.textSecondary;
  if (p.contains('emergency') || p.contains('urgent')) return t.danger;
  if (p.contains('high')) return ZebuTheme.warning;
  if (p.contains('low')) return ZebuTheme.success;
  return ZebuTheme.info;
}
