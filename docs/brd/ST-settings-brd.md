# Business Requirements Document — Settings (Server)

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Settings (Server) **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Server Settings — Business Requirements Document |
| Module Scope | The Server Settings screen, which re-points the app at a different helpdesk backend: the base-URL field with validation, the connectivity status, and the test / save / reset actions. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/settings/server_settings_screen.dart`, `lib/core/network/server_config.dart`, `lib/core/config.dart` |

---

## 6. Functional Requirements

### 6.1 ST-001 — Server URL field and status

| Field | Value |
|-------|-------|
| Description | The screen shows the current helpdesk base URL for editing, validates it, previews the resolved API dispatcher, and shows the device's connectivity. |
| Acceptance Criteria | - The app bar title reads **Server settings**<br>- A live status row shows **Device online** or **Device offline** reflecting current connectivity<br>- A **Helpdesk base URL** field is pre-filled with the currently saved server (hint **https://ticket.example.com**)<br>- The URL is validated: empty → **Enter a server URL**; unparseable/host-less → **Enter a valid URL (e.g. https://host:port)**; a scheme other than http/https → **URL must start with http:// or https://**<br>- Below the field, the resolved **API dispatcher** URL for the entered (or current) base URL is shown<br>- A note explains that changing the server signs the agent out and requires signing in again against the new backend |
| Priority | High |

### 6.2 ST-002 — Test connection

| Field | Value |
|-------|-------|
| Description | A test action checks whether the entered server is reachable. |
| Acceptance Criteria | - A **Test connection** button validates the URL first, then pings the entered server (forcing a fresh check)<br>- While testing, a busy indicator is shown<br>- On success a toast reads **Server is reachable**; on failure a toast reads **Could not reach {url}** |
| Priority | Medium |

### 6.3 ST-003 — Save server

| Field | Value |
|-------|-------|
| Description | Saving persists the new server and re-points the app at it. |
| Acceptance Criteria | - A **Save server** button validates the URL first, then persists it (the value survives app restarts)<br>- Saving rebuilds the API client so every subsequent request targets the new server<br>- On success a toast reads **Server updated. Sign in again to continue.**<br>- The Test/Save/Reset actions are disabled while a test or save is in flight |
| Priority | High |

### 6.4 ST-004 — Reset to default

| Field | Value |
|-------|-------|
| Description | A reset action restores the default server. |
| Acceptance Criteria | - A **Reset to default** action restores the built-in default server, rebuilds the API client, and repopulates the field with the default value<br>- On reset a toast reads **Reset to default server** |
| Priority | Low |

---

*Document in progress — additional cases added after individual approval.*
