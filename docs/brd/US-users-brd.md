# Business Requirements Document — Users

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Users **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Users — Business Requirements Document |
| Module Scope | The Users (end-user / requester directory) surfaces of the Staff Portal: the **Users list** (search, pagination, create), and the **User detail** screen (header with the user's contact details, the Tickets / Notes tabs, and the account actions — edit, clear organization, register / lock / unlock / reset-password, delete). This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/users/users_list_screen.dart`, `lib/features/users/user_detail_screen.dart`, `lib/models/user.dart` |

---

## 6. Functional Requirements

### 6.1 US-001 — Users list

| Field | Value |
|-------|-------|
| Description | The Users list shows every end user, searchable and paginated, each row summarising email and organization. |
| Acceptance Criteria | - The app bar title reads **Users** with the total count shown below it as "N total"<br>- A search box with the placeholder **Search users** narrows the list; the search applies on **submit** (not on every keystroke), and clearing it restores the full list<br>- The list is paginated (fetches further pages as the user scrolls)<br>- Each row shows the user's **name**, avatar, and a subtitle of the **email**, or **"{email} · {organization}"** when the user belongs to an organization<br>- Tapping a row opens that user's detail screen (US-003)<br>- When there are no users (or none match the search), an empty state reading **No users** with the hint **Try a different search.** is shown<br>- A floating action button opens the create-user sheet (US-002) |
| Priority | High |

### 6.2 US-002 — Create user

| Field | Value |
|-------|-------|
| Description | A sheet creates a new user with a name, email, and optional phone. |
| Acceptance Criteria | - The sheet is titled **New user** and shows **Name** (auto-focused), **Email**, and **Phone (optional)** fields, using the appropriate keyboards for email and phone<br>- The **Create user** button submits; while saving it shows a busy indicator<br>- On success the sheet closes, a toast reads **User created**, and the list refreshes<br>- On an API error with field errors, each is shown inline under its field (name, email, phone); a general error is shown below the fields |
| Priority | Medium |

### 6.3 US-003 — User detail: load, header, and states

| Field | Value |
|-------|-------|
| Description | Opening a user loads their record and shows a header of their contact details above the tabs. |
| Acceptance Criteria | - The app bar shows the user's name (or **User** until loaded) and an overflow menu of account actions (US-007)<br>- While loading, a loading view is shown; on failure an error view with **retry** is shown<br>- The header shows the user's avatar, **name**, **email**, **phone** (when present), and their **organization** (when present)<br>- When the user has custom fields, each is shown as a labelled key/value row below the contact block |
| Priority | High |

### 6.4 US-004 — User detail tabs

| Field | Value |
|-------|-------|
| Description | The detail body is organised into two tabs. |
| Acceptance Criteria | - Two tabs are shown in this order: **Tickets**, **Notes**, selectable by tap or swipe<br>- Each tab loads its own content (US-005, US-006) |
| Priority | Medium |

### 6.5 US-005 — Tickets tab

| Field | Value |
|-------|-------|
| Description | The Tickets tab lists the tickets belonging to the user. |
| Acceptance Criteria | - The tab shows a paginated list of the user's tickets as ticket cards<br>- Tapping a ticket opens that ticket's detail screen<br>- A user with no tickets shows **No tickets** |
| Priority | Medium |

### 6.6 US-006 — Notes tab

| Field | Value |
|-------|-------|
| Description | The Notes tab lists internal staff notes on the user and lets an agent add or delete notes. |
| Acceptance Criteria | - The tab loads and lists the user's notes, each showing the note body and a line of **"{staff name} · {relative time}"**; a loading view and an error view with retry are shown as appropriate<br>- An input at the bottom with placeholder **Add a note…** and a send button adds a note; an empty note is ignored; while adding, a busy indicator is shown<br>- On a successful add, the input clears and the list reloads<br>- Swiping a note row from right to left deletes it (reloading the list); failures show an error toast<br>- A user with no notes shows **No notes** |
| Priority | Medium |

### 6.7 US-007 — Account actions (edit, organization, account state, delete)

| Field | Value |
|-------|-------|
| Description | The overflow menu edits the user, clears their organization, performs account-state actions, or deletes the user. |
| Acceptance Criteria | - The menu offers, in order: **Edit**, **Clear organization**, then **Register account**, **Lock account**, **Unlock account**, **Reset password**, then **Delete**<br>- **Edit** opens a sheet titled **Edit user** pre-filled with the current **Name**, **Email**, and **Phone**; **Save changes** submits (busy indicator while saving); on success the sheet closes, a toast reads **User updated**, and the detail reloads; field errors are shown inline (name, email, phone) with a general error below<br>- **Clear organization** removes the user's organization link, shows a toast **Organization cleared**, and reloads (server error shown as a toast on failure)<br>- **Register account**, **Lock account**, **Unlock account**, and **Reset password** each run the corresponding account action and show the server's result as a toast (or the server error on failure)<br>- **Delete** shows a confirmation reading **Delete user?** with the message **This cannot be undone.** and a destructive **Delete** confirm; on confirm the user is deleted, a toast reads **User deleted**, and the screen closes back to the list (server error shown as a toast on failure) |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
