# Zebu Helpdesk — Tester Guide & Flow Index

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Purpose:** A single map of every BRD so a tester can follow the app's flows end-to-end and find the exact case for any behaviour. **Version:** 1.0 **Date:** August 2026

---

## How to use this pack

- The app is documented as **17 BRDs**, one per module, each a `docs/brd/<PREFIX>-*-brd.pdf` (with a `.md` source).
- Every testable behaviour is a **case** identified as `PREFIX-0NN` (e.g. `TK-016` = the ticket reply composer). Each case has a Description, testable **Acceptance Criteria**, and a **Priority** (High / Medium / Low).
- Cases specify **functionality only** (not colours/themes).
- **Global behaviours** (attachments, push, offline, filter sheet, pickers, list behaviour, session expiry) live in the **GL** BRD and are referenced by the feature BRDs instead of being repeated.
- **Total: 152 cases across 17 modules.**

---

## Module map

| Prefix | Module | Cases | BRD file |
|--------|--------|-------|----------|
| GL | Global & Shared Flows | 9 | `GL-global-shared-brd.pdf` |
| AU | Authentication | 15 | `AU-authentication-brd.pdf` |
| NV | Navigation Shell | 3 | `NV-navigation-shell-brd.pdf` |
| DB | Dashboard | 7 | `DB-dashboard-brd.pdf` |
| TK | Tickets | 34 | `TK-tickets-brd.pdf` |
| TS | Tasks | 30 | `TS-tasks-brd.pdf` |
| NT | Notifications (Inbox) | 5 | `NT-notifications-brd.pdf` |
| RP | Reports | 6 | `RP-reports-brd.pdf` |
| OR | Organizations | 8 | `OR-organizations-brd.pdf` |
| US | Users | 7 | `US-users-brd.pdf` |
| AG | Agents (Directory) | 2 | `AG-agents-brd.pdf` |
| QU | Saved Queues | 5 | `QU-queues-brd.pdf` |
| CR | Canned Responses | 4 | `CR-canned-brd.pdf` |
| FQ | Knowledgebase (FAQ) | 4 | `FQ-knowledgebase-brd.pdf` |
| PR | Profile | 5 | `PR-profile-brd.pdf` |
| MO | More (Menu Hub) | 4 | `MO-more-brd.pdf` |
| ST | Settings (Server) | 4 | `ST-settings-brd.pdf` |

---

## End-to-end flows (walk these in order)

Each flow lists the case-ID trail a tester follows. Follow them top-to-bottom for a full regression pass.

### Flow 1 — Launch & sign in
`AU-001` splash → `AU-002` routing guard sends unauthenticated users to Login → `AU-003…AU-010` sign in (username uppercase-in/lowercase-out, show/hide password, remember-me, errors) → on success the guard lands on the **Dashboard** (`DB-001`).
- Forgot-password branch: `AU-007` → `AU-011` request → `AU-012` email sent → `AU-013` enter code + new password → `AU-014` done → back to Login (`AU-015`).

### Flow 2 — Home overview & triage
`DB-001/DB-002` dashboard loads + greeting → `DB-003` ticket tiles/chips, `DB-006` task tiles/chips (each drills into a pre-filtered list) → `DB-004` **Needs attention** (tap an overdue ticket → ticket detail) → `DB-005` Overview volume + chart → `DB-007` breakdown charts.

### Flow 3 — Find & open a ticket
`NV-001` tap the **Tickets** tab → `TK-001` filter tabs + counts → `TK-002` search / `TK-003` filter & sort sheet (**details in `GL-005`**) → `TK-004` read the row → `TK-005` layout toggle, `TK-006` scroll pagination → `TK-010` tap to open.

### Flow 4 — Work a ticket end-to-end
`TK-011` detail loads → `TK-012` header/SLA → `TK-013` tabs → `TK-014` read the conversation (**attachments `GL-001`, links/images `GL-002`**) → `TK-015` reply/copy on a bubble → `TK-016` reply or internal note (canned/FAQ, attachments via `GL-006`) → act via the `TK-019` ⋮ menu: `TK-020` status/mark, `TK-021` assign/claim/release/owner/refer, `TK-022` priority/topic/due/fields/tags, `TK-023` link/merge, `TK-024` collaborators, `TK-025` ban, `TK-034` **create task from ticket**, `TK-026` delete → all gated by `TK-027` permissions. `TK-017` Details tab, `TK-018` Activity tab.

