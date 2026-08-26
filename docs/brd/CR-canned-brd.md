# Business Requirements Document — Canned Responses

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Canned Responses **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Canned Responses — Business Requirements Document |
| Module Scope | The Canned Responses (saved replies) surfaces: the list, the response detail sheet with copy, and the create / edit / delete flows. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/canned/canned_screen.dart`, `lib/models/canned.dart` |

---

## 6. Functional Requirements

### 6.1 CR-001 — Canned responses list

| Field | Value |
|-------|-------|
| Description | The screen lists the saved canned responses as cards, paginated, with a create action and per-card edit/delete menu. |
| Acceptance Criteria | - The app bar title reads **Canned Responses**<br>- The list is paginated (fetches further pages as the user scrolls)<br>- Each card shows the response **title** and a two-line plain-text preview of the body; a **Disabled** chip is shown when the response is not enabled and a **Global** chip when it is global<br>- Each card has an overflow menu with **Edit** and **Delete**<br>- Tapping a card opens its detail sheet (CR-002)<br>- When there are no responses, an empty state reading **No canned responses** is shown<br>- A floating action button opens the create editor (CR-003) |
| Priority | High |

### 6.2 CR-002 — Response detail sheet

| Field | Value |
|-------|-------|
| Description | Tapping a response opens a sheet showing its full body, notes, attachments, and a copy action. |
| Acceptance Criteria | - The sheet is titled with the response title and shows the full response body (rendered from its HTML)<br>- When the response has notes, a **Notes** section shows them<br>- When the response has attachments, an **Attachments** section lists them (they open in the shared attachment viewer — see Global BRD, GL-001)<br>- A **Copy** button copies the response body as plain text to the clipboard, closes the sheet, and shows a **Copied** toast |
| Priority | Medium |

### 6.3 CR-003 — Create / edit response

| Field | Value |
|-------|-------|
| Description | A sheet creates a new response or edits an existing one, with a title, body, and enabled toggle. |
| Acceptance Criteria | - Creating opens a sheet titled **New canned response**; editing opens **Edit response** pre-filled with the current values<br>- The sheet shows a **Title** field, a multi-line **Response** field, and an **Enabled** toggle (on by default for a new response)<br>- The submit button reads **Create** when creating and **Save changes** when editing; it shows a busy indicator while saving<br>- On success the sheet closes and the list refreshes<br>- On an API error with field errors, each is shown inline under its field (title, response); a general error is shown as a toast |
| Priority | Medium |

### 6.4 CR-004 — Delete response

| Field | Value |
|-------|-------|
| Description | Delete a canned response. |
| Acceptance Criteria | - **Delete** shows a confirmation reading **Delete response?** with the message **Delete "{title}"? This cannot be undone.** and a destructive **Delete** confirm<br>- On confirm, the response is deleted, a toast reads **Deleted**, and the list refreshes<br>- On failure the server error is shown as a toast |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
