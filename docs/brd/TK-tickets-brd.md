# Business Requirements Document — Tickets

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Tickets **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Tickets — Business Requirements Document |
| Module Scope | The Tickets surfaces of the Staff Portal: the **Tickets list** (filter tabs, search, filter/sort, multi-select bulk actions, export, layout toggle, scroll pagination), the **Ticket detail** screen (collapsing header, Conversation / Details / Activity tabs, the reply/note composer, and the full ⋮ action set — status, mark, assign, claim, release, transfer, priority, topic, due date, edit fields, tags, refer, link, merge, collaborators, ban, delete), and the **Create ticket** screen. This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/tickets/tickets_list_screen.dart`, `lib/features/tickets/ticket_detail_screen.dart`, `lib/features/tickets/create_ticket_screen.dart`, `lib/features/tickets/widgets/{ticket_row,thread_entry_tile,dynamic_fields_section}.dart`, `lib/widgets/{entity_list_row,message_composer}.dart` |

---

## 6. Functional Requirements

### 6.1 TK-001 — Tickets list: filter tabs with per-tab counts

| Field | Value |
|-------|-------|
| Description | The Tickets list is organised into four filter tabs shown as a row of chips. Each chip carries a live count of matching tickets. Selecting a chip switches the list to that view; the tabs are also swipeable as pages. The app bar shows the title "Tickets" and the total count of the active view. |
| Acceptance Criteria | - Exactly four tabs are shown, in this left-to-right order: **Open**, **All Tickets**, **My Tickets**, **Closed**<br>- Each tab shows a count badge; counts are fetched per tab independently and a tab whose count fails to load simply shows no badge<br>- Tapping a chip makes it the active view and moves the pager to it; the list re-fetches for that view<br>- The four views are swipeable left/right as pages; a settled swipe adopts the swiped-to view and updates the selected chip<br>- Swiping is disabled while in multi-select mode (TK-007)<br>- The app bar title reads **Tickets** with the active view's total count shown below it as "N total"<br>- Opening the Tickets tab from another screen's request (e.g. a dashboard tile) preselects the requested view |
| Priority | High |

### 6.2 TK-002 — Live search over the fetched rows

| Field | Value |
|-------|-------|
| Description | A search box above the tabs narrows the visible rows as the user types. The search is applied client-side to the rows already fetched for the active view; it does not trigger a new server fetch. Matching is done against several columns with punctuation normalised away. |
| Acceptance Criteria | - The search box shows the placeholder **Search tickets** with a search icon<br>- Typing filters the visible rows live, debounced (~300 ms); submitting applies immediately<br>- A row matches when the typed text is contained in any of: ticket **number**, **subject**, **requester**, **assignee**, or **department** name<br>- The match is case-insensitive; `#`, commas, spaces and the `₹` symbol are stripped from both the query and the compared values before matching (so "pa", "INV-26", or "100852" match regardless of formatting)<br>- Amount-only / status columns are not independently searched beyond the fields listed above<br>- Clearing the search box restores the full fetched set for the current view/filter<br>- When the query matches no rows, the empty state (TK-006) is shown<br>- Search does not trigger a server re-fetch — it filters the already-loaded pages |
| Priority | High |

### 6.3 TK-003 — Filter & sort sheet

| Field | Value |
|-------|-------|
| Description | A filter button beside the search box opens a sheet where the user sets a create-date range, a sort order, and facet filters (Department, Status, Priority, Agent, Tag). Applying re-queries the list. The filter button reflects whether any filter is currently narrowing the list. |
| Acceptance Criteria | - The filter button is shown as a trailing control in the search bar and indicates an **active** state when any create-date range or facet filter is set (sort alone does not count as active)<br>- The sheet offers a **date range** (create-date window), a **sort** selector, and facet pickers for **Department, Status, Priority, Agent, Tag**<br>- The sort options are exactly: **Most Recently Updated**, **Most Recently Created**, **Due Date**, **Ticket Number**, **Longest Thread**; the default is Most Recently Created<br>- Sort order is ascending for **Due Date** (soonest first) and descending for the others; **Longest Thread** is ordered by the server<br>- On Apply, the selected date range, sort, and facet selections are applied and the list re-fetches; cancelling changes nothing<br>- Facet filters and the date range are also enforced on the fetched rows (a row is kept only when its department/status/priority/agent name matches the selected facet, and its created date falls inside the range)<br>- The filter/sort sheet's own behaviour (date presets, sort chips, chip-vs-searchable-dropdown facets, Apply/Reset draft) is specified in the Global BRD, GL-005 |
| Priority | High |

