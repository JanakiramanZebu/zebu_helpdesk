```
*📋 Daily Report — 21 Aug 2026*
*Patch: 1.0.0+1*

━━━━━━━━━━━━━━━━━━━━

*1. Empty attribute rows show a prompt (TC_440)*
• Issue A: An unset priority displayed "Normal" on list rows and a blank chip on detail, so the row never prompted.
   Fix: The model stops inventing a default — the web never substitutes one either.
   Changed: `J.str(j['priority']) ?? 'Normal'` ➝ `J.strNonBlank(j['priority'])`

• Issue B: Rows with no value rendered a hard dash instead of their prompt.
   Fix: The empty-value guard compared a corrupted em dash and never matched — corrected at 4 live sites on ticket + task detail.
   Changed: dead guard `value != 'â€”'` ➝ `value != '—'`

• Issue C: A collapsed row left its divider behind as a stray hairline.
   Fix: New `_DetailRow.isVisible`; the section draws dividers only for rows that actually render.
   Changed: divider per child ➝ divider per rendered row

• Tester note: verify on Assignee / Tags / Due date — Priority Level is required (*) on the web create form, so a genuinely empty priority cannot be produced there.

━━━━━━━━━━━━━━━━━━━━

*2. Custom fields section (TC_444 / TC_445 / TC_446)*
• Issue: The payload includes blank answers, so an all-empty form drew the "Ticket details" heading over an empty card.
• Fix: Every custom field now renders; unanswered ones read "—Empty—" and open the Edit fields sheet — the web's inline-edit link. Same on tasks, minus the tap (tasks have no Edit fields action).
• Changed: heading over an empty card ➝ every field listed, blanks marked "—Empty—" and tappable when the agent can edit
• TC_444: custom fields are admin configuration (Admin → Manage → Forms, attached to a Help Topic). Agents cannot create them and the app has no admin surface — the topic under test has none configured.
• TC_445: Pass as recorded — no custom field values, section correctly hidden.
• TC_446: Retest — the recorded result is about custom fields, but the case covers attribute rows (Status / Priority / Department / Assignee / Due date) opening the same picker as the ⋮ menu action.

━━━━━━━━━━━━━━━━━━━━

*3. Activity timeline (TC_450 / TC_451)*
• Issue: Adding or removing a collaborator did not update the Activity tab until the app was closed and reopened; same-second events could appear in the wrong order.
• Fix: The tags/collaborators refresh was the only path that never reloaded events — it does now; `collab` events got their own icon; ordering re-sorted on (timestamp, id) before reversing, since the API orders by timestamp alone.
• Changed: `_refreshSideData()` skipped events + `events.reversed` ➝ `unawaited(_loadEvents())` + `ThreadEvent.newestFirst()`

━━━━━━━━━━━━━━━━━━━━

*4. ⋮ menu permission groups (TC_459 – TC_464)*
• Issue: "Divider is missed" on four cases; Delete not visible on the agent account.
• Fix: The group-joining rule moved out of the ticket screen into `action_menu.dart` as `joinMenuGroups`, shared by both detail menus and pinned by 6 tests — a divider between every pair of non-empty groups, none leading, none trailing, never two in a row. The dividers were already correct; this makes it provable.
• Changed: private untested `_joinMenuGroups` ➝ shared `joinMenuGroups` + 6 regression tests
• TC_459: No group header is expected — TK-019 specifies dividers, not labels. Mark answered/overdue shows with `ticket.markanswered` OR `ticket.edit` on the ticket's department.
• TC_460 – TC_463: Pass. Dividers are emitted and verified; they render as a 1px hairline (#DDE2E7 light / #333333 dark) — subtle, not absent.
• TC_464: Delete is gated by `ticket.delete` on the ticket's department, so an agent without it correctly sees nothing. Check Admin → Agents → [agent] → Role before failing; re-open if the role does grant Delete.

━━━━━━━━━━━━━━━━━━━━

*5. Needs attention — Overdue tag (TC_41)*
• Issue: Overdue rows on the dashboard showed the ticket's age instead of the Overdue tag.
• Fix: The list API returns no `isoverdue`, so every row reported "not overdue"; the dashboard queries `view: overdue`, so the row is now told so explicitly.
• Changed: `AttentionRow(ticket: …)` ➝ `AttentionRow(ticket: …, overdue: true)`

━━━━━━━━━━━━━━━━━━━━

*6. Priority rail (TC_42)*
• Issue: The rail for a ticket with no priority painted at hairline contrast — it read as a rendering fault rather than "nothing set", and conveyed nothing to a screen reader.
• Fix: The no-priority fallback moved to a visibly neutral tone and the rail now carries the priority it stands for.
• Changed: `outlineVariant` (#DDE2E7 / #333333) ➝ `outline` (#C7CDD4 / #4A4A4A), plus Semantics "Priority X" / "No priority set"

━━━━━━━━━━━━━━━━━━━━

*7. Create ticket without Department / Assignee (TC_273.2)*
• Issue: The ticket was created but its creator could not trace it — no way to confirm support received it.
• Fix: The self-assign safety net bailed out whenever no department was chosen — exactly this case. The guard is gone, so an unknown or unseeable department self-assigns, the ticket stays reachable, and the resolved Department is readable on detail.
• Changed: `if (dept == null) return;` ➝ nullable dept through `Me.canSeeTicket(departmentId: dept?.id)`
• Tester note: Department is optional on the web too — `Ticket::open` validates `deptId` with `required => 0`, only Help Topic is mandatory. Suggest rewording the expected result to "created and remains visible to its creator"; "Validate the Department" will keep failing against correct behaviour.

━━━━━━━━━━━━━━━━━━━━

*8. SLA shows Default, ticket gets High (TC_429)*
• Issue: SLA reads "System Default" on the create form, the created ticket comes back on the High plan.
• Explanation: Not a defect. "System Default" means the server resolves the plan — Department SLA → Help Topic SLA → system default (`Ticket::selectSLAId`). That ticket's department is on High. The web behaves identically; the create screen cannot preview it because the form is fetched per help topic while the deciding factor is the department. To fix the plan, pick it on the SLA plan row.
• Fix (code): The due-date lock now follows the server's `sla_locked` until the agent actually picks a plan — "System Default" was being read as "no plan", wrongly unlocking a due date the server then overwrote.
• Changed: lock derived from the selection immediately ➝ server's flag until the agent picks, then the selection
• TC_429's own criterion passes: Attributes shows Status, Priority, Department, Assignee and Due date (plus Help topic, Source, SLA plan, Tags).

━━━━━━━━━━━━━━━━━━━━

*9. Bounce / NDR ticket would not open (#027085)*
• Issue A: The ticket sat on an endless spinner — the app stayed responsive, the server simply never answered.
   Fix: Every API call now runs under a hard deadline with its own cancel token. Dio's own timeouts cannot catch this — connect covers only the socket, receive only the pause between chunks of a reply that already started.
   Changed: connect 20s / receive 30s only ➝ plus a 45s request deadline (5 min for uploads and downloads)

• Issue B: One slow call held the whole screen hostage.
   Fix: Only `GET /tickets/{id}` is fatal now; the conversation and the activity log load on their own, each with its own spinner, error and Retry — the web's ticket page renders its info panel the same way.
   Changed: ticket + thread + events awaited in series ➝ ticket first, thread and activity per tab

• Still open (backend): the ticket now opens, but that message body still will not render. `V2ThreadSerializer::richHtml()` re-sanitises the stored body on every request, which the web's display path never does; an NDR wraps the whole original mail, so it grinds. One-line backend fix, not approved.

━━━━━━━━━━━━━━━━━━━━

*10. Composer — emoji picker removed*
• Issue: The app offered emoji entry that osTicket does not have.
• Fix: Picker sheet and its button deleted from the message composer.
• Changed: "+" and emoji buttons inside the field ➝ "+" only (~150 lines removed)

━━━━━━━━━━━━━━━━━━━━

*11. Backend asks — documented, none applied*
• Scope: `isoverdue` + `due` on the list serializer; `addMissingFields()` and the web's visibility exclusions for custom fields; richer custom-field shape (id / editable / form grouping); `objectEvents()` ordered by (timestamp, id); thread `richHtml()` double-sanitise.
• Status: Written up and handed over — no backend work approved; app-side workarounds shipped wherever one exists.
• Purpose: Overdue chips on the tickets list, custom fields on already-created tickets, NDR message bodies, stable event ordering.

━━━━━━━━━━━━━━━━━━━━

*Status:* 10 items fixed app-side, all uncommitted on `main` — 109/109 tests pass, `flutter analyze` clean. Needs a build before anything above can be retested. One gap left open by choice: the tickets list still shows no Overdue chip (same missing `isoverdue`; fixable for the Overdue tab only, awaiting go-ahead).

*Smoke test:* • Dashboard Needs attention — Overdue tag + priority rail • Ticket detail Details tab — empty rows prompt, custom fields read "—Empty—" • Add/remove a collaborator → Activity updates immediately, Created stays last • ⋮ menu on a limited agent — groups separated, no stray dividers • Create a ticket with no Department → lands on detail and stays in your list • Create with SLA left on System Default → due date stays locked • Open ticket #027085 → screen opens instead of spinning • Composer — "+" only, no emoji button
```
