# Web UI redesign — handoff

Last updated **2026-08-13**. Branch `helpdesk-web`. HEAD is `28e81e9 UI-5`
(2026-08-12) — the shared-widget extraction in §4 is committed there. Only the
new-ticket dialog work is still in the working tree: three modified files plus
`property_rows.dart`, `property_menu.dart` and `property_menu_test.dart`
untracked.

This document exists so a fresh session can pick the work up without re-reading
weeks of conversation. It records **decisions and their reasons**, not code —
the code is the source of truth for *what*, this is the source of truth for
*why*.

---

## 1. What this project is

A Flutter web client for an osTicket `/api/v2` staff console. The mobile tree
exists but is **out of scope** — the user's instruction is *"no need of mobile
we only focus on web"*. Web branches are behind `kIsWeb`; state is Riverpod;
routing is `go_router` with `StatefulShellRoute.indexedStack`.

The work is a screen-by-screen redesign driven by the user and their manager,
usually with reference screenshots. Completed in order:

ticket thread / chat view → status & priority badges → filter popover →
tasks-screen parity → notifications / inbox → bulk-action bar → create FAB →
shared dialog system → **new-ticket dialog** (in progress).

## 2. Standing rules

| Rule | Source |
|---|---|
| **Zebu naming only** — never "Mynt" in a file, class or identifier | *"dont use mynt word for files also classes also"* |
| **No shadcn**, anywhere | *"yea dont use shadcn anywhere"* |
| **Web only** | *"ok no need of mobile we only ofcus on web"* |
| **Share, don't copy** — extract to `lib/widgets/web/` | *"yea ok sharing is ok and more or less both are same"* |
| Keep the app's **Inter font and ZebuTheme palette** when porting a design | stated during the chat-redesign import |

`D:\Flutter Web\Mynt-Plus-Web` is a live UI reference (scalper module,
portfolio-analysis, watchlist, Create SIP dialog). Take its patterns; leave its
vocabulary behind.

## 3. How the user works

- Design handoffs land in `C:\Users\Zebu\Downloads` and are referenced in
  passing ("its in my downloads local"). Check it sorted by date.
- Handoff `.dart` files are **specs, not working code**. `zebu_property_menu.dart`
  shipped with a layout bug that asserted the first time it ran.
- Read the doc comment at the top of a handoff — it usually says which parts to
  reuse from the app rather than reimplement.
- Feedback is blunt and arrives as screenshots with annotations. A follow-up
  question is not automatically a report that something is wrong.
- **Do not silently reverse an earlier approved decision.** Say that it was
  decided, why, and let the user choose.

Verification rhythm, every change:

```
dart format lib
flutter analyze lib          # error-free; 22 pre-existing info/warnings are known
flutter build web --debug    # must print: √ Built build\web
flutter test test/…
```

Apply larger edits with a Python script in the scratchpad using
`assert old in s` before each replacement — a failed assert aborts before
writing, so a stale pattern cannot half-apply. Re-read any file the user has
edited before formatting it.

## 4. Shared widgets (`lib/widgets/web/`)

Extracted from duplicated screen code; each is the single source for its shape.

| File | Owns |
|---|---|
| `thread_view.dart` | Chat bubbles, tails, note cards, date dividers, inline clock, attachments |
| `panel_header.dart` | Panel title block, rail toggle, icon/actions buttons, skeleton |
| `detail_fields.dart` | `ZebuFieldRow`, group labels, text/status/empty values |
| `status_badge.dart` | `StatusBadge`, `PriorityBadge` (glyph block is commented out by the user) |
| `hatched_card.dart` | 45° two-tone hatch + optional dashed edge |
| `bubble_shape.dart` | `ShapeBorder` speech-bubble tail |
| `zebu_dialog.dart` | `showZebuDialog`, `ZebuDialogShell`, field/input/primary button |
| `zebu_select.dart` | The dropdown **box** (static accent border at rest) |
| `zebu_avatar.dart` | Name-hashed avatar, 8 hue swatches |
| `zebu_data_grid.dart` | Table grid + `ZebuGridTextCell` |
| `bulk_action_bar.dart` | Dark floating pill, `primary` inline / rest in `⋯` |
| `property_rows.dart` | **New.** `ZebuPropertyGrid` — flat label→value property grid |
| `property_menu.dart` | **New.** `showZebuPropertyMenu` — the mock's dropdown |
| `anchored_popover.dart` | **New.** `ZebuAnchoredRoute` + anchor geometry + the popover tones and shadow |
| `zebu_date_picker.dart` | **New.** `showZebuDatePicker` — grid, time and Clear on one popover |
| `zebu_text_action.dart` | **New.** `ZebuTextAction` — borderless text action, `primary` / `danger` / `muted` |
| `form_fields.dart` | **New.** `ZebuSectionTitle`, `ZebuLabeledField`, `ZebuFormInput`, `ZebuSelectField` — shared by both create dialogs |

