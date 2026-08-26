# Business Requirements Document — Queues

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Saved Queues **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Saved Queues — Business Requirements Document |
| Module Scope | The Saved Queues surfaces of the Staff Portal: the **Saved Queues list** (type filter, create, rename, delete) and the **Queue results** screen that lists the tickets or tasks belonging to a saved queue. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/queues/queues_screen.dart`, `lib/features/queues/queue_results_screen.dart`, `lib/models/saved_queue.dart` |

---

## 6. Functional Requirements

### 6.1 QU-001 — Saved Queues list and type filter

| Field | Value |
|-------|-------|
| Description | The Saved Queues screen lists the agent's saved ticket and task queues, filterable by type, with loading / error / empty / refresh handling and a create action. |
| Acceptance Criteria | - The app bar title reads **Saved Queues**<br>- A row of filter chips is shown: **All**, **Tickets**, **Tasks**; the selected chip filters the list to that type (All shows both), and changing the selection reloads the list<br>- While loading (and no prior data), a loading view is shown; on error (and no prior data) an error view with **retry** is shown<br>- When there are no queues, an empty state reading **No saved queues** is shown<br>- The list supports pull-to-refresh<br>- A floating action button opens the create-queue editor (QU-003) |
| Priority | High |

### 6.2 QU-002 — Queue card

| Field | Value |
|-------|-------|
| Description | Each queue is shown as a card summarising its type, name, visibility, and filter count, with actions available on editable queues. |
| Acceptance Criteria | - Each card shows an icon indicating whether the queue is a **task** or **ticket** queue, and the queue's **full name**<br>- A summary line shows the queue's visibility tags (**Public** and/or **Personal**) and, when it has criteria, a **"N filter(s)"** count (singular "filter" for one); the summary is omitted when there is nothing to show<br>- For an **editable** queue, a trailing overflow menu offers **Rename** and **Delete**; for a non-editable queue, a chevron is shown instead<br>- Tapping a card opens that queue's results (QU-005) |
| Priority | Medium |

### 6.3 QU-003 — Create / rename queue

| Field | Value |
|-------|-------|
| Description | A sheet creates a new personal queue or renames an existing editable queue. |
| Acceptance Criteria | - Creating opens a sheet titled **New personal queue** with a **Name** field and an optional **Search filter** field (placeholder **Keyword to match**); the create button reads **Create**<br>- Renaming opens a sheet titled **Rename queue** with only a **Name** field (pre-filled); the button reads **Save**<br>- The button shows a busy indicator while saving; on success the sheet closes and the list reloads<br>- On an API error with field errors, the name error is shown inline; a general error is shown as a toast<br>- Creating with a search filter stores it as the queue's criteria; an empty filter creates a queue with no criteria |
| Priority | Medium |

### 6.4 QU-004 — Delete queue

| Field | Value |
|-------|-------|
| Description | Delete an editable queue. |
| Acceptance Criteria | - **Delete** shows a confirmation reading **Delete queue?** with the message **Delete "{queue name}"? This cannot be undone.** and a destructive **Delete** confirm<br>- On confirm, the queue is deleted, a toast reads **Deleted**, and the list reloads<br>- On failure the server error is shown as a toast |
| Priority | Medium |

### 6.5 QU-005 — Queue results

| Field | Value |
|-------|-------|
| Description | Tapping a queue opens a screen listing the tickets or tasks that belong to it. Ticket queues are resolved server-side by queue id; task queues replay the queue's stored criteria. |
| Acceptance Criteria | - The results screen's app bar shows the queue's **full name**<br>- For a **ticket** queue, a paginated list of the queue's tickets is shown (resolved server-side by the queue id) using the standard ticket rows; tapping a row opens that ticket's detail<br>- For a **task** queue, a paginated list of tasks is shown by replaying the queue's stored criteria as query parameters using the standard task rows; tapping a row opens that task's detail<br>- An empty ticket queue shows **No tickets** with the hint **This queue has no matching tickets.**; an empty task queue shows **No tasks** with the hint **This queue has no matching tasks.**<br>- A loading skeleton is shown during the initial fetch |
| Priority | High |

---

*Document in progress — additional cases added after individual approval.*
