# Backend Requirements — zebu_helpdesk mobile app

**Target API:** osTicket `/api/v2` (`scp/api.php` + `include/api/v2/*.php`)
**Client:** Flutter agent app (`zebu_helpdesk`, branch `main`)
**Compiled:** 2026-08-25 — supersedes `BACKEND_FIX_canned_list.md`,
`BACKEND_FIX_faq_category_create.md`, `BACKEND_FIX_reports_parity.md`,
`BACKEND_FIX_reports_permission.md`, `BACKEND_FIX_subtask_parent.md`

Everything the mobile app needs from the backend that the backend does not yet
provide. Each item states the **symptom in the app**, the **cause in the API**,
the **fix**, and how to **verify** it. Where the app already ships a client-side
workaround that is called out, so you can see what the fix buys back.

---

## 0. Index

| # | Area | Gap | Severity | App impact today |
|---|---|---|---|---|
| 1 | Knowledgebase | `POST /faq/categories` does not exist | **P0 — broken** | "Add New Category" returns 404 |
| 2 | Tasks | `POST /tasks` silently drops `parent_id` / `priority_id` | **P0 — broken** | Subtasks never appear under their parent |
| 3 | Permissions | `reports.export` / `stats.agents` never registered on token auth | **P0 — broken** | Reports menu can't be gated; falls open for everyone |
| 4 | Canned | `GET /canned` list omits status/scope/date; disabled rows unmanageable | **P1** | Wrong Global/Disabled tags; a disabled response can never be re-enabled |
| 5 | Tickets | `GET /tickets/{id}` omits source, topic, SLA plan, close date, last msg/resp | **P1** | Detail screen guesses or hides those rows |
| 6 | Tickets | `GET /tickets` list rows omit assignee / due date / dept id | **P1** | N+1 detail fetches to power search + Agent facet |
| 7 | Tickets | Filter params override the `view` scope | **P1** | All tab counts computed client-side by paging every row |
| 8 | Tasks | `GET /tasks/{id}` omits due date and tags | **P1** | Due date grafted from the list row; deep links show none |
| 9 | Agents | `GET /meta/agents` carries no department; no `dept_access` anywhere | **P1** | N+1 over `/agents/{id}`; assignee picker is approximate |
| 10 | Reports | `GET /tickets/export` column set is hard-coded at 9 | ~~P1~~ **Shipped** | Closed by the `/reports/*` export surface |
| 11 | Reports | `dept_id` / `topic_id` / `assignee_id` take one id, not a list | ~~P1~~ **Shipped** | Closed for reports; still one-id on the plain `/tickets` list |
| 12 | Reports | `/users` and `/organizations` have no date filter | ~~P2~~ **Shipped** | Closed for reports; still absent on the plain list endpoints |
| 13 | Reports | No `/tasks/export` endpoint | ~~P2~~ **Shipped** | Closed by `POST /reports/exports/tasks/link` |
| 14 | Users/Orgs | List rows omit Organization / Account Manager; org list is N+1 | **P2** | Report columns now served; the list rows and the N+1 are unchanged |
| 15 | Dashboard | No task report endpoint | **P2** | Task counts derived from four `/tasks` list totals |
| 16 | Notifications | No server-side filter or per-view counts | **P2** | Client-side filtering; only "Unread" has a badge |
| 17 | Canned | `isCannedResponseEnabled()` config flag unpublished | **P3** | Half the web's menu rule can't be honored |
| 18 | Knowledgebase | Category `pid` / full name not published | **P3** | "Funds / Pay in" renders as "Pay in" |
| 19 | Policy | Ticket creator gets no visibility on their own new ticket | **Decision** | App probes with a 404 check and warns |

---

# P0 — Broken today

## 1. `POST /faq/categories` — Knowledgebase category create

