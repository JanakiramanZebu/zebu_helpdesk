# Business Requirements Document — Menu (More)

**Platform:** Zebu Helpdesk — Staff Portal (Flutter, Android/iOS) **Module:** Menu / More **Document Version:** 2.0 (Revised Edition — supersedes 1.0) **Date:** August 2026 **Status:** Current **Classification:** Internal Use Only

---

## Document Control

| Field | Value |
|-------|-------|
| Document Title | Menu (More) — Business Requirements Document |
| Module Scope | The Menu tab: the profile header, the grouped navigation menu (**Workspace** and **Resources**), the appearance theme toggle, and sign-out. Specifies **functional behaviour only** — visual styling (colours, themes, animation) is out of scope. |
| Menu Destinations | **Inbox**, **Agent Directory**, **Reports**, **Knowledgebase**, **Canned Responses**, **Profile**. Each destination screen is specified in its own BRD (NT, AG, RP, FQ, CR, PR); this document covers only the menu entry, its visibility, and the navigation into that screen. |
| Audience | Quality Assurance, Product Management, Engineering |
| Source Truth | Flutter source at `lib/features/more/more_screen.dart`, `lib/models/me.dart`, `lib/core/router/routes.dart`, `lib/data/agent_directory.dart` |

### Revision history

| Version | Date | Change |
|---------|------|--------|
| 1.0 | Aug 2026 | Initial edition — MO-001 … MO-004. |
| 2.0 | Aug 2026 | Rewritten against the shipping build. **MO-002** re-specified: **Users**, **Organizations** and **Saved Queues** are removed from the app (the web hides them from all staff), and **Reports** moves from Resources to Workspace. Menu entries are now permission-gated — new **MO-005** (visibility rules, with the who-sees-what matrix) and **MO-006** (destination map). MO-003 / MO-004 unchanged in behaviour. |

### Not in this module

Users (US), Organizations (OR) and Saved Queues (QU) no longer exist in the app — no screen, no route, no menu entry. Their BRDs are withdrawn; mark any residual case **Not Applicable**, not Failed. The old Reports charts screen is likewise gone — those charts now live on the **Dashboard** (`DB-005`, `DB-007`), and **Reports** is the reissued *Reports & Exports* module (RP).

---

## 5. Access & Visibility Summary

The menu is built from the signed-in agent's `GET /me` payload. Two entries are gated; everything else is visible to every signed-in agent.

| Menu entry | Who can see it | Permission required | Web equivalent |
|------------|----------------|---------------------|----------------|
| Profile header → **Profile** | Every signed-in agent | — | Staff panel → profile |
| **Inbox** | Every signed-in agent | — | — |
| **Agent Directory** | Every signed-in agent (the *list inside* is narrowed — see MO-005) | — to open; `visibility.agents` widens the roster | `scp/directory.php` |
| **Reports** | Only agents holding `reports.export` | `reports.export` — the agent's own grant **or** any role they hold | `reports` tab in `class.nav.php`, `scp/reports.php` |
| **Knowledgebase** | Every signed-in agent (browsing is open; **Add New Category** is gated) | — to browse; `faq.manage` to add a category | `kbase` tab, `scp/categories.php` |
| **Canned Responses** | Only agents holding `canned.manage` | `canned.manage` on one of the agent's roles | `kbase` sub-nav, `scp/canned.php` |
| **Appearance**, **Sign out** | Every signed-in agent | — | — |

### Rules that apply to every gated entry

| Rule | What it means for a test run |
|------|------------------------------|
| No admin bypass | The web reads the permission map directly, with no admin override, and the app matches it. An admin account without `reports.export` does not see **Reports**. |
| A hidden entry is not a defect | The gated screens are reachable only from this menu, so with the permission absent the module simply cannot be exercised. Record the account used for the run instead of raising a bug. |
| Nothing flickers | While `/me` is still loading, a gated entry stays hidden rather than appearing and then disappearing. |
| Unpublished permission = entry shown | If this install's `/me` never sends a permission code at all, the entry falls open and the backend remains the real guard. This is live today for `reports.export`: the app's bearer-token API path does not register that code, so **in the current build Reports is visible to every agent**. It will narrow to the matrix above with no app change once the backend publishes the code (see `BACKEND_FIX_reports_permission.md`). |

---

## 6. Functional Requirements

### 6.1 MO-001 — Menu screen and profile header

| Field | Value |
|-------|-------|
| Description | The Menu screen shows the agent's profile summary at the top, above the grouped menu, with a back affordance that returns to the Dashboard. |
| Acceptance Criteria | - The app bar title reads **Menu**; its back button (tooltip **Back to Dashboard**) navigates to the Dashboard tab (this is a root tab with nothing to pop)<br>- A profile header card shows the agent's avatar with a live availability dot, the **name** with an **ADMIN** badge for admin agents, the **email**, and a chip row of the availability status (**Available** / **Away** / **On vacation**), the primary **department**, and the **role**<br>- The department and role chips are omitted when the account has no primary department or no role name<br>- Tapping the profile header opens the **Profile** screen (`PR-001` onward)<br>- While the agent profile loads, a loading view is shown in the header area; on failure an error view with **Retry** that re-fetches the profile<br>- Visible to **every signed-in agent**; no permission is involved |
| Priority | High |

