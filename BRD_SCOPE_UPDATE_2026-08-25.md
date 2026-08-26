```
*📄 BRD Scope Update — 25 Aug 2026*
*Patch: 1.0.0+1*

*Withdrawn: 3 modules · 20 cases* · *Rewritten: 1 module · 6 cases* · *Changed: 2 cases*

━━━━━━━━━━━━━━━━━━━━

*🚫 Out of scope — skip these BRDs entirely (20 cases)*

• *US — Users* (US-001 … US-007)
• *OR — Organizations* (OR-001 … OR-008)
• *QU — Saved Queues* (QU-001 … QU-005)

• Reason: the web helpdesk hides these from all staff — the Users tab is switched off in the staff navigation, and Organizations was only its sub-menu. Mobile now matches the web.
• The screens, routes and menu entries are removed from the app, so there is nothing left to open. Please mark every case in these three BRDs as *Not Applicable*, not as Failed.

━━━━━━━━━━━━━━━━━━━━

*♻️ Rewritten — RP (Reports), 6 cases — do not test yet*

• *RP-001 … RP-006* are void. They describe the old charts screen (day-range dropdown, Opened/Closed/Net card, activity line chart), which no longer exists.
• Reports is now *Reports & Exports*, matching the web: record type (Tickets / Tasks) ➝ filters (created-date range, status, department, help topic) ➝ column picker ➝ download PDF or Excel, with a live record count.
• The charts were not deleted — they live on the *Dashboard*. Test them under *DB-005* and *DB-007* instead.
• A reissued RP BRD will follow; hold this module until then.

━━━━━━━━━━━━━━━━━━━━

*✏️ Changed — retest with these criteria*

• *MO-002 (Workspace / Resources menu)* — the menu now reads:
   Workspace: *Inbox* · *Agent Directory* · *Reports*
   Resources: *Knowledgebase* · *Canned Responses*
   Users, Organizations and Saved Queues no longer appear.

• *AG-001 (Agent directory list)* — no longer every active agent. It now shows only agents in your own departments, with an *"Agents in your departments"* note above the list. An agent holding the *view-agents* permission still sees the full roster.

━━━━━━━━━━━━━━━━━━━━

*🔐 Menu entries are now permission-gated — use the right account*

• *Reports* — visible only with the *reports.export* permission.
• *Canned Responses* — visible only with *canned.manage* on one of your roles. Without it, *CR-001 … CR-004* cannot be reached at all — that is correct behaviour, not a defect.
• *Knowledgebase* and *Agent Directory* stay visible to every agent.
• *Being an admin is not a bypass* — the web behaves the same way. An account without the permission does not see the entry, admin or not.
• Please note which account each run used, so a missing menu entry is not raised as a bug.

━━━━━━━━━━━━━━━━━━━━

*Revised pack:* 14 modules · *132 cases* (was 17 modules · 152 cases).
*Tester guide:* Flow 9 becomes Agent Directory only; Flow 10 drops Saved Queues; Reports moves from Resources to Workspace.
*Status:* App-side changes, uncommitted on `main` — test suite green, `flutter analyze` clean. A fresh build is needed before retesting.
```
