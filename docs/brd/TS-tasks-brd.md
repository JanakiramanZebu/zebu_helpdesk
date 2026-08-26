# Business Requirements Document — Tasks

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Tasks **Document Version:** 1.0 (Initial Edition) **Date:** August 2026 **Status:** In Progress (case-by-case) **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Tasks — Business Requirements Document |
| Module Scope | The Tasks surfaces of the Staff Portal: the **Tasks list** (filter tabs, search, filter/sort, multi-select bulk actions, export, layout toggle, scroll pagination), the **Task detail** screen (collapsing header with progress and blocked state, Conversation / Details / Activity tabs, the reply/note composer, subtasks, dependencies, and the ⋮ action set — close/reopen, assign, transfer, priority, collaborators, tags), and the **Create task** screen (including creating a task linked to a ticket). This document specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/tasks/tasks_list_screen.dart`, `lib/features/tasks/task_detail_screen.dart`, `lib/features/tasks/create_task_screen.dart`, `lib/features/tasks/widgets/{task_row,task_card}.dart`, `lib/widgets/{entity_list_row,message_composer}.dart` |

---

## 6. Functional Requirements

### 6.1 TS-001 — Tasks list: filter tabs with per-tab counts

| Field | Value |
|-------|-------|
| Description | The Tasks list is organised into seven filter tabs shown as a row of chips, each carrying a live count. Selecting a chip switches the list to that view; the tabs are also swipeable as pages. The app bar shows the title "Tasks" and the active view's total count. |
| Acceptance Criteria | - Exactly seven tabs are shown, in this left-to-right order: **Open**, **All**, **Overdue**, **Completed**, **Created by me**, **Collaborator**, **My Tasks**<br>- Each tab shows a count badge; the count is computed with the same query the list runs for that view (so a badge can't disagree with the list); a tab whose count fails to load shows no badge<br>- The **My Tasks** and **Collaborator** views are additionally scoped to open tasks only (matching the web nav's open-only counts)<br>- Tapping a chip makes it the active view, moves the pager to it, and re-fetches; the seven views are also swipeable, and a settled swipe adopts the swiped-to view<br>- Swiping is disabled while in multi-select mode (TS-007)<br>- The app bar title reads **Tasks** with the active view's total count shown below it as "N total"<br>- Opening the Tasks tab from another screen's request (e.g. a dashboard tile) preselects the requested view |
| Priority | High |

### 6.2 TS-002 — Live search over the fetched rows

| Field | Value |
|-------|-------|
| Description | A search box narrows the visible rows as the user types, applied client-side to the rows already fetched for the active view; it does not trigger a new server fetch. |
| Acceptance Criteria | - The search box shows the placeholder **Search tasks** with a search icon<br>- Typing filters the visible rows live, debounced (~300 ms); submitting applies immediately<br>- A row matches when the typed text is contained in any of: task **number**, **title**, **assignee**, or **department** name<br>- The match is case-insensitive; `#`, commas, spaces and the `₹` symbol are stripped from both the query and the compared values before matching<br>- Clearing the search box restores the full fetched set for the current view/filter<br>- When the query matches no rows, the empty state (TS-006) is shown<br>- Search does not trigger a server re-fetch |
| Priority | High |

### 6.3 TS-003 — Filter & sort sheet

