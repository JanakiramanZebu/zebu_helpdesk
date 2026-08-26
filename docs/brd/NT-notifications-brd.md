# Business Requirements Document — Notifications

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Notifications (Inbox) **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Notifications — Business Requirements Document |
| Module Scope | The agent's notification **Inbox**: the notification feed grouped per ticket/task, filter tabs, live search, per-card open / mark-read / delete swipe actions, and the bulk mark-all-read / delete-all menu. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/notifications/notifications_screen.dart`, `lib/models/app_notification.dart` |

---

## 6. Functional Requirements

### 6.1 NT-001 — Inbox list, filter tabs, and search

| Field | Value |
|-------|-------|
| Description | The Inbox lists the agent's notifications collapsed into one card per ticket/task, with filter tabs, a live search, infinite scroll, and loading / empty states. |
| Acceptance Criteria | - The app bar title reads **Inbox**; when there are conversations it shows a count below as "N conversation(s)"<br>- Filter tabs are shown in this order: **All**, **Unread**, **Tickets**, **Tasks**, **Mentions**; the **Unread** tab carries the live unread count as a badge<br>- Selecting a tab filters the feed client-side: Unread → objects with any unread activity, Tickets → ticket objects, Tasks → task objects, Mentions → objects with a "mention" event, All → everything<br>- A search box with the placeholder **Search notifications** filters live (debounced ~250 ms) by object id, activity label, or actor name (case-insensitive)<br>- The feed loads pages progressively and keeps pulling pages when a filter hides most of a page (until a screenful of cards or no more)<br>- While the first page loads, a loading skeleton is shown; on error (with no data) an error view with **retry** is shown<br>- When there are no matching notifications, an empty state reading **No notifications** with the hint **You are all caught up.** is shown<br>- The feed supports pull-to-refresh |
| Priority | High |

### 6.2 NT-002 — Grouped notification card

| Field | Value |
|-------|-------|
| Description | Each card collapses all of the agent's notifications for a single ticket/task, showing the latest activity and how many were collapsed. |
| Acceptance Criteria | - Each card shows the object reference (**Ticket #N** or **Task #N**), the latest activity message, and the latest activity's relative time<br>- A card with any unread activity is visually marked as unread (an unread rail and emphasised text)<br>- When more than one activity is collapsed, an **"N updates"** pill is shown<br>- An event chip is shown for the latest activity's type, mapped as: message→**Reply**, note→**Note**, assigned→**Assigned**, transfer→**Transferred**, status→**Status**, mention→**Mention**, overdue→**Overdue**, new_unassigned→**Unassigned**<br>- The actor's name is shown when present |
| Priority | Medium |

### 6.3 NT-003 — Opening a notification

| Field | Value |
|-------|-------|
| Description | Tapping a card marks the whole object's notifications read and opens the ticket or task. |
| Acceptance Criteria | - Tapping a card marks all of the agent's notifications for that object as read (server-side) and refreshes the unread count<br>- The app then navigates to the object — the task detail for a task card, the ticket detail for a ticket card<br>- On returning from the detail, the feed refreshes so the card's unread state is cleared<br>- If the mark-read call fails, navigation still proceeds |
| Priority | High |

### 6.4 NT-004 — Swipe actions (mark read / delete)

| Field | Value |
|-------|-------|
| Description | Cards can be swiped to mark all of the object's notifications read or to delete them. |
| Acceptance Criteria | - Swiping a card **right** marks all of that object's notifications read in place (the card is not removed); this direction is available only when the card has unread activity<br>- Swiping a card **left** deletes all of that object's notifications; the card is removed immediately (optimistically) and the deletes are sent to the server<br>- If a delete fails, the rows are restored and an error toast is shown<br>- After a mark-read or delete, the unread count is refreshed |
| Priority | Medium |

### 6.5 NT-005 — Inbox bulk menu

| Field | Value |
|-------|-------|
| Description | An overflow menu marks the whole inbox read or deletes all notifications. |
| Acceptance Criteria | - The app-bar overflow menu offers **Mark all read** and **Delete all** (destructive)<br>- **Mark all read** marks every notification read and refreshes the feed and unread count<br>- **Delete all** first shows a confirmation reading **Delete all notifications?** with the message **This cannot be undone.** and a **Delete all** confirm; on confirm it deletes everything and refreshes<br>- Failures show an error toast |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
