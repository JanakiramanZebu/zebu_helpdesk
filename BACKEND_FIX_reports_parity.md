# Backend gaps — mobile Reports & Exports vs the web page

The mobile Reports screen now mirrors `scp/reports.php`: four record types with
counts, the same filters, a column grid with All / None, and a download. Three
things still cannot match, all because of the API rather than the app.

Nothing here is urgent — the screen works today. Each item says what it costs
to close.

---

## 1. Ticket columns are fixed at nine (the big one)

The web offers ~35 ticket columns: Source, From Email, Last Updated, SLA Plan,
SLA Due Date, Closed Date, Overdue, Merged, Linked, Answered, Team Assigned,
**plus every ticket-form custom field** (on this install: Client Id, Account
Name, Vendor Name, Products, Sub Issue Categories, Impact, Description,
Resolution, Known/Unknown Issue, Resolution Status, RCA Performed, Preventive
Action, Escalation/Collaboration Department).

The app can offer **nine**, because that is what the server emits:

```php
// include/api/v2/class.tickets.php :: exportTickets()  (~line 348)
$cols = array('number','subject','status','priority','department',
              'assignee','requester','created','due');
```

The column set is hard-coded, and the ticket *list* serializer carries even
less (7 fields — no assignee, no due date). There is no API surface through
which a caller can ask for a different column set.

**Fix:** accept a `columns` query parameter on `GET /tickets/export` and drive
the `values()` + `fputcsv()` from it, reusing `reports_fields_for('tickets')`
from `scp/reports.php` so the two pages agree on names and labels. Custom
fields need the same `cdata.<name>` traversal `Export::dumpQuery()` already
does.

Until then, the app's column picker is honest but short, and the custom fields
that carry most of this install's reporting value (Client Id, Impact, RCA
Performed …) cannot be exported from mobile at all.

---

## 2. Department / Help Topic / Agent take one id, not a list

The web filters with `dept_id__in (…)`, `topic_id__in (…)`, `staff_id__in (…)`.
The API takes a single id for each:

```php
// include/api/v2/class.tickets.php :: applyAdvancedFilters()  (~line 225)
if (($v = (int) $this->q('dept_id')))     $tickets->filter(array('dept_id'  => $v));
if (($v = (int) $this->q('assignee_id'))) $tickets->filter(array('staff_id' => $v));
if (($v = (int) $this->q('topic_id')))    $tickets->filter(array('topic_id' => $v));
```

Only `status_id` and `tag_id` accept a comma list, via the `idList()` helper
that is already in the same file.

**App-side workaround (shipped):** the pickers are true multi-selects, and the
screen requests the **cross product** of the selections, then unions the
results. A ticket has exactly one department, one topic and one assignee, so
the combinations are disjoint — counts sum exactly and rows concatenate without
duplicates. It is capped at 24 combinations, and the screen says so when a
selection is trimmed.

The cost is request volume: 3 departments × 2 topics = 6 requests per count and
6 more per export.

**Fix (three lines, removes the fan-out entirely):**

```php
-if (($v = (int) $this->q('dept_id')))     $tickets->filter(array('dept_id'  => $v));
-if (($v = (int) $this->q('assignee_id'))) $tickets->filter(array('staff_id' => $v));
-if (($v = (int) $this->q('topic_id')))    $tickets->filter(array('topic_id' => $v));
+if (($v = $this->idList('dept_id')))      $tickets->filter(array('dept_id__in'  => $v));
+if (($v = $this->idList('assignee_id')))  $tickets->filter(array('staff_id__in' => $v));
+if (($v = $this->idList('topic_id')))     $tickets->filter(array('topic_id__in' => $v));
```

`idList()` already accepts `"3"`, `"3,4,5"` and repeated params, and the app
already sends comma lists for `status_id`, so this is backward compatible. The
same change applies to `class.tasks.php :: applyTaskFilters()` for `dept_id` /
`assignee_id`.

---

## 3. `/users` and `/organizations` have no date filter

`listUsers()` and `OrganizationsV2Controller::list()` accept only `q` — no
`created_from` / `created_to`, unlike the ticket and task lists.

**App-side workaround (shipped):** the Users and Organizations reports page the
whole list and apply the created-date window client-side, and the screen says
so under the date fields. With no date set it is one request for the count;
with a date set it pages everything (3,554 users ≈ 36 requests).

**Fix:** add the same two lines those other controllers already have:

```php
if (($v = trim($this->q('created_from', '')))) $users->filter(array('created__gte' => $v.' 00:00:00'));
if (($v = trim($this->q('created_to',   '')))) $users->filter(array('created__lte' => $v.' 23:59:59'));
```

### Smaller, same family

- **Users report has no Organization column** and **Organizations has no
  Account Manager column** — both live only on the `{id}` detail payload, not
  the list row. Adding `org__name` to the user list `values()` and the manager
  to the org list row would close both.
- The org list already does an N+1 (`Organization::lookup()` per row for
  `getNumUsers()`); paging 5,000 rows for an export makes that noticeable.

---

## Also worth knowing

The reference tree at `D:\John\John flutter\zebu-os-ticket-main` is **behind
the live site**. `include/staff/reports.inc.php` there renders Status as a
three-option dropdown (All / Open / Closed), while the live page shows a
multi-select status list with "— Any open status —", "— Any closed status —"
and individual statuses. The mobile screen follows the reference tree
(All / Open / Closed). If the live behaviour is wanted, the reference copy
needs refreshing first so there is something authoritative to port.
