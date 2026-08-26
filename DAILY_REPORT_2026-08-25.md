```
*📋 Daily Report — 25 Aug 2026*
*Patch: 1.0.0+1*

*Scope: app brought in line with the osTicket staff web* — 4 modules removed · 3 rebuilt · 19 backend gaps documented

━━━━━━━━━━━━━━━━━━━━

*1. Users, Organizations and Saved Queues removed*
• Issue: The app carried three modules the web hides from every staff account — the web's Users tab is switched off for agents and admins alike, and Organizations was only its sub-menu.
• Fix: Screens, routes, repositories, models and menu icons deleted; the users repository trimmed to the two calls still needed.
• Changed: Menu had Users / Organizations / Saved Queues ➝ they no longer appear; `/users` kept only for the ticket requester search and "create new requester".

━━━━━━━━━━━━━━━━━━━━

*2. Menu entries are now permission-gated (no admin bypass)*
• Issue: Every agent saw Reports and Canned Responses regardless of their role; the web hides both unless the permission is granted.
• Fix: Ported the web's nav rules — Reports needs *reports.export*, Canned Responses needs *canned.manage*; Knowledgebase and Agent Directory stay open to all.
• Changed: Menu built from a fixed tab list ➝ built from the account's `/me` permissions; an admin without the grant is hidden the entry too.

━━━━━━━━━━━━━━━━━━━━

*3. Reports permission never reaches the app (backend owed)*
• Issue: *reports.export* and *stats.agents* are missing from `/me` when the app signs in with a token — they appear when the same endpoint is opened in a browser, so the gate could never fire.
• Fix: Traced to the token bootstrap loading fewer permission classes than the browser session; the Reports entry deliberately falls *open* on a permission the server never publishes, so nobody is locked out by a backend gap.
• Changed: One-line backend fix written up; until it ships the Reports tile shows for everyone, while every report route still refuses on its own.

━━━━━━━━━━━━━━━━━━━━

*4. Agent Directory scoped to your departments*
• Issue: The directory listed every active agent in the system; the web lists only agents in your own departments.
• Fix: Roster filtered the same way as the web, with an "Agents in your departments" note above the list; an agent holding *view-agents* still sees the full roster.
• Changed: All active agents ➝ your departments only (falls back to the full list when a department can't be proven, so nobody disappears wrongly).

━━━━━━━━━━━━━━━━━━━━

*5. Reports rebuilt as "Reports & Exports"*
• Issue A: The old Reports screen was a charts page (day-range dropdown, Opened/Closed/Net card, line chart) that does not exist on the web.
   Fix: Screen deleted; the charts were kept and moved onto the *Dashboard*, where the web also shows them.
   Changed: Reports tab = charts ➝ Dashboard = charts.

• Issue B: Exports were hard-coded — nine fixed ticket columns, one department/topic at a time, no task export, no date window on users/orgs.
   Fix: Rewritten against the backend's new report endpoints: *Records* tab (Tickets / Tasks / Users / Organizations ➝ filters ➝ column picker ➝ download) and *Statistics* tab (Department / Help Topic / Agent over a date window).
   Changed: Columns and filters decided by the app ➝ served by the API, custom form fields included; downloads use a signed link and come out as PDF, Excel or CSV.

• Issue C: Reports sat in the wrong menu section.
   Fix: Moved under *Workspace* with Inbox and Agent Directory, matching the web.
   Changed: Resources ➝ Workspace.

━━━━━━━━━━━━━━━━━━━━

*6. Ticket create — due date and assignee*
• Issue A: The due-date field locked itself from the SLA dropdown alone, so "System Default" read as "no plan" and a typed date was silently replaced by the server's SLA date.
   Fix: The server's lock stays authoritative until the agent picks a plan themselves; choosing a help topic resets it to the server's word, exactly as the web does.
   Changed: Locked from the dropdown ➝ locked from the server, then from the selection once the agent chooses.

• Issue B: "Assign to agent" came pre-filled with the agent creating the ticket.
   Fix: Left blank — that value is the requesting agent, not an intended assignee.
   Changed: Pre-filled with yourself ➝ blank until you choose.

━━━━━━━━━━━━━━━━━━━━

*7. Knowledgebase — category Type and Add New Category*
• Issue: Category tiles showed only an article count and there was no way to add a category; the web shows a Type column and has an Add New Category action.
• Fix: Type (Private / Public / Featured) added beside the count, and an *Add new category* action gated on *faq.manage* — Name / Type / Description / Internal notes.
• Changed: Count only, no create ➝ Type column plus a create sheet. ⚠️ The create endpoint does not exist yet — the button fails until the backend ships it (spec written and handed over).

━━━━━━━━━━━━━━━━━━━━

*8. Canned Responses — full detail and edit*
• Issue: A canned response could only be viewed as text; the web has a full settings form (status, department, variables, attachments, internal notes).
• Fix: Detail sheet rebuilt to the web's form — Active / Disabled, department picker, supported-variable inserter, attachment add and remove, internal notes.
• Changed: Read-only preview ➝ create and edit with settings. ⚠️ The list payload still omits status, department and dates, so every row tags as *Global* and a disabled response cannot be re-enabled from the app — backend fix documented.

━━━━━━━━━━━━━━━━━━━━

*9. Profile screen rebuilt*
• Issue: The screen did not match the web's My Profile and could break its layout inside the app shell.
• Fix: Rebuilt as an identity card plus sections — availability toggle, Edit profile, Change password, Regenerate avatar — with a test that boots the real shell so the layout fault cannot come back.
• Changed: Flat list ➝ web-style profile page; layout fault ➝ covered by test.

━━━━━━━━━━━━━━━━━━━━

*10. Tester pack — BRD scope update + PDFs*
• Scope: The removed modules invalidate part of the BRD pack the tester is working from.
• Status: `BRD_SCOPE_UPDATE_2026-08-25.md` sent — *US, OR, QU (20 cases) marked Not Applicable*, *RP-001…006 void* pending a reissued Reports & Exports BRD, *MO-002* and *AG-001* reissued with new criteria. Revised pack: *14 modules · 132 cases* (was 17 · 152).
• Purpose: The whole BRD set renders to PDF now, so the pack ships as documents rather than markdown.

━━━━━━━━━━━━━━━━━━━━

*11. Backend requirements consolidated*
• Scope: One file — `BACKEND_REQUIREMENTS.md` — replacing the scattered per-issue notes.
• Status: 19 numbered gaps, P0 ➝ P3, each with the symptom in the app, the cause in the API, the fix and how to verify; four report items already closed by the backend are marked Shipped.
• Purpose: A single hand-over list for the backend team; new gaps go into this file, not a new note.

━━━━━━━━━━━━━━━━━━━━

*Status:* All app-side changes are uncommitted on `main` — *252 tests green*, `flutter analyze` clean. A fresh build is needed before retesting. Three items are blocked on the backend: FAQ category create, the canned list fields, and the reports permission.

*Smoke test:* • Menu — Users / Organizations / Saved Queues gone, Reports under Workspace • Sign in without *canned.manage* — Canned Responses hidden (correct behaviour) • Agent Directory — only your departments, note shown • Reports ➝ Records — pick Tickets, set filters and columns, download PDF / Excel / CSV • Reports ➝ Statistics — Department / Help Topic / Agent over a date range • Create ticket — pick a help topic with an SLA, due date locks; assignee starts blank • Knowledgebase — Type column visible, Add New Category opens (backend error expected) • Canned response — open, change status and department, add an attachment, save • Profile — availability toggle, edit profile, change password
```