### 6.4 TK-004 — Ticket list row content

| Field | Value |
|-------|-------|
| Description | Each row summarises one ticket. It shows the ticket number, subject, status, requester, relative created time, meaningful priority, department and due date, and flags an overdue ticket. |
| Acceptance Criteria | - Every row shows: the ticket **#number**, the **subject**, the **status**, the **requester** name (or "Unknown" when absent), and the **created** time as a relative string (e.g. "3 days ago") with a tooltip of the full created date-time<br>- A **priority** chip is shown only for meaningful priorities — a "Normal" (or empty) priority is suppressed<br>- Meta chips are shown for the **department** (when present) and the **due date** (when present)<br>- An **overdue** ticket is flagged with an "Overdue" indicator and its due-date chip is marked as danger<br>- Tapping a row opens that ticket's detail screen (TK-011)<br>- The row is offered in two layouts (card / compact) per TK-005; both show the same underlying fields |
| Priority | High |

### 6.5 TK-005 — Comfortable / compact layout toggle

| Field | Value |
|-------|-------|
| Description | An app-bar action toggles the list between a comfortable (card) layout and a compact (dense single-row) layout. The choice is applied to the list rendering. |
| Acceptance Criteria | - An app-bar toggle switches between **Comfortable view** and **Compact view**; its tooltip names the layout it will switch to<br>- Compact rows render denser (more rows per screen); comfortable rows render as cards<br>- The setting applies immediately to the visible list |
| Priority | Low |

### 6.6 TK-006 — Scroll pagination and empty state

| Field | Value |
|-------|-------|
| Description | The list fetches tickets page by page from the server and appends more as the user scrolls. A skeleton is shown during the first load; an empty state is shown when there are no matching rows. |
| Acceptance Criteria | - The first load shows a loading skeleton in place of rows<br>- As the user scrolls, further pages are fetched and appended until the server has no more<br>- When the active view/filter/search yields no rows, an empty state is shown reading **No tickets** with the hint **Try a different filter or search.**<br>- Changing the view, date range, sort, or facet filters re-fetches from the first page |
| Priority | Medium |

### 6.7 TK-007 — Multi-select mode

| Field | Value |
|-------|-------|
| Description | Long-pressing a row enters multi-select mode, letting the user pick multiple tickets for a bulk action. A selection app bar and a select-all bar are shown while in this mode. |
| Acceptance Criteria | - Long-pressing any row toggles its selection and enters selection mode<br>- In selection mode, tapping a row toggles its selection (instead of opening it)<br>- A selection bar offers **select all / deselect all** for the currently visible rows<br>- The app bar switches to a selection app bar showing the selected count and a **cancel** control that clears the selection and exits the mode<br>- Page swiping between tabs is disabled while in selection mode so a bulk action stays scoped to one list<br>- Exiting selection mode (cancel, or clearing all) returns to the normal app bar |
| Priority | Medium |

### 6.8 TK-008 — Bulk actions on selected tickets

