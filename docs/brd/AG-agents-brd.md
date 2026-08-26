# Business Requirements Document — Agents

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Agents (Directory) **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Agents — Business Requirements Document |
| Module Scope | The Agent Directory — a read-only colleague directory listing the active agents, with a searchable list and a per-agent profile sheet (contact details, department, role, availability, and open-ticket count). This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/agents/agents_directory_screen.dart`, `lib/models/me.dart` |

---

## 6. Functional Requirements

### 6.1 AG-001 — Agent directory list

| Field | Value |
|-------|-------|
| Description | The Agent Directory lists the active agents, with a search box that filters the list live by name, and loading / error / empty / refresh handling. |
| Acceptance Criteria | - The app bar title reads **Agent Directory**<br>- The list is loaded from the agents meta list on open<br>- A search box with the placeholder **Search agents** filters the list **live as the user types** (matching the typed text against the agent name, case-insensitive); clearing it restores the full list<br>- Each row shows the agent's avatar, **name**, and a chevron indicating it is tappable<br>- Tapping a row opens that agent's profile sheet (AG-002)<br>- While loading, a loading view is shown; on failure an error view with **retry** is shown; when the (filtered) list is empty, an empty state reading **No agents found** is shown<br>- The list supports pull-to-refresh, which reloads the agents |
| Priority | High |

### 6.2 AG-002 — Agent profile sheet

| Field | Value |
|-------|-------|
| Description | Tapping an agent opens a bottom sheet that loads and shows that agent's full profile. |
| Acceptance Criteria | - The sheet opens and loads the agent's profile; a loading indicator is shown while fetching, and the server error message is shown if the load fails<br>- The sheet header shows the agent's avatar and **name**, with an availability indicator reading **Available** or **Unavailable**<br>- The profile shows, when present, labelled rows for **Email**, **Phone**, **Department**, and **Role**<br>- An **Open tickets** row always shows the agent's current open-ticket count<br>- Rows whose value is absent are omitted (Email/Phone/Department/Role are conditional; Open tickets is always shown) |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