| Field | Value |
|-------|-------|
| Description | A filter button opens a sheet to set a create-date range, sort order, and facet filters (Department, Priority, Agent, Tag). Applying re-queries the list. |
| Acceptance Criteria | - The filter button indicates an **active** state when any create-date range or facet filter is set (sort alone does not count)<br>- The sheet offers a **date range**, a **sort** selector, and facet pickers for **Department, Priority, Agent, Tag**<br>- The sort options are exactly: **Most Recently Updated**, **Most Recently Created**, **Due Date**, **Task Number**, **Longest Thread**; default is Most Recently Created<br>- Sort order is ascending for **Due Date** (soonest first) and descending for the others; **Longest Thread** is ordered by the server<br>- On Apply, the selections are applied and the list re-fetches; cancelling changes nothing<br>- Facet filters and the date range are also enforced on the fetched rows (kept only when the row's department/priority/agent name matches the selected facet and its created date falls inside the range)<br>- The filter/sort sheet's own behaviour (date presets, sort chips, chip-vs-searchable-dropdown facets, Apply/Reset draft) is specified in the Global BRD, GL-005 |
| Priority | High |

### 6.4 TS-004 — Task list row content

| Field | Value |
|-------|-------|
| Description | Each row summarises one task: number, title, status, assignee, relative created time, meaningful priority, department, due date, progress, and a blocked flag. |
| Acceptance Criteria | - Every row shows: the task **#number**, the **title**, the **status**, the **assignee** name (or **Unassigned** when absent), and the **created** time as a relative string with a tooltip of the full created date-time<br>- A **priority** chip is shown only for meaningful priorities (a "Normal"/empty priority is suppressed)<br>- Meta chips are shown for the **department** (when present) and the **due date** (when present); the due-date chip is marked danger when the task is overdue<br>- The **progress** percentage is shown when greater than 0<br>- A **blocked** task (an open dependency) is flagged with a "Blocked" indicator<br>- Tapping a row opens that task's detail screen (TS-011) |
| Priority | High |

### 6.5 TS-005 — Comfortable / compact layout toggle

| Field | Value |
|-------|-------|
| Description | An app-bar action toggles the list between a comfortable (card) layout and a compact (dense) layout. |
| Acceptance Criteria | - An app-bar toggle switches between **Comfortable view** and **Compact view**; its tooltip names the layout it will switch to<br>- The choice applies immediately to the visible list |
| Priority | Low |

### 6.6 TS-006 — Scroll pagination and empty state

| Field | Value |
|-------|-------|
| Description | The list fetches tasks page by page and appends more as the user scrolls; a skeleton shows during first load and an empty state shows when there are no matching rows. |
| Acceptance Criteria | - The first load shows a loading skeleton<br>- Scrolling fetches and appends further pages until the server has no more<br>- When the active view/filter/search yields no rows, an empty state reads **No tasks** with the hint **Try a different filter or search.**<br>- Changing view, date range, sort, or facet filters re-fetches from the first page |
| Priority | Medium |

### 6.7 TS-007 — Multi-select mode

| Field | Value |
|-------|-------|
| Description | Long-pressing a row enters multi-select mode for bulk actions. |
| Acceptance Criteria | - Long-pressing any row toggles its selection and enters selection mode<br>- In selection mode, tapping a row toggles its selection instead of opening it<br>- A selection bar offers **select all / deselect all** for the currently visible rows<br>- The app bar switches to a selection app bar showing the selected count and a **cancel** control that clears the selection and exits<br>- Page swiping between tabs is disabled while in selection mode<br>- Exiting selection mode returns to the normal app bar |
| Priority | Medium |

### 6.8 TS-008 — Bulk actions on selected tasks

| Field | Value |
|-------|-------|
| Description | From the selection app bar the user can act on all selected tasks: mark complete, reopen, assign to an agent, set priority, or transfer department. |
| Acceptance Criteria | - The selection app bar's primary action is **Mark complete** (closes every selected task)<br>- An overflow menu offers: **Reopen**, **Assign to agent…**, **Set priority…**, and **Transfer department…**<br>- The value-based actions first prompt for the target (agent / priority / department) then apply it to every selected task<br>- Bulk operations run per task; on completion a toast reports the count, e.g. "Completed 5 tasks" or "Assigned 4 tasks · 1 failed"<br>- After a bulk action the selection is cleared, the list refreshes, and the per-tab counts reload<br>- (There is no bulk delete for tasks.) |
| Priority | Medium |

### 6.9 TS-009 — Export the visible tasks

| Field | Value |
|-------|-------|
| Description | An export action downloads the active view's tasks (narrowed by the active search) as PDF or Excel. |
| Acceptance Criteria | - An export menu in the app bar offers **PDF** and **Excel**<br>- Export gathers the active view's rows (paged from the server, capped at 2000) and applies the active search/date/facet narrowing<br>- The exported columns are exactly: **#, Title, Status, Priority, Department, Assignee, Progress, Created, Due**<br>- On success a toast reports the count and format, e.g. "Exported 20 tasks as Excel"<br>- When there are no rows to export, a toast reads **No tasks to export**<br>- On failure, the server error is shown as a toast (or "Saved file but could not open it automatically" when only the open step failed) |
| Priority | Medium |

### 6.10 TS-010 — Opening a task / cross-tab filter request

| Field | Value |
|-------|-------|
| Description | Tapping a row opens the task detail; the row's data is passed along so the detail can show a due date its own endpoint omits. The list also honours a view-filter requested from another screen. |
| Acceptance Criteria | - Tapping a row (outside selection mode) navigates to the task detail for that task, passing the list row as seed data<br>- A view request arriving from another tab while the list is already open jumps the list to the requested view and clears the request<br>- A task mutated elsewhere causes the list to refetch so the row is not stale |
| Priority | High |

### 6.11 TS-011 — Task detail: load, loading, and error states

| Field | Value |
|-------|-------|
| Description | Opening a task loads its record, conversation thread, activity events, subtasks, and dependencies. Because the detail endpoint omits the due date, it is grafted from the list row passed in. A loading view is shown during the fetch and an error view with retry on failure. |
| Acceptance Criteria | - On open, the screen fetches the task, its thread, activity events, subtasks, and dependencies<br>- When the detail response lacks a due date but the seed row (same task) has one, the seed's due date and overdue flag are used<br>- While loading, a loading view is shown under an app bar titled **Task**<br>- On failure (or missing task), an error view with **retry** is shown<br>- After sending a message, the data refreshes in place without the full-screen loader |
| Priority | High |

### 6.12 TS-012 — Task detail header (title, status, progress, blocked)

| Field | Value |
|-------|-------|
| Description | A collapsing header shows the task's title and status chips, a progress bar, and a blocked banner when applicable; the app bar always shows the task number and reveals the title once the header scrolls away. |
| Acceptance Criteria | - The app bar shows **#number** at all times<br>- The collapsing header shows the **title**, a **status** chip, a **priority** chip (when set), and an **Overdue** chip when overdue<br>- A **progress** bar with a "Progress: N%" line is shown when progress is greater than 0<br>- When the task is blocked, a banner reading **Blocked by an open dependency** is shown<br>- Once the header scrolls behind the app bar, the title also appears as a second line in the app bar |
| Priority | Medium |

### 6.13 TS-013 — Task detail tabs

| Field | Value |
|-------|-------|
| Description | The detail body is organised into three tabs: Conversation, Details, Activity. A progress bar shows while an action runs. |
| Acceptance Criteria | - Three tabs are shown in this order: **Conversation**, **Details**, **Activity**, selectable by tap or swipe<br>- A linear progress indicator is shown while a task action is in flight<br>- The reply/note composer is shown only on the Conversation tab (TS-016) and hides the instant the user swipes or taps away |
| Priority | High |

### 6.14 TS-014 — Conversation tab

| Field | Value |
|-------|-------|
| Description | The Conversation tab shows the task thread as chat bubbles, distinguishing staff replies/notes from incoming messages, grouping consecutive messages from one sender, and dividing the thread by day. The newest message is kept in view. |
| Acceptance Criteria | - Each thread entry is shown as a bubble; staff entries (replies and internal notes) sit on one side and incoming messages on the other with the sender's avatar<br>- An **internal note** and an **agent reply** each carry a distinguishing role label; a plain incoming message carries none<br>- Consecutive entries from the same sender on the same side and day are grouped so name/avatar shows once per run<br>- A day separator is shown when the day changes, labelled **Today**, **Yesterday**, or the date<br>- Each bubble shows the message body, any attachments, and a relative timestamp; an empty entry shows **(no content)**<br>- Attachments open in the shared attachment viewer, and links / inline images in the body are tappable (see Global BRD, GL-001 and GL-002)<br>- The conversation auto-scrolls to the newest entry on open and when a new entry arrives<br>- An empty thread shows **No messages yet** |
| Priority | High |

### 6.15 TS-015 — Message bubble actions (Reply / Copy)

| Field | Value |
|-------|-------|
| Description | Long-pressing a message bubble opens an action sheet to reply to (quote) that message or copy its text. |
| Acceptance Criteria | - Long-pressing a bubble opens a sheet with **Reply** and **Copy text**<br>- **Reply** loads that entry into the composer as a quote and shows a "Replying to <sender>" banner with a cancel control<br>- **Copy text** copies the message's plain text and confirms with "Copied"; it is disabled when the message has no text |
| Priority | Low |

### 6.16 TS-016 — Reply / internal-note composer

| Field | Value |
|-------|-------|
| Description | On the Conversation tab an agent with reply permission gets a composer to post a public reply or an internal note, with rich text, attachments, emoji, saved-reply/FAQ insertion, and a full-screen editor. |
| Acceptance Criteria | - The composer is shown only on the Conversation tab and only when the agent has reply permission on the task's department (TS-026); otherwise no composer is shown<br>- A toggle switches between **public reply** and **internal note**; the placeholder (reply mode reads "Reply to this task...") and send icon reflect the mode<br>- A **+** menu offers **Camera**, **Photo**, **File**, **Saved replies**, and **Insert FAQ**; an **emoji** picker is available; attachments are shown as removable chips<br>- An **expand** control opens a full-screen editor sharing the same draft<br>- **Send** posts a reply (with alert) or an internal note; on success the thread refreshes in place and the Tasks list is signalled to refresh<br>- Send is disabled when the draft is empty and no attachment is attached; a send shows a busy indicator<br>- On send failure an error toast is shown and the draft (and attachments) are kept |
| Priority | High |

### 6.17 TS-017 — Details tab: attributes, information, custom fields

| Field | Value |
|-------|-------|
| Description | The Details tab lists the task's attributes, read-only information, and any custom fields. Editable attribute rows open the matching picker when the agent has permission. |
| Acceptance Criteria | - An **Attributes** section shows **Status**, **Priority**, **Department**, and **Assignee**; each is tappable to edit only with the matching permission (status→close/reopen, priority→edit, department→transfer, assignee→assign), otherwise read-only<br>- An empty editable row shows a placeholder prompt (e.g. "Set priority", "Assign")<br>- An **Information** section shows read-only **Number**, **Created**, **Updated**, and **Due**<br>- A **Custom fields** section is shown only when the task has custom field values, listing each name/value |
| Priority | High |

### 6.18 TS-018 — Subtasks

| Field | Value |
|-------|-------|
| Description | The Details tab lists the task's subtasks and lets an agent with create permission add one. |
| Acceptance Criteria | - A **Subtasks** section lists the task's subtasks as cards (number, title, status, assignee, progress); an empty list shows **No subtasks**<br>- Tapping a subtask opens its own task detail<br>- An **Add subtask** action is shown only when the agent has create permission; it opens a sheet with **Title** and **Description** fields<br>- Both fields are required — an empty one shows **Title and description are required** and blocks creation<br>- On success the subtask is created (inheriting the parent's department), the sheet closes, and the task reloads |
| Priority | Medium |