Resources: `lib/res/zebu_status_style.dart` maps every status and priority to a
badge style; `lib/res/zebu_theme.dart` holds all tones.

## 5. The new-ticket dialog (current work)

`lib/features/tickets/web/create_ticket_screen_web.dart`, reviewed field by
field.

**Done**

- `ZebuDialogShell`, 720 wide, footer kept because the form scrolls
- Requester + Collaborators 50/50 in one row
- Labels 12px semibold slate, 6px gap, inline ⚠ error row, no required asterisk
  (validation on submit says which field is missing, more precisely)
- Text inputs carry the same **static accent border** as `ZebuSelect` — focus
  deepens the colour rather than introducing it
- Subject hint is an example (`e.g. Unable to reset account password`), not a
  description of the field
- "Insert canned response" moved onto the **Message** label row as a text link —
  it writes into Message, and sat under Subject looking like a third input
- Options → **`ZebuPropertyGrid`**: eyebrow `PROPERTIES  all optional`, flat
  `label → value` rows, one hairline each, no boxes, no icons, dot on Status and
  Priority, two columns
- Menu → **`showZebuPropertyMenu`**: radius 10, hairline, soft shadow,
  right-aligned to the value, tinted selected row with trailing ✓, muted
  default entry, search at 6+ items, dots on Status/Priority entries
- Clearing moved into the menu (`None` / `Auto-assign` / `Open (default)`) since
  the rows have no X — and it is more discoverable there
- Due date → **`showZebuDatePicker`**: one anchored popover carrying the month
  grid, an inline time row and Clear, on the same card as the property menu.
  It replaced `showDatePicker` + `showTimePicker` — two centered Material
  modals stacked on a dialog that is itself a modal — plus the Change / Clear
  menu that only existed because `showDatePicker` cannot say "no date".
  Tapping a day selects; Apply commits; date-only mode commits on the tap.
  Dismissing returns null and changes nothing, which is why the result type is
  `ZebuDateResult` and not `DateTime?`. The footer link is just **Clear**, in
  `zebuPopoverDanger` `#C40024` with a `zebuPopoverDangerBg` `#FDECEC` pill
  that appears only on hover. Both are the user's exact values and are pinned,
  not taken from `t.danger` `#FF1717`, which is tuned for badges and error
  borders and reads hot as a text link
- Time is two **▲▼ steppers**, not text boxes. The boxes were rejected as
  confusing, and they clamped only on blur — `99` sat in the minute field
  looking accepted until you clicked away. The control is now a single
  minutes-since-midnight counter wrapped modulo the day, so minutes carry into
  the hour, midnight steps back to 23:59, AM/PM cannot disagree with the hour,
  and no invalid time is reachable rather than merely corrected. Arrows repeat
  while held, since one click per minute is otherwise 45 clicks to `:45`

**Not yet reviewed:** Attachments block, Internal note section, footer.

**User's own edits in `property_rows.dart` — do not revert.** They edit this
file directly and often, so re-read it before every change rather than trusting
this list. As of 2026-08-13 13:34 it carries: value weight `semiBold`; a
two-letter `code` tile before each label (DP/AG/TM/HT/ST/PR/SR/DD, 24×18,
tinted `zebuPropertyCodeBg`, accent 10px) which also widens the value's
reserved gutter from 96 to 126; and `TextDecoration.underline` re-enabled with
new semantics — **dashed while the row is empty, solid once it holds a value**,
hover only deepening the alpha from .55 to 1. An earlier version had the rule
commented out, and the one before that keyed dashed/solid to hover instead.

