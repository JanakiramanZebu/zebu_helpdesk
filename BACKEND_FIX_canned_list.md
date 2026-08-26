# Backend fix — `GET /canned` list payload and disabled-response management

**File:** `include/api/v2/class.canned.php` → `CannedV2Controller`
**Affects:** `GET /canned` and every by-id canned endpoint
**Reference:** `include/staff/cannedresponses.inc.php`, `include/staff/cannedresponse.inc.php`
**Symptom:** every row in the Canned Responses list shows the **Global** tag and never
shows **Disabled**, whatever is in the database; and a response that has been disabled
can no longer be opened, edited or re-enabled from the app at all.

## Cause 1 — the list payload has no status/scope/date fields

`listCanned()` selects three columns:

```php
// class.canned.php:60
foreach ($qs->limit($limit)->offset(($page-1)*$limit)
        ->values('canned_id','title','response') as $r)
    $data[] = array(
        'id'    => (int) $r['canned_id'],
        'title' => (string) $r['title'],
        'body'  => (string) $r['response'],
    );
```

`CannedResponse.fromJson` therefore falls back to its defaults for the rest —
`dept_id => 0` and `is_enabled => true`. The list card draws its two tags from exactly
those fields, so the **Global** chip shows on department-scoped responses and the
**Disabled** chip is unreachable.

The osTicket staff list shows Title, **Status**, **Department** and **Last Updated**,
plus a file icon when the response carries non-inline attachments. None of those four can
be rendered from the current payload.

## Cause 2 — disabled responses can't be managed

`visibleCanned()` is the base queryset for `listCanned`, `retrieve`, `update`, `destroy`,
`attachments`, `uploadAttachment`, `deleteAttachment` **and** `expand`:

```php
// class.canned.php:17
$qs = Canned::objects()
    ->filter(array('isenabled' => true))
    ->order_by('title');
```

`isenabled => true` is right for the *composer* — an agent inserting a reply should only
see live responses — but it is applied to the management endpoints too. So a disabled
response is absent from `GET /canned` **and** 404s on `GET/POST/DELETE /canned/{id}`.
Once anything is disabled, from the app or from the osTicket admin, there is no way back
to Active through the API. `scp/canned.php` has no such restriction: it lists every
response in the agent's departments and offers bulk Enable / Disable.

## Proposed change

### a. Widen the list serializer

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

`files` mirrors the staff list's `count(attach.file_id)` join
(`type='C' AND NOT attach.inline`). `dept_name` saves the client a
`GET /meta/departments` round-trip on every row.

### b. Split composer visibility from management visibility

Keep `visibleCanned()` exactly as it is for `expand()` and the ticket composer. Add a
management queryset that drops the `isenabled` filter:

```php
// Management scope — mirrors scp/canned.php: every response in a dept where
// the agent holds Canned::PERM_MANAGE, plus the global (dept_id=0) pool,
// regardless of enabled state.
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

Then:

* `listCanned()` — accept `?include_disabled=1`, using `manageableCanned()` when the flag
  is set **and** `canManage()` is true; otherwise unchanged.
* `retrieve()`, `update()`, `destroy()`, `attachments()`, `uploadAttachment()`,
  `deleteAttachment()` — resolve through `manageableCanned()` when `canManage()` is true,
  falling back to `visibleCanned()` otherwise. Those endpoints already gate mutation on
  the same permission, so this grants nothing new; it only stops a disabled row 404-ing.
* `expand()` — leave on `visibleCanned()`. A disabled response must never be insertable
  into a reply.

### c. Expose the filter usage on retrieve

`Canned::getFilters()` backs the osTicket form's "Canned response is in use by email
filter(s): …" warning, and `Canned::delete()` refuses while `getNumFilters() > 0` (which
the v2 `destroy()` already surfaces as a 409). Adding

```php
'filters' => array_values($c->getFilters()),
```

to `serialize()` lets the edit sheet warn *before* the user tries to delete, instead of
only after the 409 comes back.

### d. Optional: sorting

`?sort=title|status|dept|updated&order=asc|desc`, matching the four sortable columns on
the staff list. Not required for the tags to be correct.

## Client work unblocked by this

| Change | Client follow-up |
|---|---|
| `is_enabled` in list | Status tag becomes truthful |
| `dept_id` + `dept_name` in list | Scope tag becomes truthful; can show the department name |
| `updated` in list | Can show "Last updated" |
| `files` in list | Attachment indicator on the row |
| `include_disabled=1` | Show disabled rows; Active/Disabled/All filter; bulk Enable/Disable |
| `filters` on retrieve | In-sheet "in use by email filter(s)" warning |

## Not blocked (already shipped in the app)

The create/edit sheet now sends `dept_id`, `notes` and `is_enabled` on both create and
update, and manages attachments via `POST|DELETE /canned/{id}/attachments`. Those
endpoints already behave correctly. The detail sheet re-reads `GET /canned/{id}`, whose
serializer *does* include `dept_id`, `is_enabled`, `notes` and `attachments` — which is
why the detail sheet's status/department are accurate while the list's tags are not.