| Field | Value |
|-------|-------|
| Description | From the selection app bar the user can act on all selected tickets at once: assign to self, assign to an agent, set status, set priority, or delete. Each runs per-ticket and reports how many succeeded and failed. |
| Acceptance Criteria | - The selection app bar's primary action is **Assign to me** (claims every selected ticket)<br>- An overflow menu offers: **Assign to agent…**, **Set status…**, **Set priority…**, and **Delete** (destructive)<br>- "Assign to agent / Set status / Set priority" first prompt for the target value, then apply it to every selected ticket<br>- **Delete** first shows a confirmation reading **Delete N ticket(s)?** with the message **This permanently removes the selected tickets.** and only proceeds on confirm<br>- Bulk operations run per ticket; on completion a toast reports the count, e.g. "Assigned 5 tickets" or "Deleted 4 tickets · 1 failed"<br>- After a bulk action the selection is cleared, the list refreshes, and the per-tab counts reload |
| Priority | Medium |

### 6.9 TK-009 — Export the visible tickets

| Field | Value |
|-------|-------|
| Description | An export action downloads the active view's tickets (narrowed by the active search) as a PDF or Excel file with a fixed set of columns. |
| Acceptance Criteria | - An export menu in the app bar offers **PDF** and **Excel**<br>- Export gathers the active view's rows (paged from the server, capped at 2000) and applies the active search/date/facet narrowing before exporting<br>- The exported columns are exactly: **#, Subject, Status, Priority, Department, Requester, Assignee, Created, Due**<br>- On success a toast reports the count and format, e.g. "Exported 37 tickets as Excel"<br>- When there are no rows to export, a toast reads **No tickets to export** and no file is produced<br>- On failure, the server error message is shown as a toast (or "Saved file but could not open it automatically" when only the open step failed) |
| Priority | Medium |

### 6.10 TK-010 — Opening a ticket / cross-tab filter request

| Field | Value |
|-------|-------|
| Description | Tapping a row opens the ticket detail. The list also honours a view-filter requested from another screen while it is already alive. |
| Acceptance Criteria | - Tapping a row (outside selection mode) navigates to the ticket detail screen for that ticket<br>- A view request arriving from another tab while the list is already open jumps the list to the requested view and then clears the request<br>- A ticket mutated elsewhere (e.g. edited on the detail screen) causes the list to refetch so the row is not stale |
| Priority | High |

### 6.11 TK-011 — Ticket detail: load, loading and error states

| Field | Value |
|-------|-------|
| Description | Opening a ticket loads its record, conversation thread, and activity events. A loading view is shown during the fetch, and an error view with retry is shown on failure. |
| Acceptance Criteria | - On open, the screen fetches the ticket, its thread (most recent entries), and its activity events<br>- While loading, a loading view is shown under an app bar titled **Ticket**<br>- On load failure (or a missing ticket), an error view is shown with a **retry** action that re-attempts the load<br>- After sending a message, the data refreshes in place without showing the full-screen loader |
| Priority | High |

### 6.12 TK-012 — Ticket detail header (subject, status, SLA)

| Field | Value |
|-------|-------|
| Description | A collapsing header shows the ticket's subject and status chips; the app bar always shows the ticket number and reveals the subject once the header scrolls away. An SLA progress bar is shown when SLA data is present. |
| Acceptance Criteria | - The app bar shows **#number** at all times<br>- The collapsing header shows the **subject**, a **status** chip, a **priority** chip (when set), and an **Overdue** chip when the ticket is overdue<br>- Once the header has scrolled up behind the app bar, the subject also appears as a second line in the app bar<br>- When SLA data with a fraction is present, an SLA progress bar is shown along with an "SLA: <label>" line; an overdue SLA is indicated as such |
| Priority | Medium |

### 6.13 TK-013 — Ticket detail tabs

| Field | Value |
|-------|-------|
| Description | The detail body is organised into three tabs: Conversation, Details, and Activity. A progress bar is shown while an action is running. |
| Acceptance Criteria | - Three tabs are shown in this order: **Conversation**, **Details**, **Activity**<br>- The tabs can be selected by tap or swipe<br>- A linear progress indicator is shown while a ticket action is in flight<br>- The reply/note composer is shown only on the Conversation tab (TK-016) and hides the instant the user swipes or taps away from it |
| Priority | High |

### 6.14 TK-014 — Conversation tab