## 6. Open decisions

1. **Two menu styles coexist.** `showZebuPropertyMenu` (new, tick + fill) for
   the property grid; `showAppDropdown` (weight + colour, no tick) everywhere
   else. Rolling the new one out app-wide would reverse an earlier approved
   decision — the user has not answered.
2. **`copyWith(fontWeight:)` renders nothing.** `google_fonts` encodes weight in
   the family name (`Inter_500`), so a weight set after the fact is inert.
   **128 sites across 51 files**, counted 2026-08-13 by matching balanced parens
   and keeping only calls whose base is a `ZebuTextStyles.*` / `textTheme.*`
   style (an earlier estimate of 81/~30 scanned a narrower tree). Heaviest:
   `dashboard_screen_web.dart` 10, `orgs_list_screen_web.dart` 7,
   `login_screen_web.dart` 6, `profile_screen_web.dart` 6,
   `create_task_screen_web.dart` 6. Fix per call site, or centrally via a
   `TextStyle.weight()` extension that re-resolves the family. Not started.
3. **Dark mode** has had no pass on any redesigned screen.

## 7. Loose ends, flagged not fixed

- `tasks/web/task_detail_screen_web.dart` (~1555 lines) still routed at
  `/tasks/:id` though its features moved into the task panel — delete and
  repoint
- `create_task_screen_web.dart` is now on `ZebuDialogShell` and the shared
  `form_fields.dart`, so heading, labels, inputs, selects and footer match the
  ticket dialog by construction rather than by copy. It also shares the
  attachments block, the property grid and `showZebuDatePicker` — no web
  surface opens a Material picker any more. The three mobile screens still do,
  deliberately: mobile is out of scope. Still duplicated between the two
  dialogs: `_IconBtn`, `_MiniIcon`, `_ErrorBanner`, and the primary/secondary
  buttons the ticket dialog no longer uses
- `CreatePanel` + `_toggleCreate` in the shell are dead since the create FAB
- `_markAllRead` / `_deleteAll` / `_deleteGroup` / `_eventIcon` unreferenced in
  notifications; "delete all server-side" is unreachable from the UI
- Notifications still on a hand-rolled table, not `ZebuDataGrid`
- Emoji arriving as `-` — the Dart path is clean; almost certainly osTicket's DB
  charset (`utf8` vs `utf8mb4`). Fix supplied, not applied
- "Complete" on 50 selected tasks has no confirmation

## 8. Tests

`test/zebu_date_picker_test.dart` — ten widget tests: apply-with-time,
date-only commit-on-tap, Clear vs dismiss (the two answers the result type
exists to separate), no clear link when empty, range bounds, the year list,
chevron limits, an edited time riding along, and a short window capping the
panel instead of running it off the bottom.

**A trap the harness itself fell into:** the `Builder` that supplies the anchor
context must sit *inside* the widget being anchored to. Above it, the anchor
rect is the whole body and the popover is positioned off-screen — the taps then
miss and the failures look like logic bugs. `property_menu_test.dart` has the
same flaw but never taps a position, so it passes regardless.

`test/property_menu_test.dart` — four widget tests covering the property grid
and menu: the menu opens and returns a value, long lists filter (and keep the
clear entry), short lists get no search box, and values right-align regardless
of length. The last one catches the `Flexible` + `Spacer` trap in §9.

## 9. Traps that have bitten more than once

1. `Colors.transparent` is transparent **black** — animating from it washes
   through grey. Use `targetColor.withValues(alpha: 0)`.
2. `Align`, `Center`, `Container(alignment:)` **expand to fill**. Caused
   full-width bubbles, stacked filter chips, a stretched bulk bar.
3. `Flexible` and `Spacer` **both default to `flex: 1`** — in one `Row` they
   split free space equally, and a loose `Flexible` leaves its half as dead
   space.
4. `InputDecoration.border` is only a **fallback**; theme `enabledBorder` /
   `focusedBorder` win. Clear all six slots plus `filled`.
5. A non-flex child with a fixed `maxWidth` is laid out **before** flex children
   get the remainder, so it overflows narrow rows — cap it with a
   `LayoutBuilder`.
