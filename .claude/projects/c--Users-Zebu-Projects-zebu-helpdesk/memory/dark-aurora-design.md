---
name: dark-aurora-design
description: The app's auth flow and all 5 main tabs use a shared dark "aurora glass" design language
metadata:
  type: project
---

The sign-in/forgot-password screens and all five main shell tabs (Dashboard, Tickets, Tasks, Inbox, More) render as a dedicated **dark "aurora glass"** experience regardless of the user's `themeMode`.

Two material sources, kept visually in sync (deep navy→black gradient + cyan/indigo/sky aurora glows, translucent frosted panels, cyan `#22D3EE` accent, sky `#38BDF8` links, indigo `#6366F1`, Inter):
- **Auth**: `lib/features/auth/widgets/auth_ui.dart` (`AuthUi`) — always-dark canvas/glass card, forces `AppTheme.dark()` over its subtree.
- **Tabs**: `lib/widgets/glass.dart` (`Glass`) — `Glass.canvas` + `Glass.tint` applied once at the shell (`home_shell.dart`), so every branch inherits the dark theme. `Glass.tint` keeps overlays (dialogs/menus/sheets) opaque via `overlayFill` and makes app bars transparent.

**Why:** user asked to redesign login "premium/dark cool", then extend the same material to the dashboard and then all main tabs.

**How to apply:** new tab UI should be theme-driven (read `colorScheme`) so it inherits the tint; recolor any hardcoded `AppTheme.brand`/`brandDark` accents to `Glass.indigo`/`Glass.accent`. Keep semantic status colors (open/overdue/warning/closed).

Known trade-offs (as of 2026-07-08): pushed **detail** screens (ticket/task/reports/profile) are NOT in the shell, so they still follow `themeMode` (light unless changed) — a dark-list→light-detail jump. The More→Appearance theme toggle therefore only affects those pushed screens, not the always-dark tabs.