### Flow 5 — Create a ticket
`NV-002` center **+** → New ticket → `TK-028` required fields → `TK-029` requester + collaborators (**user picker `GL-006`**) → `TK-030` message + canned/FAQ + attachments → `TK-031` properties → `TK-032` internal note → `TK-033` submit → lands on the new ticket.

### Flow 6 — Bulk actions & export (tickets)
`TK-007` long-press to multi-select → `TK-008` bulk claim/assign/status/priority/delete → `TK-009` export PDF/Excel.

### Flow 7 — Tasks (mirrors tickets, plus task-only bits)
`TS-001…TS-010` list → `TS-011…TS-016` detail + composer → `TS-017` details → **`TS-018` subtasks**, **`TS-019` dependencies (blocked state)** → `TS-020` activity → `TS-021` menu, `TS-022` close/reopen, `TS-023` assign/transfer/priority, `TS-024` collaborators, `TS-025` tags, `TS-026` permissions → `TS-027…TS-030` create task (incl. parent task + ticket link from `TK-034`).

### Flow 8 — Notifications
`NV-001` Inbox tab (unread badge, **push `GL-003`**) → `NT-001` inbox + tabs + search → `NT-002` grouped card → `NT-003` tap to open the ticket/task → `NT-004` swipe mark-read / delete → `NT-005` mark-all / delete-all.

### Flow 9 — Directory & records (reached from More)
`MO-002` menu → **Users** `US-001…US-007` (list, create, detail, tickets/notes tabs, account actions) · **Organizations** `OR-001…OR-008` (list, create, detail, members/tickets/notes, edit/delete) · **Agent Directory** `AG-001/AG-002`.

### Flow 10 — Resources (reached from More)
**Knowledgebase** `FQ-001…FQ-004` (browse categories / search / article) · **Canned Responses** `CR-001…CR-004` (list, view+copy, create/edit, delete) · **Saved Queues** `QU-001…QU-005` (list, card, create/rename, delete, results) · **Reports** `RP-001…RP-006`.

### Flow 11 — Account & settings
`MO-001` profile header → **Profile** `PR-001…PR-005` (availability, edit profile, change password, regenerate avatar) · `MO-003` theme toggle · `MO-004` sign out · **Server settings** `ST-001…ST-004` (URL + validation, test, save, reset).

### Flow 12 — Always-on / cross-cutting (verify throughout)
`GL-004` offline banner appears when the device drops connection · `GL-003` a push arrives and its tap deep-links to the object · `GL-001` attachments open (image/PDF/video/text/download) · `GL-002` links/images in messages are tappable · `GL-007` every list has skeleton/scroll/pull-refresh/retry/empty · `GL-009` tapping outside a field dismisses the keyboard · `GL-008` an expired session forces sign-out to Login.

---

## Full case index

**GL — Global & Shared Flows**
- GL-001 Attachment viewer · GL-002 Tappable links & inline images · GL-003 Push notifications · GL-004 App-wide offline banner · GL-005 Filter & Sort sheet · GL-006 Shared pickers · GL-007 Shared paginated list behaviour · GL-008 Session expiry → forced sign-out · GL-009 Keyboard dismissal on outside tap

**AU — Authentication**
- AU-001 Splash while session restores · AU-002 Auth-aware routing guard · AU-003 Login screen contents · AU-004 Username/email field · AU-005 Password field + show/hide · AU-006 Remember me (username only) · AU-007 Forgot-password link · AU-008 Sign in button busy state · AU-009 Sign in submit/validation/errors · AU-010 Login footer help text · AU-011 Forgot: request stage · AU-012 Forgot: email-sent stage · AU-013 Forgot: code + new password · AU-014 Forgot: done · AU-015 Forgot: back navigation

**NV — Navigation Shell**
- NV-001 Bottom navigation tabs · NV-002 Center create button + speed-dial · NV-003 Shell lifecycle

**DB — Dashboard**
- DB-001 Structure/load/states · DB-002 Greeting header + profile entry · DB-003 Tickets tiles + chips · DB-004 Needs attention · DB-005 Overview volume + chart · DB-006 Tasks tiles + chips · DB-007 Breakdown charts

