```
*📋 Daily Report — 24 Aug 2026*
*Patch: 1.0.0+1*

*Test cases worked: 38* — 19 Fixed · 17 Explanation given · 2 In progress

━━━━━━━━━━━━━━━━━━━━

*✅ Fixed (19)*

• *TC_511 / TC_512* — Tags: add-one-at-a-time sheet replaced with a multi-select + Save; a removal now saves instead of reading as "removed but can't save".
• *TC_517* — "Enter at least one ticket number" moved from a toast over the Link/Merge dialog to an inline field error that clears on typing.
• *TC_593* — Due date range now follows the web on every screen: today at the earliest, up to 3 years out.
• *TC_601* — Task create: a past due date showed no error (server returns numeric field ids). Errors are now mapped to the right field and shown.
• *TC_621* — "N total" under the app-bar title went stale on tab *swipe* and again after applying a filter/search — both paths now recount.
• *TC_650* — Tags row added to the task Details tab, so the Tag filter facet can actually be verified.
• *TC_662* — Task dependency picker added — a blocker can now be chosen and the task blocked.
• *TC_788 – TC_791* — Task detail / dependency screen fixes shipped along with the picker above.
• *TC_792 / TC_793 / TC_799 – TC_803* — Dependency batch: the server's real rejection reason is now surfaced (was one generic "Could not add"), and a silently-failed remove is detected. Most of these were one cascade — the tester's build predates the picker, so retest on the new build.
• *Extra (not filed)* — Subtask create failed ("Could not create task"): the sheet posted only title + description; department and due date are required. Now reuses the full create form.

━━━━━━━━━━━━━━━━━━━━

*📝 Explanation given (17)*
TC_539, TC_540, TC_541, TC_542, TC_543, TC_546, TC_547, TC_548, TC_549, TC_561, TC_663, TC_758, TC_810, TC_811, TC_821, TC_822, TC_846

• Each was checked against the web / BRD and behaves as designed — comments written on the sheet, no code change needed.
• Example: *TC_663* — "tapping a task row opens Conversation" is correct; TS-010 opens Task Detail and Conversation is its first tab.

━━━━━━━━━━━━━━━━━━━━

*🔄 In progress (2)*
• *TC_661* — under analysis.
• *TC_722* — under analysis.

━━━━━━━━━━━━━━━━━━━━

*Status:* All fixes are app-side and uncommitted on `main` — test suite green, `flutter analyze` clean. A fresh build is needed before any of the above can be retested.

*Smoke test:* • Task/ticket Tags — add + remove several, Save once • Link/Merge with an empty number field — error appears under the field • Create a task with a past due date — error on the Due date field • Swipe between tabs and apply a filter — "N total" follows • Task Details — Tags row visible, Tag filter works • Add a dependency from the picker → task shows Blocked • Create a subtask — succeeds and shows its parent
```