| Field | Value |
|-------|-------|
| Description | The Conversation tab shows the ticket thread as chat bubbles. Staff-authored entries (replies and internal notes) and incoming customer messages are visually distinguished, consecutive messages from one sender are grouped, and day separators divide the thread. The newest message is kept in view. |
| Acceptance Criteria | - Each thread entry is shown as a bubble; staff entries (agent replies and internal notes) are placed on one side and incoming customer messages on the other with the sender's avatar<br>- An **internal note** and an **agent reply** each carry a role label distinguishing them; a plain customer message carries none<br>- Consecutive entries from the same sender on the same side and day are grouped so the sender name/avatar is shown once per run<br>- A day separator is shown when the day changes, labelled **Today**, **Yesterday**, or the date<br>- Each bubble shows the message body (rendered from its HTML), any attachments, and a relative timestamp; an entry with no content shows **(no content)**<br>- Attachments open in the shared attachment viewer, and links / inline images in the body are tappable (see Global BRD, GL-001 and GL-002)<br>- The conversation auto-scrolls to the newest entry when it opens and whenever a new entry arrives<br>- An empty thread shows **No messages yet** |
| Priority | High |

### 6.15 TK-015 — Message bubble actions (Reply / Copy)

| Field | Value |
|-------|-------|
| Description | Long-pressing a message bubble opens an action sheet to reply to (quote) that message or copy its text. |
| Acceptance Criteria | - Long-pressing a bubble opens a sheet with **Reply** and **Copy text**<br>- **Reply** loads that entry into the composer as a quote and shows a "Replying to <sender>" banner above the input, with a control to cancel the quote<br>- **Copy text** copies the message's plain text to the clipboard and confirms with a "Copied" toast; it is disabled when the message has no text<br>- A sent reply that was quoting an entry prepends the quoted excerpt to the outgoing message |
| Priority | Low |

### 6.16 TK-016 — Reply / internal-note composer

| Field | Value |
|-------|-------|
| Description | On the Conversation tab an agent with reply permission gets a composer to post a public reply or an internal note, with rich text, attachments, emoji, saved-reply/FAQ insertion, and a full-screen editor. |
| Acceptance Criteria | - The composer is shown only on the Conversation tab and only when the agent has reply permission on the ticket's department (TK-027); otherwise no composer is shown<br>- A toggle switches between **public reply** and **internal note** mode; the placeholder and send icon reflect the current mode<br>- A **+** menu offers **Camera**, **Photo**, **File**, **Saved replies**, and **Insert FAQ**; an **emoji** picker is available; attachments picked are shown as removable chips<br>- **Saved replies** insert the canned response body (with its variables expanded against this ticket when possible); **Insert FAQ** inserts the chosen article's answer<br>- An **expand** control opens a full-screen editor sharing the same draft, with its own send and saved-reply/FAQ insert actions<br>- **Send** posts a reply (with alert) or an internal note; on success the thread refreshes in place and the Tickets list is signalled to refresh<br>- Send is disabled when the draft is empty and no attachment is attached; a send shows a busy indicator<br>- On send failure an error toast is shown and the draft (and attachments) are kept |
| Priority | High |

### 6.17 TK-017 — Details tab

| Field | Value |
|-------|-------|
| Description | The Details tab lists the ticket's attributes, requester information, and any custom fields. Editable attribute rows open the matching picker; rows the agent lacks permission for are read-only. |
| Acceptance Criteria | - An **Attributes** section shows **Status**, **Priority**, **Department**, **Assignee**, and **Due date**; each row is tappable to edit only when the agent has the matching permission (status→change status, priority/due→edit, department→transfer, assignee→assign), otherwise it is read-only<br>- A row with no value shows a placeholder prompt (e.g. "Set priority", "Assign") when editable<br>- An **Information** section shows read-only **Requester**, **Email**, **Created**, and **Updated**<br>- A **Custom fields** section is shown only when the ticket has custom field values, listing each name/value<br>- Editing a row routes to the same action as the ⋮ menu (TK-019) and reloads the ticket on success |
| Priority | High |

