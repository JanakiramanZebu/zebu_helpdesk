# Business Requirements Document — Global & Shared Flows

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Global & Shared Flows **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Global & Shared Flows — Business Requirements Document |
| Module Scope | The app-wide and cross-module behaviours that are re-used across many screens rather than owned by one feature: the **attachment viewer**, tappable links/images in message HTML, **push notifications**, the app-wide **offline banner**, the shared **Filter & Sort sheet**, the shared **pickers**, the shared **paginated list** contract, **session expiry**, and app-wide keyboard dismissal. Other BRDs reference these cases instead of re-specifying them. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/widgets/attachment_viewer.dart`, `lib/widgets/attachment_tile.dart`, `lib/widgets/thread_html.dart`, `lib/core/push/push_service.dart`, `lib/widgets/offline_banner.dart`, `lib/app.dart`, `lib/widgets/filter_sheet.dart`, `lib/widgets/pickers.dart`, `lib/widgets/paged_list_view.dart`, `lib/core/auth/auth_controller.dart` |

---

## 6. Functional Requirements

### 6.1 GL-001 — Attachment viewer

| Field | Value |
|-------|-------|
| Description | Tapping an attachment (in a ticket/task conversation, an FAQ article, or a canned response) opens it in the best in-app viewer for its type; unpreviewable types are downloaded and opened with the device's default app. All bytes are fetched through the authenticated API. |
| Acceptance Criteria | - Each attachment is shown as a row with its file-type icon (or an inline thumbnail for images), its name, and its size (when known)<br>- Tapping an attachment opens it by type:<br>  • **Image** → a fullscreen pinch-to-zoom viewer<br>  • **PDF** → an in-app PDF reader (scroll + pinch-zoom)<br>  • **Video** → an in-app video player<br>  • **Text / source code** → an in-app monospaced, selectable text viewer<br>  • **Any other type** → the file bytes are downloaded (showing an "Opening {name}…" progress toast) and opened with the OS default app; if no app can open it, a toast reads **No app found to open {name}**<br>- Every viewer shows a loading indicator while fetching, and an error state with **Retry** if the fetch fails<br>- Every viewer has an **Open externally** action that launches the file's URL in an external app/browser<br>- Image thumbnails in the tile load the authed bytes, falling back to a type icon while loading or on error<br>- On a failed download/open, a toast reads **Couldn't open {name}** |
| Priority | High |

### 6.2 GL-002 — Tappable links and inline images in message HTML

| Field | Value |
|-------|-------|
| Description | Message bodies rendered from HTML (ticket/task conversation entries) make links and inline images interactive. |
| Acceptance Criteria | - Tapping a link inside a message body opens it in an in-app browser view, falling back to the system browser if that is unavailable<br>- Tapping an inline image inside a message body opens it in the fullscreen image viewer (GL-001) |
| Priority | Medium |

### 6.3 GL-003 — Push notifications

| Field | Value |
|-------|-------|
| Description | The app registers for push notifications after sign-in, shows incoming alerts, and routes a tapped notification to the relevant ticket or task. The whole pipeline no-ops gracefully when push is not configured. |
| Acceptance Criteria | - On first reaching the main app (post-authentication), the OS "Allow notifications" permission is requested and the device's push token is registered with the backend<br>- The token is re-registered if it refreshes; on sign-out the device is unregistered from the backend before local credentials are cleared<br>- A notification arriving while the app is **foregrounded** is shown as a local notification and immediately refreshes the unread badge count<br>- Tapping a notification opens the referenced object — the **task** detail for a task notification, otherwise the **ticket** detail — whether the app was foregrounded, backgrounded, or launched cold by the tap<br>- When push is not configured (no Firebase config present), none of the above runs and the app behaves normally without notifications |
| Priority | High |

### 6.4 GL-004 — App-wide offline banner

| Field | Value |
|-------|-------|
| Description | A connectivity strip appears above every screen when the device is offline. |
| Acceptance Criteria | - When the device is positively known to be **offline**, a strip reading **No internet connection** is shown above the current screen content on every screen<br>- The strip is hidden when connectivity is up (or while connectivity is still being determined)<br>- The strip does not block interaction with the screen below it |
| Priority | Medium |

### 6.5 GL-005 — Filter & Sort sheet

| Field | Value |
|-------|-------|
| Description | The shared sheet opened from a list's filter button, used by the Tickets and Tasks lists. It edits a draft selection and applies it only on Apply. |
| Acceptance Criteria | - The list search bar's trailing **filter button** shows a small dot when any filter is active; tapping it opens the **Filters** sheet<br>- The sheet has a **Create date** section (a single-select chip row of date-range presets), a **Sort by** section (a single-select chip row of the list's sort options), and one section per available facet<br>- A facet with a short option list (≤ 6 options) renders as a single-select chip row including an **All** chip; a facet with a long option list renders as a tappable selector that expands an inline **searchable** dropdown (with an "All …" option and a "No matches" state)<br>- The sheet edits a **draft** — nothing on the list changes until **Apply** is pressed<br>- A **Reset** action (shown only when the draft differs from defaults) clears the draft back to defaults (all dates, default sort, no facets) without closing the sheet<br>- **Apply** closes the sheet and returns the chosen date range, sort, and facet selections to the list (which then re-fetches); dismissing without Apply changes nothing<br>- Only facets whose options actually loaded are shown |
| Priority | High |

### 6.6 GL-006 — Shared pickers

| Field | Value |
|-------|-------|
| Description | The reusable bottom-sheet pickers invoked from across the app for choosing a user, a meta value, or an attachment source. |
| Acceptance Criteria | - **User picker** — a sheet titled **Select requester** with a search box (**Search by name or email**) that queries users (debounced), showing a loading spinner, an error state with retry, or **No users found**; tapping a result returns that user. (Used by create-ticket requester, Change owner, Add collaborator.)<br>- **Meta picker** — a sheet listing the options of a meta kind (departments, priorities, statuses, agents, teams, topics, tags), highlighting the current selection; long lists (> 8) show a search field; tapping an option returns it<br>- **Attachment-source chooser** — a sheet offering **Camera**, **Photo**, and **File**; the chosen source is used to pick attachment(s) with their bytes ready to upload<br>- **Canned / FAQ inserters** — pickers that return the chosen canned response / FAQ article to insert into a composer or message field |
| Priority | Medium |

### 6.7 GL-007 — Shared paginated list behaviour

| Field | Value |
|-------|-------|
| Description | The common contract every paginated list screen inherits (Tickets, Tasks, Organizations, Users, Canned, FAQ search, org/user tickets & members, queue results). |
| Acceptance Criteria | - The first load shows a loading skeleton in place of rows<br>- Further pages are fetched and appended as the user scrolls (infinite scroll), until the server has no more<br>- The list supports pull-to-refresh<br>- A fetch error shows an error state with a **retry** action<br>- When there are no rows, a typed empty state (message + optional hint/icon supplied by the host screen) is shown |
| Priority | Medium |

### 6.8 GL-008 — Session expiry → forced sign-out

| Field | Value |
|-------|-------|
| Description | When the session can no longer be refreshed, the app signs the agent out and returns to login. |
| Acceptance Criteria | - When the API determines the session cannot be refreshed (expired/invalid), local credentials are cleared and the auth state becomes unauthenticated<br>- The routing guard then redirects the agent to the Login screen (protected routes are no longer reachable) |
| Priority | High |

### 6.9 GL-009 — Keyboard dismissal on outside tap

| Field | Value |
|-------|-------|
| Description | Tapping outside a focused input dismisses the keyboard, consistently across the whole app. |
| Acceptance Criteria | - Tapping anywhere outside a focused text field removes focus and dismisses the on-screen keyboard, on every screen<br>- The dismiss tap does not consume taps intended for buttons or list items below it |
| Priority | Low |

---

*Document in progress — additional cases added after individual approval.*
