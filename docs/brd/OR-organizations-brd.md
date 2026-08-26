# Business Requirements Document — Organizations

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Organizations **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Organizations — Business Requirements Document |
| Module Scope | The Organizations surfaces of the Staff Portal: the **Organizations list** (search, pagination, create), and the **Organization detail** screen (header with organization attributes and flags, and the Members / Tickets / Notes tabs, plus edit and delete). This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/organizations/orgs_list_screen.dart`, `lib/features/organizations/org_detail_screen.dart`, `lib/models/organization.dart` |

---

## 6. Functional Requirements

### 6.1 OR-001 — Organizations list

| Field | Value |
|-------|-------|
| Description | The Organizations list shows every organization, searchable and paginated, each row summarising its user count and domain. |
| Acceptance Criteria | - The app bar title reads **Organizations** with the total count shown below it as "N total"<br>- A search box with the placeholder **Search organizations** narrows the list; the search applies on **submit** (not on every keystroke), and clearing it restores the full list<br>- The list is paginated (fetches further pages as the user scrolls)<br>- Each row shows the organization **name** and a subtitle of **"{N} users"**, or **"{N} users · {domain}"** when the organization has a domain<br>- Tapping a row opens that organization's detail screen (OR-003)<br>- When there are no organizations (or none match the search), an empty state reading **No organizations** with the hint **Try a different search.** is shown<br>- A floating action button opens the create-organization sheet (OR-002) |
| Priority | High |

### 6.2 OR-002 — Create organization

| Field | Value |
|-------|-------|
| Description | A sheet creates a new organization with a required name and an optional domain. |
| Acceptance Criteria | - The sheet is titled **New organization** and shows a **Name** field (auto-focused) and a **Domain (optional)** field with placeholder **example.com**<br>- The **Create organization** button submits; while saving it shows a busy indicator<br>- On success the sheet closes, a toast reads **Organization created**, and the list refreshes<br>- On an API error with field errors, each is shown inline under its field (name, domain); a general error is shown below the fields<br>- The domain is only sent when non-empty |
| Priority | Medium |

### 6.3 OR-003 — Organization detail: load, header, and states

| Field | Value |
|-------|-------|
| Description | Opening an organization loads its record and shows a header of its attributes and flags above the tabs. |
| Acceptance Criteria | - The app bar shows the organization name (or **Organization** until loaded) and an overflow menu with **Edit** and **Delete** (OR-008)<br>- While loading, a loading view is shown; on failure an error view with **retry** is shown<br>- The header shows the organization **name** and, for each present value, a labelled row for **Domain**, **Manager**, **Sharing**, and **Members** (count); rows with no value are omitted<br>- Flag chips are shown for the organization's enabled flags: **Collab all**, **Collab primary**, and **Auto-assign** (only those that are enabled)<br>- When the organization has custom fields, each is shown as a labelled key/value row below a divider |
| Priority | High |

### 6.4 OR-004 — Organization detail tabs

| Field | Value |
|-------|-------|
| Description | The detail body is organised into three tabs. |
| Acceptance Criteria | - Three tabs are shown in this order: **Members**, **Tickets**, **Notes**, selectable by tap or swipe<br>- Each tab loads its own content (OR-005, OR-006, OR-007) |
| Priority | Medium |

### 6.5 OR-005 — Members tab

| Field | Value |
|-------|-------|
| Description | The Members tab lists the organization's users, opens a user, and lets an agent remove a member by swiping. |
| Acceptance Criteria | - The tab shows a paginated list of member users, each row showing the user's **name**, **email**, and avatar<br>- Tapping a member opens that user's detail screen<br>- Swiping a member row from right to left removes them from the organization; on failure an error toast is shown<br>- An empty organization shows **No members** |
| Priority | High |

### 6.6 OR-006 — Tickets tab

| Field | Value |
|-------|-------|
| Description | The Tickets tab lists the organization's tickets. |
| Acceptance Criteria | - The tab shows a paginated list of the organization's tickets as ticket cards<br>- Tapping a ticket opens that ticket's detail screen<br>- An organization with no tickets shows **No tickets** |
| Priority | Medium |

### 6.7 OR-007 — Notes tab

| Field | Value |
|-------|-------|
| Description | The Notes tab lists internal staff notes on the organization and lets an agent add or delete notes. |
| Acceptance Criteria | - The tab loads and lists the organization's notes, each showing the note body and a line of **"{staff name} · {relative time}"**; a loading view and an error view with retry are shown as appropriate<br>- An input at the bottom with placeholder **Add a note…** and a send button adds a note; an empty note is ignored; while adding, a busy indicator is shown<br>- On a successful add, the input clears and the list reloads<br>- Swiping a note row from right to left deletes it (reloading the list); failures show an error toast<br>- An organization with no notes shows **No notes** |
| Priority | Medium |

### 6.8 OR-008 — Edit / delete organization

| Field | Value |
|-------|-------|
| Description | The overflow menu edits the organization's name and domain or deletes it. |
| Acceptance Criteria | - **Edit** opens a sheet titled **Edit organization** pre-filled with the current **Name** and **Domain**; **Save changes** submits (busy indicator while saving)<br>- On a successful edit the sheet closes, a toast reads **Organization updated**, and the detail reloads<br>- Edit field errors are shown inline under their field (name, domain); a general error is shown below<br>- **Delete** shows a confirmation reading **Delete organization?** with the message **This cannot be undone.** and a destructive **Delete** confirm<br>- On confirm, the organization is deleted, a toast reads **Organization deleted**, and the screen closes back to the list; on failure the server error is shown as a toast |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