**File:** `include/api/v2/class.faq.php` → `FaqV2Controller` (+ one route line in `scp/api.php`)
**Needed by:** [faq_screen.dart](lib/features/faq/faq_screen.dart), [faq_repository.dart:46](lib/data/faq_repository.dart#L46) → `FaqRepository.createCategory`
**Status:** verified absent — the `^/faq` block at `scp/api.php:230` registers four `url_get`s and no `url_post`; the controller docblock says *"No create/edit here — those are deferred."*

The staff web has Knowledgebase → Categories → **Add New Category** (`scp/categories.php`).
The mobile app now has the same action and calls an endpoint that does not exist. **The
button returns 404 until this ships.** Article create/edit is deliberately *not* requested.

### Request

```
POST /api/v2/faq/categories
Authorization: Bearer <agent token>
Content-Type: application/json

{
  "name":        "Payins",                   // required, min 3 chars
  "type":        "private",                  // required: private | public | featured
  "description": "How pay-ins are handled",  // required
  "pid":         0,                          // required: parent id, 0 = top level
  "notes":       "internal only"             // optional
}
```

`pid` is the web form's **Parent** dropdown ("— Top-Level Category —" = `0`). The app now
sends it on every create and edit — see item 18 — so it must be stored, not hard-coded.

`type` is the lowercase form of the string `GET /faq/categories` already returns, so read
and write share one vocabulary. Map onto `category.ispublic` (`include/class.faq.php`):

| `type` | `ispublic` |
|---|---|
| `private` | 0 |
| `public` | 1 |
| `featured` | 2 |

An unknown `type` is a validation error, never a silent default.

### Handling

`CannedV2Controller::create()` (`class.canned.php:90`) is the template — same shape, one
model swap. Build `$vars` the way `scp/categories.php` does for `$_POST['a'] == 'create'`
and hand them to `Category::create()` (`class.category.php:345`) then `->update()` (`:168`),
so the model keeps ownership of validation:

```php
function createCategory() {
    $this->requireStaff(); $this->requireCsrf();
    if (!$this->requireStaffPerm(FAQ::PERM_MANAGE))
        $this->fail(403,'forbidden','Not allowed to manage the knowledgebase');
    $in = $this->bodyInput();

    $fields = array();
    if (!trim((string)($in['name'] ?? '')))          $fields['name'] = 'Required';
    if (!trim((string)($in['description'] ?? '')))   $fields['description'] = 'Required';
    if (!isset($map[strtolower($in['type'] ?? '')])) $fields['type'] = 'Invalid';
    if ($fields) $this->fail(422,'validation','Missing or invalid data',$fields);

    $vars = array(
        'name'        => trim($in['name']),
        'ispublic'    => $ispublic,          // mapped from $in['type']
        'pid'         => (int)($in['pid'] ?? 0),  // Parent dropdown; 0 = top level
        'description' => $in['description'], // update() runs Format::sanitize()
        'notes'       => $in['notes'] ?? '',
    );

    $errors = array();
    $cat = Category::create();
    if (!$cat->update($vars, $errors) || $errors)
        $this->fail(422,'validation','Could not create category',
            $this->normErrors($errors));

    return $this->created(/* same array `category($id)` builds */);
}
```

Route (`scp/api.php`, inside the existing `^/faq` block):

```php
url_post('^/categories$', array('FaqV2Controller','createCategory')),
```

Three rules `Category::update()` already enforces (`class.category.php:168-185`) must be
surfaced, not swallowed — all three arrive in `$errors` keyed by field:

* `name` required, **3 chars minimum** ("Name is too short. 3 chars minimum")
* duplicate `name` under the same parent → "Category already exists"
* `description` required

### Permission

`FAQ::PERM_MANAGE` = `'faq.manage'` (`include/class.faq.php:48`); `scp/categories.php:21`
gates the whole page on `$thisstaff->hasPerm(FAQ::PERM_MANAGE)`. Use the same check.
Reading the KB stays ungated, matching the web's `kbase` tab.

`faq.manage` **is** published to the app (`class.faq.php` is loaded by the bearer-token
bootstrap), so the client gate already works — this server check is the real one.

### Response

**201**, in the *same shape* as `GET /faq/categories/{id}` so the client parses one model:

```json
{ "data": { "id": 9, "name": "Payins", "public": false,
            "type": "Private", "faq_count": 0, "faqs": [] } }
```

Errors use the standard envelope; field keys must be the **request** keys (`name`, `type`,
`description`, `notes`) so they land on the right input:

```json
{ "error": { "code": "validation", "message": "",
             "fields": { "name": "Category already exists" } } }
```

`403` uses `code: "forbidden"`.

### Client behaviour to know

* The app pre-validates `name` (present, 3+) and `description`, so empty-field round trips
  should not normally reach you.
* On success it re-fetches `GET /faq/categories` — the new row must be visible immediately.
* `notes` is omitted from the payload entirely when blank.

---

## 2. v2 task create drops `parent_id` (and `priority_id`)

**File:** `include/api/v2/class.tasks.php` → `TasksV2Controller::create()`
**Affects:** `POST /tasks` **and** `POST /tasks/{id}/subtasks` (both run this method)
**Symptom:** a subtask is created but returns `parent_id: null` — it never appears under the
parent's Subtasks. Priority set at create time is lost the same way.

### Cause

`Task::create()` reads the parent and priority out of the **internal form's** clean data —
`class.task.php:2258` (`$vars['internal_formdata']['parent_id']`) and `:2268`
(`priority_id`) — and stamps them on the row **before** the insert. That is how the web does
it: `ajax.tasks.php::addSubtask()` puts `parent_id` into `TaskForm::getInternalForm()` as a
locked field (field id 5).

The v2 controller never puts them in the form source:

```php
// class.tasks.php:333
$src = array(
    'title'       => trim($in['title']),
    'description' => ThreadEntryBody::clean($in['description']),
    'dept_id'     => (int)$in['dept_id'],
    'duedate'     => $in['duedate'] ?? '',
);
```

so `$iform->getClean()` has `parent_id = 0`, the task is created unparented, and the
controller then patches the column afterwards:

```php
// class.tasks.php:382
if ($parentId)                  { $task->parent_id = $parentId; $changed = true; }
if (!empty($in['priority_id'])) { $task->priority_id = (int)$in['priority_id']; $changed = true; }
if ($changed) { try { $task->save(); } catch (Exception $e) {} }
```

**That save is failing on live and the `catch` swallows it**, so the parent is lost silently.

### Fix — put them in the form source, like the web

**1. `class.tasks.php:333` — add two keys to `$src`:**

```php
$src = array(
    'title'       => trim($in['title']),
    'description' => ThreadEntryBody::clean($in['description']),
    'dept_id'     => (int)$in['dept_id'],
    'duedate'     => $in['duedate'] ?? '',
    'parent_id'   => $parentId,                       // NEW — TaskInternalForm field id 5
    'priority_id' => (int)($in['priority_id'] ?? 0),  // NEW — TaskInternalForm field id 4
);
```

`$parentId` is already resolved at line 320 (route arg, else `$in['parent_id']`).

**2. `class.tasks.php:382` — drop parent/priority from the post-create patch, keep progress
(it is not a form field):**

```php
$changed = false;
if (isset($in['progress'])) { $task->progress = max(0, min(100, (int)$in['progress'])); $changed = true; }
if ($changed) { try { $task->save(); } catch (Exception $e) {} }
```

### Why this shape

One code path for web and API — no silent post-create patching that can fail unnoticed.
`Task::create()` re-validates the parent (unknown parent / no permission → `parent_id` error;
cycles impossible on a brand-new task) instead of writing an unchecked id. Errors keyed by
field id already work in the app: it maps 1=dept_id, 3=duedate, 4=priority_id, 5=parent_id
back to names.

**Heads-up:** once `priority_id` goes through the form, an unknown or **inactive** priority
id is rejected (422, field `4`) instead of written silently. That matches the web — please
confirm it is wanted.

### Verify

```
POST /api/v2/tasks/{parent}/subtasks
{ "title":"t", "description":"d", "dept_id":<parent dept>, "duedate":"<future>" }
→ 201 with  "parent_id": <parent>          (currently null)

POST /api/v2/tasks
{ "title":"t","description":"d","dept_id":1,"duedate":"<future>",
  "parent_id":<parent>,"priority_id":<active id> }
→ 201, "parent_id": <parent>, "priority": {...}

GET /api/v2/tasks/{parent}/subtasks  → the new task is listed
```

The app currently also sends `custom_fields: {parent_id, priority_id}` as a client-side
workaround (merged into `$src` at line 341 — same source). That keeps working after the fix
and can be removed from the app once it is live.

---

## 3. `reports.export` is never sent to the app

**Symptom:** the Reports entry can't be gated for **any** account — manager or admin.
**Not an app bug.** The permission never reaches the app, so there is nothing to check.

### Root cause

osTicket registers each permission from the bottom of the class file that owns it:

```php
// include/class.report.php:28  (last line of the file)
RolePermission::register(/* @trans */ 'Miscellaneous', ReportModel::getPermissions());
//                                    ^ stats.agents + reports.export
```

`scp/api.php` has **two** bootstraps, and only one ever loads that file:

| Path | Bootstrap | Loads `class.report.php`? |
|---|---|---|
| **Bearer token** (`Authorization: Bearer …`) — what the app uses | `require('../main.inc.php')` + `class.staff.php` | **No** |
| Session cookie (browser) | `require('staff.inc.php')` → `class.nav.php` → `class.report.php` | Yes |

```
scp/api.php:38-44        if ($__tokenMode) { main.inc.php + class.staff.php }
                         else             { staff.inc.php }
scp/staff.inc.php:117    require_once(INCLUDE_DIR.'class.nav.php');
include/class.nav.php:17 require_once(INCLUDE_DIR.'class.report.php');   <-- only reached here
```

`include/api/v2/class.reports.php` requires only `class.v2controller.php` — it does **not**
pull in the `ReportModel` that owns the permission.

**Consequence:** on the app's path `RolePermission::allPermissions()` has no
`reports.export`, so `MeV2Controller::allPermissionCodes()` omits it and `GET /me` returns it
in **neither** `global_permissions` nor any `permissions_by_department` map. `stats.agents`
is missing the same way. Open `/scp/api.php/me` with a staff *session* and `reports.export`
**is** there — only token auth is affected.

### Fix (one line)

```php
// include/api/v2/class.reports.php
 require_once INCLUDE_DIR.'api/v2/class.v2controller.php';
+require_once INCLUDE_DIR.'class.report.php';   // registers stats.agents + reports.export
```

Equivalent alternative — the token branch of `scp/api.php`:

```php
 if ($__tokenMode) {
     require('../main.inc.php');
     require_once(INCLUDE_DIR.'class.staff.php');
+    require_once(INCLUDE_DIR.'class.report.php');
 }
```

**Verify:** `GET /me` with a bearer token returns a `reports.export` key (value `1` or `0`)
inside `global_permissions` **and** inside each `permissions_by_department` entry.

### What the app does meanwhile

No app change is needed once this ships. `/me` writes an explicit `1`/`0` for every code it
knows, so an *absent* code was never registered. `Me.publishes()` detects that and
`Me._gate()` falls **open** — an entry the backend will refuse anyway beats one hidden from
everyone forever. **The moment this fix ships the real rule takes over automatically**, no
rebuild required. Covered by `test/menu_permission_gating_test.dart` → *"an unpublished
permission falls open"*.

**Still worth fixing, but no longer dangerous.** Every `/reports/*` route enforces
`reports.export` itself (global **or** any department role, the same dual check
`scp/reports.php` makes), so an agent without it now meets a `403` rather than a working
screen. The cost of the gap is a menu entry that shows for everyone and a 403 on tap, instead
of the entry being hidden.

### Worth checking at the same time

The same include-order trap applies to any permission whose owning class the token bootstrap
misses. Currently loaded and therefore safe: `class.staff.php` (`visibility.agents`),
`class.canned.php`, `class.faq.php`, `class.organization.php`, `class.user.php`,
`class.ticket.php`, `class.task.php`, `class.search.php`. Only `class.report.php` is missing.

---

# P1 — Payload and query gaps

## 4. `GET /canned` list payload + disabled-response management

**File:** `include/api/v2/class.canned.php` → `CannedV2Controller`
**Reference:** `include/staff/cannedresponses.inc.php`, `include/staff/cannedresponse.inc.php`
**Symptom:** every row shows the **Global** tag and never shows **Disabled**, whatever is in
the database; and a disabled response can no longer be opened, edited or re-enabled from the
app at all.

### Cause 1 — the list payload has no status/scope/date fields

```php
// class.canned.php:60
foreach ($qs->limit($limit)->offset(($page-1)*$limit)
        ->values('canned_id','title','response') as $r)
    $data[] = array('id' => (int) $r['canned_id'],
                    'title' => (string) $r['title'],
                    'body'  => (string) $r['response']);
```

`CannedResponse.fromJson` therefore falls back to defaults — `dept_id => 0`,
`is_enabled => true` — and the card draws its two tags from exactly those fields. The
osTicket staff list shows Title, **Status**, **Department** and **Last Updated**, plus a file
icon for non-inline attachments. None of the four is renderable from the current payload.

### Cause 2 — disabled responses can't be managed

`visibleCanned()` is the base queryset for `listCanned`, `retrieve`, `update`, `destroy`,
`attachments`, `uploadAttachment`, `deleteAttachment` **and** `expand`:

```php
// class.canned.php:17
$qs = Canned::objects()->filter(array('isenabled' => true))->order_by('title');
```

`isenabled => true` is right for the *composer* but is applied to the management endpoints
too. A disabled response is absent from `GET /canned` **and** 404s on
`GET/POST/DELETE /canned/{id}` — once anything is disabled, from the app or from osTicket
admin, there is no way back to Active through the API. `scp/canned.php` has no such
restriction: it lists every response in the agent's departments and offers bulk
Enable / Disable.

### Fix

**a. Widen the list serializer**

```php
foreach ($qs->limit($limit)->offset(($page-1)*$limit)
        ->values('canned_id','title','response','dept_id','isenabled',
                 'updated','dept__name') as $r)
    $data[] = array(
        'id'         => (int) $r['canned_id'],
        'title'      => (string) $r['title'],
        'body'       => (string) $r['response'],
        'dept_id'    => (int) $r['dept_id'],
        'dept_name'  => $r['dept__name'] ?: null,   // null => All Departments
        'is_enabled' => (bool) $r['isenabled'],
        'updated'    => Format::datetime($r['updated']),
        'files'      => (int) $attachmentCounts[$r['canned_id']],
    );
```

`files` mirrors the staff list's `count(attach.file_id)` join (`type='C' AND NOT
attach.inline`). `dept_name` saves the client a `GET /meta/departments` round-trip per row.

**b. Split composer visibility from management visibility**

Keep `visibleCanned()` exactly as-is for `expand()` and the ticket composer. Add:

```php
// Management scope — mirrors scp/canned.php: every response in a dept where the
// agent holds Canned::PERM_MANAGE, plus the global (dept_id=0) pool, regardless
// of enabled state.
private function manageableCanned() {
    global $thisstaff;
    $qs = Canned::objects()->order_by('title');
    if ($thisstaff) {
        $depts = $thisstaff->getDepts();
        $depts[] = 0;
        $qs->filter(array('dept_id__in' => $depts));
    }
    return $qs;
}
```

* `listCanned()` — accept `?include_disabled=1`, using `manageableCanned()` when the flag is
  set **and** `canManage()` is true; otherwise unchanged.
* `retrieve()`, `update()`, `destroy()`, `attachments()`, `uploadAttachment()`,
  `deleteAttachment()` — resolve through `manageableCanned()` when `canManage()` is true,
  else `visibleCanned()`. These already gate mutation on the same permission, so this grants
  nothing new; it only stops a disabled row 404-ing.
* `expand()` — leave on `visibleCanned()`. A disabled response must never be insertable.

**c. Expose filter usage on retrieve**

`Canned::getFilters()` backs the web's "Canned response is in use by email filter(s): …"
warning, and `Canned::delete()` refuses while `getNumFilters() > 0` (already surfaced as a
409). Adding `'filters' => array_values($c->getFilters()),` to `serialize()` lets the edit
sheet warn *before* the delete instead of only after the 409.

**d. Optional:** `?sort=title|status|dept|updated&order=asc|desc`, matching the four sortable
staff columns.

### Client work unblocked

| Change | Client follow-up |
|---|---|
| `is_enabled` in list | Status tag becomes truthful |
| `dept_id` + `dept_name` | Scope tag becomes truthful; can show the department name |
| `updated` | Can show "Last updated" |
| `files` | Attachment indicator on the row |
| `include_disabled=1` | Show disabled rows; Active/Disabled/All filter; bulk Enable/Disable |
| `filters` on retrieve | In-sheet "in use by email filter(s)" warning |

**Already shipped and working:** create/edit sends `dept_id`, `notes`, `is_enabled`;
attachments go through `POST|DELETE /canned/{id}/attachments`. The detail sheet re-reads
`GET /canned/{id}`, whose serializer *does* include `dept_id`, `is_enabled`, `notes` and
`attachments` — which is why detail is accurate while the list's tags are not.

---

## 5. `GET /tickets/{id}` payload gaps

**Consumers:** [ticket_detail_screen.dart](lib/features/tickets/ticket_detail_screen.dart), [models/ticket.dart](lib/models/ticket.dart)

The web's ticket view (`include/staff/ticket-view.inc.php`) shows fields the detail payload
does not carry. The model already parses every one of them tolerantly under several possible
key names, so **adding any of these is backwards compatible and needs no app change**:

| Field | Keys the model accepts | Missing today → app does |
|---|---|---|
| Source | `source` | Row hidden |
| Help topic | `topic` / `help_topic` / `helptopic` (string, `{id,name}` or bare `topic_id`) | Row hidden |
| SLA plan | `sla_plan` / `sla_name` / `slaplan` / `sla_plan_name` / `sla_id` | Shows only the remaining-time ring, not "High - 8h" |
| Due-date lock | `sla_locked` or `can_set_duedate` | **Guessed** from `sla.id > 0` |
| Close date | `closed_at` | Row hidden |
| Last Message / Last Response | `last_message` / `last_response` (+ `lastmessage`, `last_resp_date`) | Derived from the loaded thread |
| Organization | `organization` / `org`, or nested under `user` | Row hidden |

**The due-date lock is the one that matters.** The web renders a padlock instead of the
inline editor when an active SLA plan drives the due date, and `Ticket::updateField()`
rejects a manual edit. Today the app re-derives that rule (`plan id > 0`) from whatever it
can see; a server-published `sla_locked` makes it authoritative and removes a class of
"why was my edit refused" 422s.

**Ask:** add `source`, `topic`, `sla_plan` (id + name), `sla_locked`, `closed_at`,
`last_message`, `last_response`, `organization` to the `GET /tickets/{id}` serializer.

---

## 6. `GET /tickets` list rows are too thin

**Consumer:** [tickets_list_screen.dart:101](lib/features/tickets/tickets_list_screen.dart#L101)

The list serializer emits 7 fields — **no assignee, no due date, no department id.**

**Workaround shipped:** the screen fetches `GET /tickets/{id}` for rows whose summary lacks
an assignee and caches the name for the session. That powers search-by-assignee and the Agent
facet — at the cost of one extra request per visible row on first paint.

**Fix:** add `assignee` (`{id,name}` or null), `due` and `department.id` to the list row.
The task list already carries assignee and due date; the ticket list should match.

---

## 7. Filter params override the `view` scope

**Consumer:** [tickets_list_screen.dart:196](lib/features/tickets/tickets_list_screen.dart#L196), `_clientCounted` / `_countable`

Two related problems:

1. **`view` is dropped whenever a filter param is present.** So `?view=open&priority_id=3`
   returns rows from every tab, and the per-tab totals are untrustworthy under any filter.
2. **`view=mine` also returns closed assignments**, unlike the web's "My Tickets" queue
   which is open-only.

**Workaround shipped:** whenever a filter, a search term or a date range is active — and
always for `mine` — the app pages **every** matching row and counts the tabs client-side,
re-deriving open/closed membership from the status name. That is correct but expensive, and
it can't re-derive Overdue/Answered membership (the rows don't carry those flags), so those
two tabs still trust the server.

**Fix:** compose `view` **with** the filters rather than letting filters replace it, and make
`view=mine` open-only. Optionally publish `is_overdue` / `is_answered` on the list row so the
client can stop trusting the server for those two tabs.

---

## 8. `GET /tasks/{id}` omits due date and tags

**Consumer:** [task_detail_screen.dart:79](lib/features/tasks/task_detail_screen.dart#L79)

The task **list** row carries `duedate`; the **detail** payload does not. The app grafts the
list row's due date onto the fetched detail via the route's `extra` seed — which works when
you arrive from a list, and **shows nothing on a deep link or a push notification tap**.

Tags are likewise absent and side-loaded from `GET /tasks/{id}/tags`.

**Fix:** add `duedate` and `tags` to the `GET /tasks/{id}` serializer. Then
[app_router.dart:156](lib/core/router/app_router.dart#L156)'s seed plumbing can be deleted.

---

## 9. Agents carry no department

**Consumer:** [agent_directory.dart](lib/data/agent_directory.dart)

`GET /meta/agents` returns every active agent and **carries no department**, but the server
only accepts an assignee the ticket's department allows — `Dept::canAssign()` is re-checked
in `Ticket::assign()`, answering 422 "Permission denied" / "Agent is unavailable for
assignment". Offering the whole roster means offering picks that cannot succeed.

**Workaround shipped:** `AgentDirectory` fetches `GET /agents/{id}` for every agent (6 lookups
in flight, cached per session) to learn their **primary** department, then narrows the picker.
Because a profile names only the primary department, the match is *narrower* than the
server's real rule — a department set to "all agents", or an agent with extended `dept_access`,
is assignable without being a primary member. So the list is a default, never a gate: anything
unproven stays in, an empty match falls back to the full roster, and the picker always keeps
a "Show all agents" escape hatch.

The same approximation limits the **Agent Directory** screen, which ports
`Staff::getDeptAgents()` visibility — `dept_access` is published by no endpoint at all.

**Fix (either one closes it):**

* add `dept_id` / `dept_name` **and** a `dept_access` id list to each `GET /meta/agents` row; or
* add a `?dept_id=` filter to `/meta/agents` that runs the server's own `Dept::canAssign()` rule.

The second is better — it makes the picker exact instead of approximate, and removes the
N+1 entirely.

---

## 10. `GET /tickets/export` column set is fixed at nine — **RESOLVED**

**Closed by the `/reports/*` export surface** (`GET /reports/exports/{type}/fields` +
`POST /reports/exports/{type}/link`), which serves the full column catalog per type —
custom `cdata.*` form fields included — and mints a signed CSV link for the selected subset.
`GET /tickets/export` itself is unchanged and still the fixed nine, but it is now only the
**queue** export; the Reports screen no longer touches it.

**Consumer:** [records_view.dart](lib/features/reports/records_view.dart) — the column picker
is built from the served catalog, so an install that adds a ticket field gets it with no app
change.

The original report follows, for the record.

**Consumer (was):** `report_spec.dart` — hard-coded nine-column list, now deleted

```php
// include/api/v2/class.tickets.php :: exportTickets()  (~line 348)
$cols = array('number','subject','status','priority','department',
              'assignee','requester','created','due');
```

The web offers ~35 ticket columns: Source, From Email, Last Updated, SLA Plan, SLA Due Date,
Closed Date, Overdue, Merged, Linked, Answered, Team Assigned, **plus every ticket-form custom
field** — on this install: Client Id, Account Name, Vendor Name, Products, Sub Issue
Categories, Impact, Description, Resolution, Known/Unknown Issue, Resolution Status, RCA
Performed, Preventive Action, Escalation/Collaboration Department.

The column set is hard-coded and the list serializer carries even less, so there is no API
surface through which a caller can ask for a different set. **The custom fields that carry
most of this install's reporting value cannot be exported from mobile at all.**

**Fix:** accept a `columns` query parameter on `GET /tickets/export` and drive the `values()`
+ `fputcsv()` from it, reusing `reports_fields_for('tickets')` from `scp/reports.php` so the
two pages agree on names and labels. Custom fields need the same `cdata.<name>` traversal
`Export::dumpQuery()` already does.

---

## 11. Department / Help Topic / Agent take one id, not a list — **RESOLVED for reports**

`POST /reports/exports/{type}/link` takes `dept_id`, `topic_id` and `staff_id` as **arrays**,
so the Reports screen sends one request per export and the cross-product fan-out (and its
24-combination cap) is gone from the app.

**Still open on the plain list endpoints.** `GET /tickets` / `GET /tasks` continue to read a
single id each, so the fix below still applies to `applyAdvancedFilters()` /
`applyTaskFilters()` for the ticket and task **list** screens.

The original report follows.

The web filters with `dept_id__in (…)`, `topic_id__in (…)`, `staff_id__in (…)`. The API takes
a single id each:

```php
// include/api/v2/class.tickets.php :: applyAdvancedFilters()  (~line 225)
if (($v = (int) $this->q('dept_id')))     $tickets->filter(array('dept_id'  => $v));
if (($v = (int) $this->q('assignee_id'))) $tickets->filter(array('staff_id' => $v));
if (($v = (int) $this->q('topic_id')))    $tickets->filter(array('topic_id' => $v));
```

Only `status_id` and `tag_id` accept a comma list, via the `idList()` helper already in the
same file.

**Workaround (removed):** the Reports pickers used to request the **cross product** of the
selections and union the results — disjoint by construction, since a ticket has exactly one
department, one topic and one assignee — capped at 24 combinations. That code is gone now
that the report endpoints take arrays.

**Fix (three lines, removes the fan-out entirely):**

```php
-if (($v = (int) $this->q('dept_id')))     $tickets->filter(array('dept_id'  => $v));
-if (($v = (int) $this->q('assignee_id'))) $tickets->filter(array('staff_id' => $v));
-if (($v = (int) $this->q('topic_id')))    $tickets->filter(array('topic_id' => $v));
+if (($v = $this->idList('dept_id')))      $tickets->filter(array('dept_id__in'  => $v));
+if (($v = $this->idList('assignee_id')))  $tickets->filter(array('staff_id__in' => $v));
+if (($v = $this->idList('topic_id')))     $tickets->filter(array('topic_id__in' => $v));
```

`idList()` already accepts `"3"`, `"3,4,5"` and repeated params, and the app already sends
comma lists for `status_id`, so this is backward compatible. The same change applies to
`class.tasks.php :: applyTaskFilters()` for `dept_id` / `assignee_id`.

---

# P2 — Efficiency and coverage

## 12. `/users` and `/organizations` have no date filter — **RESOLVED for reports**

`POST /reports/exports/users/link` and `.../orgs/link` honour `start` / `end` server-side, so
the Users and Organizations reports no longer page the whole install to apply a window.

**Still open on the plain list endpoints:** `listUsers()` and
`OrganizationsV2Controller::list()` accept only `q`.

`listUsers()` and `OrganizationsV2Controller::list()` accept only `q` — no `created_from` /
`created_to`, unlike the ticket and task lists.

**Workaround (removed):** the Users and Organizations reports used to page the whole list and
apply the created-date window client-side — 3,554 users ≈ 36 requests. That code is gone.

**Fix:** add the same two lines the other controllers already have:

```php
if (($v = trim($this->q('created_from', '')))) $users->filter(array('created__gte' => $v.' 00:00:00'));
if (($v = trim($this->q('created_to',   '')))) $users->filter(array('created__lte' => $v.' 23:59:59'));
```

## 13. No `/tasks/export` — **RESOLVED for reports**

`POST /reports/exports/tasks/link` mints a server-side task CSV with its own column catalog
(task form `cdata.*` fields included), so the Tasks report is no longer assembled from paged
list rows and is no longer bounded by the app's 5,000-row cap.

**Still open for the task *list* screen's own download,** which has no `GET /tasks/export`
counterpart to `GET /tickets/export` and still builds its file from list rows.

## 14. User / Organization list rows and the org N+1

* ~~**Users report has no Organization column**~~ — **resolved**: the report catalog serves
  `org::getName`. The plain `GET /users` list row still omits `org__name`, which is what the
  Users *list* screen would need.
* ~~**Organizations report has no Account Manager column**~~ — **resolved**: the catalog
  serves `::getAccountManager`. Same caveat on the plain `GET /organizations` list row.
* The org list already does an **N+1** (`Organization::lookup()` per row for
  `getNumUsers()`); paging 5,000 rows for an export makes that noticeable. Replace with an
  aggregate join.

## 15. No task report endpoint

**Consumer:** [dashboard_screen.dart:61](lib/features/dashboard/dashboard_screen.dart#L61)

`/reports/summary` and `/reports/volume` cover tickets only. The dashboard's task counts
(open / overdue / all / closed) are derived from **four separate `/tasks` list calls** read
for their `total`, purely to fill four numbers.

**Fix:** extend `/reports/summary` with a `tasks` block (`open`, `overdue`, `closed`, `all`),
or add `GET /tasks/stats` mirroring `GET /tickets/stats`.

## 16. Notifications have no server-side filter or per-view counts

**Consumer:** [notifications_screen.dart](lib/features/notifications/notifications_screen.dart)

`GET /notifications` takes only `page` / `limit`. All view filtering (type, read/unread
beyond the single unread total, search) is client-side, so:

* only the **Unread** chip has a badge — every other view is count-less, because there is no
  cheap total for it;
* a client-side filter can hide most of a page, so the screen keeps pulling pages until it
  has a screenful (`groups.length < 8`), which can mean several round trips per view switch.

**Fix:** accept `type=`, `read=0|1` and `q=` on `GET /notifications`, and extend
`GET /notifications/count` to return a per-view breakdown rather than just `unread`.

**Still open (2026-08-26):** the filters shipped, but `GET /notifications/count` still
returns only `unread`, a count of **rows**. Both inboxes list one card per ticket/task, so
the badge needs the number of unread *objects* — the app now derives it by grouping the
`read=0` feed (up to 3x100 rows) on every badge fetch. Adding `unread_objects`
(`COUNT(DISTINCT object_type, object_id) WHERE read IS NULL`) to the count payload retires
that extra read; the app already prefers it when present.

**Note:** `POST /notifications/read-object` (`{type, object_id}`) is called by the app —
please confirm it exists; it is not in the read-only endpoint list we verified.

---

# P3 — Small items

## 17. `isCannedResponseEnabled()` is not published

`scp/canned.php` requires **both** `canned.manage` *and* `$cfg->isCannedResponseEnabled()`.
No endpoint publishes that flag, so the app can only honor half the rule
([me.dart:113](lib/models/me.dart#L113)). Adding a `config` block to `GET /me` — or just
`canned_enabled` — closes it.

## 18. KB category parent / full name

`Category` has a `category_pid`, and the web's Categories list renders children as
"Funds / Pay in" via `getFullName()`. The v2 list endpoint sends `getName()` — the *local*
name only — so the app shows "Pay in" with no hint of its parent. Adding `pid` (and/or
`full_name`) to the `GET /faq/categories` payloads also lets the create form (item 1) grow a
parent picker to match the web.

**Write side (open).** The `GET` payloads now carry `pid` / `full_name`, so the app's
Add/Edit Category sheet ships the web's Parent dropdown and sends `pid` on
`POST /faq/categories` and `POST /faq/categories/{id}`. Both handlers must read it and pass
it into `$vars` — while `pid` is hard-coded to `0`, picking a parent in the app silently
creates a top-level category. `Category::update()` already rejects a duplicate name under
the same parent, so no extra validation is needed beyond refusing a `pid` that does not
exist (or, on edit, one that is the category itself or a descendant of it — the app hides
those from the dropdown, but the server should not trust that).

---

# Decision required (not a bug)

## 19. A ticket's creator gets no visibility on their own ticket

**Consumer:** [create_ticket_screen.dart:763](lib/features/tickets/create_ticket_screen.dart#L763) `_canOpen`, [me.dart:190](lib/models/me.dart#L190) `canSeeTicket`

This install tightened `Ticket::checkStaffPerm()`: visibility takes an admin, a department the
agent **manages** (`Staff::getVisibilityDepts()`), the assignee, the assigned team, a staff
collaborator or a referral. **Plain department membership is deliberately not honored, and
creating a ticket grants its creator nothing.**

So an agent can file a ticket into a department they merely belong to, leave it unassigned,
and lose sight of it the instant it exists — `GET /tickets/{id}` answers `404 No such ticket`.

**What the app does:** it predicts this before submit (`Me.canSeeTicket`) and warns; it sends
`assign_staff_id` / `assign_team_id` **inside** `POST /tickets` (because
`POST /tickets/{id}/assign` sits behind the same gate and 404s in exactly the case the
assignment was needed); and after create it probes with `GET /tickets/{id}`, treating **only**
a 404 as "can't open".

**Please confirm this is intended policy.** If it is not, granting the creator visibility (as
stock osTicket effectively does through department membership) removes the warning, the probe
and the inline-assign special case from the client.

---

# Appendix A — Endpoints the app calls today

Anything marked ✗ does not exist server-side; ⚠ exists but is incomplete (see the item).

```
GET    /ping
GET    /me                                    ⚠ 3, 17
POST   /me
POST   /me/availability
POST   /me/password
POST   /me/avatar
GET    /agents/{id}                           ⚠ 9  (only primary dept)
POST   /auth/login
POST   /auth/forgot-password
POST   /auth/reset-password

GET    /meta/{kind}                           kinds: queues statuses departments teams
                                              priorities agents topics tags
                                              task-priorities sla        ⚠ 9 (agents)

GET    /tickets                               ⚠ 6, 7, 11
GET    /tickets/stats
GET    /tickets/export                        ⚠ 10, 11
GET    /tickets/form
GET    /tickets/{id}                          ⚠ 5
POST   /tickets                               (inline assign keys — see 19)
POST   /tickets/bulk
DELETE /tickets/{id}
POST   /tickets/{id}/{action}                 reply note assign transfer status ...
GET    /tickets/{id}/fields
GET    /tickets/{id}/events
GET    /tickets/{id}/thread/{entry}/history
GET|POST|DELETE /tickets/{id}/collaborators[/{cid}]
GET|POST|DELETE /tickets/{id}/tags[/{tagId}]
GET|POST|DELETE /tickets/{id}/referrals[/{rid}]
GET|POST /tickets/{id}/relations, /link, DELETE /link
POST|DELETE /tickets/{id}/merge
POST|DELETE /tickets/{id}/ban-email

GET    /tasks                                 ⚠ 11
GET    /tasks/{id}                            ⚠ 8
POST   /tasks                                 ✗ 2  (drops parent_id / priority_id)
POST   /tasks/{id}/subtasks                   ✗ 2
POST   /tasks/{id}/{action}
GET    /tasks/{id}/events, /subtasks
GET|POST|DELETE /tasks/{id}/collaborators[/{cid}]
GET|POST|DELETE /tasks/{id}/tags[/{tagId}]
GET|POST|DELETE /tasks/{id}/dependencies[/{depId}]
GET    /tasks/{id}/thread/{entry}/history
       /tasks/export                          ✗ 13

GET    /users                                 ⚠ 12, 14
POST   /users
GET    /organizations                         ⚠ 12, 14

GET    /canned                                ⚠ 4
GET|POST|DELETE /canned/{id}                  ⚠ 4 (404s on disabled)
GET|POST|DELETE /canned/{id}/attachments[/{attId}]

GET    /faq, /faq/{id}
GET    /faq/categories, /faq/categories/{id}  ⚠ 18
POST   /faq/categories                        ✗ 1

GET    /notifications                         ⚠ 16
GET    /notifications/count                   ⚠ 16
POST   /notifications/read-all
POST   /notifications/read-object             ✗? confirm this exists
POST   /notifications/{id}/read
DELETE /notifications, /notifications/{id}

GET    /reports/summary                       ⚠ 15 (tickets only)
GET    /reports/volume

POST|DELETE /push/devices
POST   /push/config, /push/test               (admin)
```

# Appendix B — Suggested order of work

1. **Item 2** (subtask parent) — data is being silently lost.
2. **Item 3** (`class.report.php` require) — one line, unblocks permission gating.
3. **Item 1** (`POST /faq/categories`) — a shipped button currently 404s.
4. **Item 11** (`idList` on dept/topic/assignee) — three lines, removes a 24× request fan-out.
5. **Item 4** (canned list + management scope) — a disabled response is currently unrecoverable.
6. **Item 5 / 6 / 8** (payload widening) — pure additions, no client change needed for 5 and 6.
7. **Item 10** (`columns` on export) + **13** (`/tasks/export`) — the real reporting unlock.
8. Everything else as capacity allows.

---

# Appendix C — Reference-tree caveat

The osTicket reference copy at `D:\John\John flutter\zebu-os-ticket-main` is **behind the live
site**. `include/staff/reports.inc.php` there renders Status as a three-option dropdown
(All / Open / Closed), while the live page shows a multi-select status list with
"— Any open status —", "— Any closed status —" and individual statuses. The mobile Reports
screen follows the reference tree. If the live behaviour is wanted, refresh the reference copy
first so there is something authoritative to port.
