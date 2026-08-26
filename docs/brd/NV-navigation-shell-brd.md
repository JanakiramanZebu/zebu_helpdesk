# Business Requirements Document — Navigation Shell

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Navigation Shell **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Navigation Shell — Business Requirements Document |
| Module Scope | The app's bottom-navigation shell: the four primary tabs, the raised center "create" button and its speed-dial, the Inbox unread badge, and the tab-switching behaviour. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/shell/home_shell.dart`, `lib/features/shell/widgets/floating_nav_bar.dart` |

---

## 6. Functional Requirements

### 6.1 NV-001 — Bottom navigation tabs

| Field | Value |
|-------|-------|
| Description | The shell hosts a bottom navigation bar with four destinations and reveals the currently active branch content above it. |
| Acceptance Criteria | - The bottom bar shows four tabs in this order: **Home**, **Tickets**, **Tasks**, **Inbox**<br>- Tapping a tab switches to that branch and marks it selected; the branch content is shown above the bar<br>- The **Inbox** tab shows a red unread-count badge when there are unread notifications (showing **99+** above 99); the badge is hidden when the count is zero<br>- The fifth destination (**More**) is not on the bar — it is reached from the Dashboard header (see the More module)<br>- Re-tapping the already-active tab resets that branch to its initial location |
| Priority | High |

### 6.2 NV-002 — Center create button and speed-dial

| Field | Value |
|-------|-------|
| Description | A raised "+" button at the center of the bar opens a speed-dial to create a new ticket or task; it does not switch tabs. |
| Acceptance Criteria | - A raised **+** button sits at the center of the bar between the Tickets and Tasks tabs<br>- Tapping it opens a small popup above the button offering **New ticket** and **New task**, over a tap-to-dismiss scrim; tapping the button again (or the scrim) closes the popup<br>- Choosing **New ticket** opens the create-ticket screen; choosing **New task** opens the create-task screen<br>- The create button does not change the selected tab |
| Priority | High |

### 6.3 NV-003 — Shell lifecycle

| Field | Value |
|-------|-------|
| Description | Reaching the shell means the agent is authenticated, so push notifications are initialised. |
| Acceptance Criteria | - On first reaching the shell (post-authentication), the push-notification service is started (permission prompt + token registration); this is a no-op when push is not configured<br>- The four branches retain their own state as the user switches between tabs |
| Priority | Low |

---

*Document in progress — additional cases added after individual approval.*