### 6.19 TS-019 — Dependencies

| Field | Value |
|-------|-------|
| Description | The Details tab lists the task's dependencies (blocking tasks) and lets an agent with edit permission add or remove them. A dependency that is still open blocks the task. |
| Acceptance Criteria | - A **Dependencies** section lists each dependency as a card showing the blocking task's number and title (or "Dependency #id" when the blocker isn't expanded) and whether it is **Required** or **Optional**; an open blocker is indicated as blocking<br>- An empty list shows **No dependencies**<br>- An **Add dependency** action (edit permission only) opens a dialog to enter a **Blocking task id**; a non-numeric/invalid value shows **Enter a valid task id**<br>- Each dependency can be removed (edit permission only)<br>- Adding or removing a dependency reloads the task (so the blocked state and progress update) |
| Priority | Medium |

### 6.20 TS-020 — Activity tab

| Field | Value |
|-------|-------|
| Description | The Activity tab shows the task's event history as a timeline, newest first. |
| Acceptance Criteria | - Events are shown as a vertical timeline ordered **newest first** (the server's oldest→newest order reversed, keeping same-second events in correct relative order and "Created" last)<br>- Each event shows its description (or state) and a line combining the actor (when present) and the relative time<br>- An empty history shows **No activity** |
| Priority | Low |

### 6.21 TS-021 — Action menu, permission-gated

| Field | Value |
|-------|-------|
| Description | An overflow (⋮) menu surfaces the task actions the agent may perform; actions the agent cannot perform on this task's department are hidden. |
| Acceptance Criteria | - The ⋮ menu lists: **Close** (when the task is open) or **Reopen** (when closed) — gated by close permission; **Assign** (assign permission); **Transfer dept** (transfer permission); **Set priority** (edit permission); **Collaborators** (always available); and **Tags** (edit permission)<br>- Group dividers appear only around non-empty groups<br>- When permissions are not yet loaded, actions default to hidden |
| Priority | High |

### 6.22 TS-022 — Status: close / reopen

| Field | Value |
|-------|-------|
| Description | A task's status is binary — Open or Completed — driven by close/reopen. It can be changed from the ⋮ menu or the Details-tab Status row via a deliberate picker. |
| Acceptance Criteria | - From the ⋮ menu, **Close** closes an open task ("Task closed") and **Reopen** reopens a closed one ("Task reopened"); both reload<br>- The Details-tab **Status** row opens a picker offering **Open** and **Completed** with the current one selected; choosing the other applies the matching close/reopen; choosing the current one (or dismissing) changes nothing<br>- Status changes require close permission |
| Priority | High |

### 6.23 TS-023 — Assign / transfer / set priority

| Field | Value |
|-------|-------|
| Description | Assignment, department transfer, and priority changes are made from pickers. |
| Acceptance Criteria | - **Assign** opens an agent picker and assigns the task on choose (toast "Assigned", reload)<br>- **Transfer dept** opens a department picker (pre-selecting the current department) and transfers on choose (toast "Transferred", reload)<br>- **Set priority** opens a task-priority picker (pre-selecting the current priority) and applies on choose (toast "Priority updated", reload)<br>- Each requires its matching permission (assign / transfer / edit) |
| Priority | Medium |

### 6.24 TS-024 — Collaborators

| Field | Value |
|-------|-------|
| Description | Manage the task's collaborators. |
| Acceptance Criteria | - The Collaborators dialog lists current collaborators (name + email) or **No collaborators** when empty<br>- **Add collaborator** opens a user picker and adds the chosen user; each collaborator can be removed<br>- Add/remove are enforced server-side; the action is available to all agents |
| Priority | Low |

### 6.25 TS-025 — Tags

| Field | Value |
|-------|-------|
| Description | Manage the task's tags. |
| Acceptance Criteria | - The Tags dialog lists the task's tags or **No tags** when empty<br>- **Add tag** opens a picker from the shared tag list; each tag can be removed<br>- Tag management requires edit permission |
| Priority | Low |

### 6.26 TS-026 — Per-agent permission gating

| Field | Value |
|-------|-------|
| Description | Every mutating task affordance is gated by the same per-department permission the corresponding server endpoint enforces, so an agent never sees an action they cannot perform. |
| Acceptance Criteria | - Action visibility/editability is derived from the agent's per-department task permissions (task.edit, task.create, task.assign, task.transfer, task.close, task.reply)<br>- Close/reopen and the status row require close permission; add-subtask requires create; add/remove dependency, priority, and tags require edit; assign requires assign; transfer requires transfer; the composer requires reply<br>- When permissions are not yet loaded, actions default to hidden (the server would reject them regardless)<br>- Details-tab rows and section actions honour the same gates as the ⋮ menu (a non-permitted attribute row is read-only; a non-reply agent gets no composer; add-subtask/add-dependency hidden without their permissions) |
| Priority | High |

### 6.27 TS-027 — Create task: structure and required fields

| Field | Value |
|-------|-------|
| Description | The Create task screen collects a new task across grouped sections. Department, title, and description are required; the submit button stays disabled until all three are present and names what is still missing. A task may also be created linked to a ticket. |
| Acceptance Criteria | - The screen is titled **New task** and is organised into sections: **Task details**, **Attachments**, and **Properties**<br>- The three required fields are **Department**, **Title**, and **Description**<br>- The **Create task** button is disabled until all three are provided; while disabled, a hint lists what is missing, e.g. **Add department, title to continue**<br>- When opened from a ticket, an informational banner reads **This task will be linked to ticket #<number>** (or a generic variant) and the created task is linked to that ticket<br>- While saving, the form is not interactive and a progress indicator is shown |
| Priority | High |

### 6.28 TS-028 — Create task: title, description, canned/FAQ, attachments

| Field | Value |
|-------|-------|
| Description | The Task details section holds the title and a rich description with saved-reply/FAQ insertion; the Attachments section adds files. |
| Acceptance Criteria | - **Title** is a required single-line field (placeholder **Title**; inline server error under it when returned)<br>- **Description** is a required rich-text field with placeholder **Describe the task…** (inline error **Description is required** when empty on submit)<br>- Saved-reply and FAQ actions insert their content into the description at the cursor<br>- **Attachments** adds files via Camera / Photo / File; added files are shown as removable chips with name and size |
| Priority | High |

### 6.29 TS-029 — Create task: properties

| Field | Value |
|-------|-------|
| Description | The Properties section sets the department (required), priority, due date, and an optional parent task. |
| Acceptance Criteria | - **Department** opens a department picker; until chosen it shows **Required · tap to choose**; after a failed submit with no department it shows an inline error<br>- **Priority** opens a task-priority picker<br>- **Due date** opens a date then time picker (from yesterday up to 3 years out; defaults to 5 pm when no time is chosen) and can be cleared<br>- **Parent task** opens a searchable task picker (search by number or title); the chosen parent is shown as "#number · title" and can be cleared |
| Priority | Medium |

### 6.30 TS-030 — Create task: submit, validation, and result

| Field | Value |
|-------|-------|
| Description | Submitting validates the required fields, creates the task, and opens the new task. |
| Acceptance Criteria | - On submit, the title and description are validated and a missing department is surfaced on its own row (scrolling it into view)<br>- On a valid form the task is created with the department, title, rich description, and any priority, due date, parent task, and (when applicable) the linked ticket, plus attachments<br>- On success a toast reads **Task #<number> created** and the new task's detail screen replaces the create screen<br>- On an API error with field errors, each is shown inline against its field (title, description, dept_id); a general error is shown as an error banner at the top of the form |
| Priority | High |

---

*Document in progress — additional cases added after individual approval.*