### 6.2 MO-002 — Workspace and Resources menu

| Field | Value |
|-------|-------|
| Description | The menu groups navigation destinations into a **Workspace** section and a **Resources** section. |
| Acceptance Criteria | - A **WORKSPACE** section lists, in order: **Inbox** (with the unread-count badge), **Agent Directory**, **Reports**<br>- A **RESOURCES** section lists, in order: **Knowledgebase**, **Canned Responses**<br>- **Users**, **Organizations** and **Saved Queues** do not appear in either section, for any account<br>- The Inbox badge shows the unread notification count, is hidden when the count is zero, and reads **99+** above 99<br>- The badge count matches the badge on the Alerts item in the bottom navigation bar<br>- Tapping any entry opens that feature's screen (see MO-006)<br>- **Reports** and **Canned Responses** appear only for accounts holding the permission (see MO-005); the sections render correctly with those entries absent |
| Priority | High |

### 6.3 MO-003 — Appearance theme toggle

| Field | Value |
|-------|-------|
| Description | An inline segmented control sets the app's theme mode. |
| Acceptance Criteria | - An **APPEARANCE** section shows a segmented control with **System**, **Light** and **Dark**, with the current mode selected<br>- Selecting an option changes the app's theme immediately, across every screen<br>- The choice persists across app restarts<br>- **System** follows the device's light/dark setting<br>- Visible to **every signed-in agent** |
| Priority | Medium |

### 6.4 MO-004 — Sign out

| Field | Value |
|-------|-------|
| Description | A sign-out action ends the session and returns to login. |
| Acceptance Criteria | - A **Sign out** button is shown at the bottom of the menu<br>- Tapping it shows a confirmation reading **Sign out?** with the message **You will need to sign in again to continue.** and a destructive **Sign out** confirm<br>- Cancelling leaves the session untouched and stays on the Menu<br>- On confirm, the session is ended and the app navigates to the **Login** screen, with no blank or black screen in between<br>- After signing out, the back gesture cannot return to any in-app screen<br>- Visible to **every signed-in agent** |
| Priority | Medium |

### 6.5 MO-005 — Menu entry visibility by permission

| Field | Value |
|-------|-------|
| Description | Gated menu entries appear only for accounts whose `GET /me` permissions allow the destination, mirroring the web's staff navigation. Testers must record which account each run used. |
| Acceptance Criteria | - **Reports** is shown only when the account holds **`reports.export`**, either as its own grant or through any role it holds; otherwise the entry is absent<br>- **Canned Responses** is shown only when one of the account's roles holds **`canned.manage`**; otherwise the entry is absent, and cases `CR-001 … CR-004` are unreachable by design<br>- **Inbox**, **Agent Directory** and **Knowledgebase** are shown to every agent<br>- **Being an admin does not bypass a gate** — an admin account lacking the permission does not see the entry, exactly as on the web<br>- While the profile is still loading, gated entries are hidden rather than flickering into view<br>- A permission code this install never publishes leaves its entry visible, with the backend rejecting the action if it is not truly allowed; this currently applies to `reports.export`, so **Reports** shows for every agent in the present build<br>- Inside **Agent Directory**, an account without **`visibility.agents`** sees only agents from its own departments, under the note **Agents in your departments**; an account holding `visibility.agents` sees the full roster with no note (`AG-001`)<br>- Inside **Knowledgebase**, the **Add New Category** action is shown only to an account holding **`faq.manage`**; browsing categories and articles is open to every agent (`FQ-001`) |
| Priority | High |

### 6.6 MO-006 — Menu destinations

| Field | Value |
|-------|-------|
| Description | Each menu entry opens the correct screen, and returning from it lands back on the Menu. |
| Acceptance Criteria | - **Inbox** opens the notifications screen titled **Inbox** — the same screen as the Alerts bottom-nav tab (`NT-001` onward)<br>- **Agent Directory** opens the screen titled **Agent Directory** (`AG-001`, `AG-002`)<br>- **Reports** opens the screen titled **Reports & Exports** (RP, reissued edition) — not the retired charts screen<br>- **Knowledgebase** opens the screen titled **Knowledgebase** (`FQ-001` onward)<br>- **Canned Responses** opens the screen titled **Canned Responses** (`CR-001` onward)<br>- The profile header opens the screen titled **Profile** (`PR-001` onward)<br>- Every destination is pushed over the Menu: its back affordance returns to the Menu with the section scroll position intact<br>- The bottom navigation bar remains usable, and switching tabs and back preserves the Menu's state |
| Priority | High |

---

*Total: 6 cases (MO-001 … MO-006). Supersedes version 1.0 in full.*