**TK — Tickets**
- TK-001 Filter tabs + counts · TK-002 Live search · TK-003 Filter & sort sheet · TK-004 Row content · TK-005 Layout toggle · TK-006 Pagination + empty · TK-007 Multi-select · TK-008 Bulk actions · TK-009 Export · TK-010 Open / cross-tab request · TK-011 Detail load/states · TK-012 Header + SLA · TK-013 Tabs · TK-014 Conversation · TK-015 Bubble actions · TK-016 Reply/note composer · TK-017 Details tab · TK-018 Activity tab · TK-019 Action menu (gated) · TK-020 Status / mark · TK-021 Assignment actions · TK-022 Attribute edits · TK-023 Link/merge · TK-024 Collaborators · TK-025 Ban email · TK-026 Delete · TK-027 Permission gating · TK-028 Create: structure · TK-029 Create: requester/cc · TK-030 Create: message/attachments · TK-031 Create: properties · TK-032 Create: internal note · TK-033 Create: submit · TK-034 Create task from ticket

**TS — Tasks**
- TS-001 Filter tabs + counts · TS-002 Live search · TS-003 Filter & sort sheet · TS-004 Row content · TS-005 Layout toggle · TS-006 Pagination + empty · TS-007 Multi-select · TS-008 Bulk actions · TS-009 Export · TS-010 Open / cross-tab request · TS-011 Detail load/states · TS-012 Header (progress/blocked) · TS-013 Tabs · TS-014 Conversation · TS-015 Bubble actions · TS-016 Reply/note composer · TS-017 Details tab · TS-018 Subtasks · TS-019 Dependencies · TS-020 Activity tab · TS-021 Action menu (gated) · TS-022 Close/reopen · TS-023 Assign/transfer/priority · TS-024 Collaborators · TS-025 Tags · TS-026 Permission gating · TS-027 Create: structure · TS-028 Create: description/attachments · TS-029 Create: properties · TS-030 Create: submit

**NT — Notifications**
- NT-001 Inbox list/tabs/search · NT-002 Grouped card · NT-003 Open notification · NT-004 Swipe mark-read/delete · NT-005 Bulk menu

**RP — Reports**
- RP-001 Screen/load/states · RP-002 Day-range selector · RP-003 Opened/Closed/Net · RP-004 Per-day averages · RP-005 Activity chart card · RP-006 Line-chart rendering

**OR — Organizations**
- OR-001 List · OR-002 Create · OR-003 Detail/header/states · OR-004 Tabs · OR-005 Members tab · OR-006 Tickets tab · OR-007 Notes tab · OR-008 Edit/delete

**US — Users**
- US-001 List · US-002 Create · US-003 Detail/header/states · US-004 Tabs · US-005 Tickets tab · US-006 Notes tab · US-007 Account actions

**AG — Agents**
- AG-001 Directory list · AG-002 Agent profile sheet

**QU — Saved Queues**
- QU-001 List + type filter · QU-002 Queue card · QU-003 Create/rename · QU-004 Delete · QU-005 Queue results

**CR — Canned Responses**
- CR-001 List · CR-002 Detail sheet + copy · CR-003 Create/edit · CR-004 Delete

**FQ — Knowledgebase**
- FQ-001 Browse vs search · FQ-002 Category browse · FQ-003 Search results · FQ-004 Article detail

**PR — Profile**
- PR-001 Screen/header · PR-002 Availability toggle · PR-003 Edit profile · PR-004 Change password · PR-005 Regenerate avatar

**MO — More**
- MO-001 Menu + profile header · MO-002 Workspace/Resources menu · MO-003 Theme toggle · MO-004 Sign out

**ST — Settings**
- ST-001 Server URL + status · ST-002 Test connection · ST-003 Save server · ST-004 Reset to default

---

## Notes for testers

- **Permissions:** ticket/task actions are gated per department (`TK-027`, `TS-026`). Test with agents of different roles — actions the agent can't perform are hidden, not just disabled.
- **Server-fetch vs client-side:** list search/sort filter the already-fetched rows; changing tabs/filters re-fetches from the server. Watch the Network tab to confirm.
- **Where "New ticket / New task" lives:** the center **+** on the bottom nav (`NV-002`), not inside the lists.
- **The More tab** is reached from the Dashboard header avatar, not the bottom bar (`DB-002`, `NV-001`).
- **Cross-module reuse:** whenever a BRD says "see GL-00N", the shared behaviour is specified once in the GL BRD.