### 6.18 TK-018 — Activity tab

| Field | Value |
|-------|-------|
| Description | The Activity tab shows the ticket's event history as a timeline, newest first. |
| Acceptance Criteria | - Events are shown as a vertical timeline ordered **newest first** (the server's oldest→newest order is reversed, keeping same-second events in their correct relative order and "Created" last)<br>- Each event shows its description (or state) and a line combining the actor (when present) and the relative time<br>- An empty history shows **No activity** |
| Priority | Low |

### 6.19 TK-019 — Action menu, permission-gated

| Field | Value |
|-------|-------|
| Description | An overflow (⋮) menu on the detail app bar surfaces every ticket action the agent is permitted to perform. Actions the agent cannot perform on this ticket's department are hidden. |
| Acceptance Criteria | - The ⋮ menu lists only actions the agent may perform, grouped as: (workflow) **Change status**, **Mark answered/overdue**; (assignment) **Assign**, **Assign to team**, **Claim**, **Release**, **Change owner**, **Refer**; (attributes) **Transfer dept**, **Set priority**, **Change topic**, **Set due date**, **Edit fields**, **Tags**; (relations) **Link tickets**, **Merge tickets**; (metadata) **Collaborators**, **Create task** (see TK-034), **Ban / unban email**; and **Delete** (destructive)<br>- **Collaborators** is always available (view + server-enforced edits); every other action is gated by the corresponding permission (TK-027)<br>- Group dividers appear only between non-empty groups, so gating items out never leaves a dangling divider |
| Priority | High |

### 6.20 TK-020 — Change status / mark answered or overdue

| Field | Value |
|-------|-------|
| Description | The status action changes the ticket's status from a picker; the mark action sets an answered/overdue flag. |
| Acceptance Criteria | - **Change status** opens a status picker; choosing a status applies it, shows "Status updated", and reloads the ticket<br>- **Mark answered/overdue** offers exactly: **Answered**, **Unanswered**, **Overdue**, **Not overdue**; choosing one applies it, shows "Marked <state>", and reloads<br>- Both are available when the agent has the matching permission (status: close-or-edit; mark: mark-answered-or-edit) |
| Priority | High |

### 6.21 TK-021 — Assignment actions

| Field | Value |
|-------|-------|
| Description | Assignment actions cover assigning to an agent or team, claiming, releasing, changing the owner, and referring. |
| Acceptance Criteria | - **Assign** / **Assign to team** open the respective picker and, on choose, assign the ticket and reload (toast "Assigned" / "Assigned to team")<br>- **Claim** assigns the ticket to the current agent (toast "Ticket claimed"); **Release** unassigns it (toast "Ticket released"); both reload<br>- **Change owner** opens a user picker and sets the ticket owner (toast "Owner changed")<br>- **Refer** opens a chooser (Agent / Team / Department), then a picker of that kind, and adds a referral; existing referrals can be viewed and removed<br>- Assign/claim/team/release require assign/release permission; owner and refer require edit/refer permission respectively |
| Priority | High |

### 6.22 TK-022 — Attribute edits (transfer, priority, topic, due date, fields, tags)

| Field | Value |
|-------|-------|
| Description | Attribute actions change the ticket's department, priority, topic, due date, custom fields, and tags. |
| Acceptance Criteria | - **Transfer dept** opens a department picker (pre-selecting the current department) and transfers on choose (toast "Transferred", reload)<br>- **Set priority** and **Change topic** open their pickers and apply on choose (toast "Priority updated" / "Topic updated")<br>- **Set due date** opens a date picker (today up to 3 years out) then a time picker; a due time in the past is rejected with **Due date must be in the future**; a valid value is saved (toast "Due date set")<br>- **Edit fields** loads the ticket's editable dynamic fields and lets the agent change them; **Save** posts the values and reloads; a load with no editable fields shows **No editable fields**; server field errors are shown inline per field<br>- **Tags** lists the ticket's tags and lets the agent add (from the shared tag list) or remove them<br>- All of these require edit permission |
| Priority | Medium |

### 6.23 TK-023 — Link / merge tickets

| Field | Value |
|-------|-------|
| Description | Link or merge other tickets into this one by ticket number, with the option to undo an existing relation. |
| Acceptance Criteria | - **Link tickets** / **Merge tickets** open a dialog that shows any existing relation ("Currently N linked: …" or "Linked to #…") and offers **Unlink** / **Unmerge**<br>- The user enters one or more ticket numbers (comma/space separated); submitting with none entered shows **Enter at least one ticket number**<br>- **Merge** additionally offers a **Combine threads** toggle ("Merge conversations into one thread")<br>- A successful link/merge/unlink/unmerge closes the dialog and reloads the ticket; failures show the server error<br>- Link requires link permission; merge requires merge permission |
| Priority | Medium |

### 6.24 TK-024 — Collaborators

| Field | Value |
|-------|-------|
| Description | Manage the ticket's collaborators (Cc). |
| Acceptance Criteria | - The Collaborators dialog lists current collaborators (name + email) or **No collaborators** when empty<br>- **Add collaborator** opens a user picker and adds the chosen user; each collaborator can be removed<br>- Add/remove are enforced server-side; the action is available to all agents (view + server-gated edits) |
| Priority | Low |

### 6.25 TK-025 — Ban / unban requester email

| Field | Value |
|-------|-------|
| Description | Ban or unban the requester's email address. |
| Acceptance Criteria | - The action opens a chooser (showing the requester email) with **Ban this email address** and **Remove from ban list**<br>- Choosing an option performs it and confirms with a toast ("Email banned" / "Email removed from ban list")<br>- The action is available only when the agent has the ban-list permission |
| Priority | Low |

### 6.26 TK-026 — Delete ticket

| Field | Value |
|-------|-------|
| Description | Permanently delete the ticket. |
| Acceptance Criteria | - **Delete** shows a confirmation reading **Delete ticket?** with the message **This cannot be undone.** and a destructive **Delete** confirm<br>- On confirm, the ticket is deleted, a "Ticket deleted" toast is shown, and the screen closes back to the list<br>- On failure the server error is shown as a toast<br>- The action is available only when the agent has delete permission |
| Priority | Medium |

### 6.27 TK-027 — Per-agent permission gating

| Field | Value |
|-------|-------|
| Description | Every mutating ticket affordance is gated by the same per-department permission the corresponding server endpoint enforces, so an agent never sees an action they cannot perform. |
| Acceptance Criteria | - Action visibility/editability is derived from the current agent's per-department permissions (ticket.edit, ticket.assign, ticket.release, ticket.transfer, ticket.refer, ticket.link, ticket.merge, ticket.markanswered, ticket.close, ticket.reply, ticket.delete; ban uses the global ban-list permission)<br>- Status change requires close **or** edit; note requires reply **or** edit; mark requires mark-answered **or** edit<br>- When permissions are not yet loaded, actions default to hidden (the server would reject them regardless)<br>- Details-tab rows and the composer honour the same gates as the ⋮ menu (a non-permitted attribute row is read-only; a non-reply agent gets no composer) |
| Priority | High |

### 6.28 TK-028 — Create ticket: form structure and required fields

| Field | Value |
|-------|-------|
| Description | The Create ticket screen collects a new ticket across grouped sections. Requester, subject, and message are required; the submit button stays disabled until all three are present and names what is still missing. |
| Acceptance Criteria | - The screen is titled **New ticket** and is organised into sections: **Requester**, **Ticket details**, **Attachments**, **Properties**, and **Internal note**<br>- The three required fields are **Requester**, **Subject**, and **Message**<br>- The **Create ticket** button is disabled until all three required fields are provided; while disabled, a hint lists what is missing, e.g. **Add requester, subject to continue**<br>- While saving, the form is not interactive and a progress indicator is shown |
| Priority | High |

### 6.29 TK-029 — Create ticket: requester and collaborators

| Field | Value |
|-------|-------|
| Description | The Requester section picks the ticket's requester (required) and optional collaborators (Cc). |
| Acceptance Criteria | - **Requester** opens a user picker; until chosen it shows **Required · tap to choose**; after a failed submit with no requester it shows an inline error<br>- **Collaborators (Cc)** lets the user add one or more users; added collaborators are shown as removable chips and the row shows "N added"<br>- A collaborator already added is not added twice |
| Priority | Medium |

### 6.30 TK-030 — Create ticket: message, canned/FAQ, attachments

| Field | Value |
|-------|-------|
| Description | The Ticket details section holds the subject and a rich message body, with saved-reply/FAQ insertion; the Attachments section adds files. |
| Acceptance Criteria | - **Subject** is a required single-line field (inline error **Subject is required** when empty on submit)<br>- **Message** is a rich-text field with placeholder **Type your message…**; it is required (inline error **Message is required** when empty on submit)<br>- Saved-reply and FAQ actions insert their content into the message at the cursor<br>- **Attachments** adds files via Camera / Photo / File; added files are shown as removable chips with name and size |
| Priority | High |

### 6.31 TK-031 — Create ticket: properties

| Field | Value |
|-------|-------|
| Description | The Properties section sets source, help topic, department, priority, due date, agent/team assignment, and status. |
| Acceptance Criteria | - **Source** offers exactly **Phone**, **Email**, **Web**, **Other**, defaulting to **Phone**<br>- **Help topic**, **Department**, **Priority**, and **Status** each open a picker of the respective kind<br>- **Due date** opens a date then time picker (today at the earliest, up to 3 years out); a past time is rejected with **Due date must be in the future**; the chosen value can be cleared<br>- **Assign to agent** and **Assign to team** each open a picker and can be cleared<br>- All Properties fields are optional |
| Priority | Medium |

### 6.32 TK-032 — Create ticket: internal note

| Field | Value |
|-------|-------|
| Description | The Internal note section adds a staff-only note posted after the ticket is created. |
| Acceptance Criteria | - A multi-line **Internal note** field is shown with the hint **Visible to staff only**<br>- When non-empty, the note is posted to the new ticket after creation (best-effort; a note failure does not fail the create) |
| Priority | Low |

### 6.33 TK-033 — Create ticket: submit, validation, and result

| Field | Value |
|-------|-------|
| Description | Submitting validates the required fields, creates the ticket, applies the optional assignment/status/collaborators/note, then opens the new ticket. |
| Acceptance Criteria | - On submit, the subject and message are validated inline and a missing requester is surfaced on its own row (scrolling it into view)<br>- On a valid form the ticket is created with the requester, subject, rich message, source, and any topic/department/priority/due date, plus attachments<br>- After creation, the chosen agent/team assignment, status, collaborators, and internal note are applied via their own endpoints (best-effort — none can fail the create)<br>- On success a toast reads **Ticket #<number> created** and the new ticket's detail screen replaces the create screen<br>- On an API error with field errors, each is shown inline against its field (user_id, subject, message); a general error is shown as an error banner at the top of the form |
| Priority | High |

### 6.34 TK-034 — Create task from a ticket

| Field | Value |
|-------|-------|
| Description | An agent with task-create permission on the ticket's department can create a task pre-linked to the ticket directly from the ticket's ⋮ menu. |
| Acceptance Criteria | - The ⋮ menu shows a **Create task** action, gated by the agent's **task.create** permission on the ticket's department (hidden otherwise)<br>- Selecting it opens the Create Task screen pre-linked to this ticket, passing the ticket id and number so the form shows the "This task will be linked to ticket #<number>" banner (see the Tasks BRD, TS-027)<br>- The task is created with the ticket association (`ticket_id`), so it appears as a task belonging to the ticket |
| Priority | Medium |

---

*Document in progress — additional cases added after individual approval.*
