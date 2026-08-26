# Business Requirements Document — Dashboard

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Dashboard **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Dashboard — Business Requirements Document |
| Module Scope | The Dashboard (home) screen — the agent's landing overview. It covers the greeting header, the Tickets focus tiles and secondary count chips, the "Needs attention" overdue triage list, the Overview section (volume summary with an in-card day-range picker plus the activity chart, reused from Reports), the Tasks section, and the Breakdown bar charts (by priority / department / agent). Also covers the load / error / empty / refresh behaviour and every drill-down into a pre-filtered Tickets or Tasks list. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. The shared volume summary card and activity chart are specified in the Reports BRD (RP-003…RP-006); this document covers only their dashboard-specific wiring. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/dashboard/dashboard_screen.dart`, `lib/features/dashboard/widgets/{attention_row,count_chip_row,focus_strip,mini_bar_chart}.dart`, `lib/features/reports/widgets/{report_summary_card,activity_chart_card}.dart`, `lib/models/reports.dart` |

---

## 6. Functional Requirements

### 6.1 DB-001 — Dashboard: structure, data load, and states

| Field | Value |
|-------|-------|
| Description | The Dashboard loads a report summary and a volume report, then progressively fills in task counts and the attention list. It shows a skeleton during the initial load, an error view with retry on failure, and supports pull-to-refresh. |
| Acceptance Criteria | - On open, the screen fetches the report **summary** and the **volume** report (default 30-day window) together; while that initial fetch is in flight a dashboard-shaped loading skeleton is shown<br>- On success the body shows, in order: **Tickets** section (DB-003), **Needs attention** (DB-004), **Overview** (DB-005), **Tasks** section (DB-006, once its counts load), and **Breakdown** (DB-007, when data exists)<br>- After the summary/volume load, task counts (DB-006) and the attention list (DB-004) are fetched separately and fill in when ready; a failure of either leaves that section hidden / "caught up" rather than erroring the whole screen<br>- On a summary/volume fetch error, an error view with a **retry** action is shown; when the summary is missing entirely, an error view reading **No data** with retry is shown<br>- The screen is vertically scrollable and supports **pull-to-refresh**, which reloads everything |
| Priority | High |

### 6.2 DB-002 — Greeting header and profile/menu entry

| Field | Value |
|-------|-------|
| Description | A header greets the signed-in agent by first name and provides a profile avatar that opens the More menu. |
| Acceptance Criteria | - The header shows a greeting **Hi, <FirstName>** using the first word of the signed-in agent's name; when the name is unavailable it falls back to **Hi there**<br>- A subtitle reads exactly **Here's your helpdesk overview**<br>- A profile avatar (the agent's initials/avatar) is shown at the right; tapping it navigates to the **More** menu<br>- The header stays visible across the loading, populated, and error states |
| Priority | Medium |

### 6.3 DB-003 — Tickets focus tiles and count chips

| Field | Value |
|-------|-------|
| Description | The Tickets section presents the four ticket queue figures as two tappable focus tiles and two secondary count chips, each drilling into the matching pre-filtered Tickets tab. |
| Acceptance Criteria | - The section is headed **Tickets** with a **View all** action that opens the Tickets tab on the **Open** view<br>- Two focus tiles are shown: **Open** (open ticket count) and **All Tickets** (total ticket count)<br>- Two count chips are shown below: **My Tickets** (the agent's open tickets) and **Closed** (closed ticket count), each with its count<br>- Tapping **Open**, **All Tickets**, **My Tickets**, or **Closed** switches to the Tickets tab pre-filtered to that view (open / all / mine / closed respectively)<br>- All counts come from the report summary totals |
| Priority | High |

### 6.4 DB-004 — Needs attention (overdue triage)

| Field | Value |
|-------|-------|
| Description | A short "Needs attention" list surfaces the oldest overdue tickets for quick triage, with a loading, populated, and "all caught up" state. |
| Acceptance Criteria | - The section is headed **Needs attention**; a **View all** action (opening the Tickets **Open** view) is shown only when the list is non-empty<br>- The list is populated from the overdue tickets, oldest first, capped at 5<br>- While the list is loading, a placeholder (shimmer) panel is shown<br>- Each row shows the ticket **#number**, the **requester** (when present), the **subject**, and a right-aligned tag reading **Overdue** (for overdue tickets) or the ticket's age; a priority rail indicates priority<br>- Tapping a row opens that ticket's detail screen<br>- When there are no overdue tickets, a positive empty state is shown reading **All caught up** with **Nothing overdue right now — nice work.**<br>- If the attention fetch fails, the "all caught up" state is shown (the failure is not surfaced as an error) |
| Priority | High |

### 6.5 DB-005 — Overview: volume summary and activity chart

| Field | Value |
|-------|-------|
| Description | The Overview section reuses the volume summary card and the activity chart from Reports, but with an in-card day-range picker that reloads only the volume data (never the whole screen). |
| Acceptance Criteria | - The section is headed **Overview** and is shown once the volume report has loaded<br>- The volume summary card is shown with an **in-card day-range picker** offering **Last 7 / 30 / 90 days**, defaulting to 30; the card's Opened / Closed / Net metrics and per-day averages behave as specified in RP-003 and RP-004<br>- Changing the range in the picker reloads **only** the volume report for the new window (an inline loading indicator shows in the card) and does not flash the full-screen loader or reload the rest of the dashboard<br>- The **Ticket activity** chart card is shown below the summary and behaves as specified in RP-005 and RP-006 |
| Priority | High |

### 6.6 DB-006 — Tasks focus tiles and count chips

| Field | Value |
|-------|-------|
| Description | The Tasks section mirrors the Tickets section for tasks, appearing once task counts load, with tiles and chips that drill into the matching pre-filtered Tasks tab. |
| Acceptance Criteria | - The Tasks section is hidden until its counts have loaded; once loaded it is headed **Tasks** with a **View all** action that opens the Tasks tab on the **All** view<br>- Two focus tiles are shown: **Open** (open task count) and **All** (all task count)<br>- Two count chips are shown below: **Overdue** and **Completed**, each with its count<br>- Tapping **Open**, **All**, **Overdue**, or **Completed** switches to the Tasks tab pre-filtered to that view (open / all / overdue / closed respectively)<br>- The counts are fetched from the tasks list totals for those four views (there is no task report endpoint); if the fetch fails the whole Tasks section stays hidden |
| Priority | Medium |

### 6.7 DB-007 — Breakdown bar charts

| Field | Value |
|-------|-------|
| Description | A Breakdown section shows open-ticket distributions by priority, department, and (for admins) agent, each as a horizontal bar list. |
| Acceptance Criteria | - The Breakdown section is shown only when the summary contains at least one of the by-priority, by-department, or by-agent breakdowns; it is headed **Breakdown**<br>- **By priority** is shown (when present) as a bar list with one row per priority (open count)<br>- **By department** is shown (when present) as a bar list with one row per department (open count)<br>- **By agent** is shown (when present) as a bar list with one row per agent (open count), capped at the top 8; this breakdown is returned only for admins, so non-admins do not see the By-agent chart<br>- Each bar row shows the label, a proportional filled bar (sized against the largest value in that chart), and the numeric value; a chart with no data shows **No data** |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
