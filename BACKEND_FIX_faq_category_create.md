# Backend — add `POST /faq/categories` (Knowledgebase category create)

**File:** `include/api/v2/class.faq.php` → `FaqV2Controller` (+ one route line in
`scp/api.php`)
**Affects:** new endpoint — nothing existing changes
**Verified absent** in the reference tree (`D:\John\John flutter\zebu-os-ticket-main`,
2026-08-25): the `^/faq` block at `scp/api.php:230` registers four `url_get`s and no
`url_post`, and the controller docblock says so outright — *"No create/edit here — those
are deferred."*
**Needed by:** mobile Knowledgebase → **Add new category**
(`lib/features/faq/faq_screen.dart`, `FaqRepository.createCategory`)

## Why

The staff web has Knowledgebase → Categories → **Add New Category**
(`scp/categories.php`). The v2 API exposes the KB read-only: `/faq`,
`/faq/{id}`, `/faq/categories`, `/faq/categories/{id}`. The mobile app now has
the same action, and it calls an endpoint that does not exist yet — **until this
ships the button returns `404`.**

Article create/edit is deliberately *not* requested here; categories only.

## Request

```
POST /api/v2/faq/categories
Authorization: Bearer <agent token>
Content-Type: application/json

{
  "name":        "Payins",                  // required
  "type":        "private",                 // required: private | public | featured
  "description": "How pay-ins are handled", // required
  "notes":       "internal only"            // optional
}
```

`type` is the lowercase form of the string `GET /faq/categories` already returns
in its `type` field, so read and write use one vocabulary. Map it onto the
column the web writes — `category.ispublic`, using osTicket's category
visibility constants in `include/class.faq.php`:

| `type`     | `ispublic` |
| ---------- | ---------- |
| `private`  | 0          |
| `public`   | 1          |
| `featured` | 2          |

An unknown `type` is a validation error, not a silent default.

## Handling

`CannedV2Controller::create()` (`class.canned.php:90`) is the template — same
shape, one model swap. Build `$vars` the way `scp/categories.php` does for
`$_POST['a'] == 'create'` and hand them to `Category::create()` (`class.category.php:345`)
then `->update()` (`:168`), so the model keeps ownership of validation:

```php
function createCategory() {
    $this->requireStaff(); $this->requireCsrf();
    if (!$this->requireStaffPerm(FAQ::PERM_MANAGE))          // see Permission below
        $this->fail(403,'forbidden','Not allowed to manage the knowledgebase');
    $in = $this->bodyInput();

    $fields = array();
    if (!trim((string)($in['name'] ?? '')))        $fields['name'] = 'Required';
    if (!trim((string)($in['description'] ?? ''))) $fields['description'] = 'Required';
    if (!isset($map[strtolower($in['type'] ?? '')])) $fields['type'] = 'Invalid';
    if ($fields) $this->fail(422,'validation','Missing or invalid data',$fields);

    $vars = array(
        'name'        => trim($in['name']),
        'ispublic'    => $ispublic,               // mapped from $in['type'], below
        'pid'         => 0,                       // top-level; see "Parent categories"
        'description' => $in['description'],      // update() runs Format::sanitize()
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

Three rules `Category::update()` already enforces (`class.category.php:168-185`),
which the API must surface rather than swallow — all three arrive in `$errors`
keyed by field, so `normErrors()` maps them straight onto the response:

* `name` **required**, and **at least 3 characters** ("Name is too short. 3 chars minimum").
* a duplicate `name` under the same parent → "Category already exists".
* `description` **required**.

### Parent categories

`Category` has a `category_pid`, and the web's Categories list renders children
as "Funds / Pay in" via `getFullName()`. The v2 list endpoint sends
`getName()` — the *local* name only — so the app currently shows "Pay in" with
no hint of its parent. Out of scope for this endpoint (it creates top-level
categories with `pid = 0`), but if `pid` is added to the `GET` payloads later,
the create form can grow a parent picker to match the web.

## Permission

Guard with the same permission the web page checks.
`FAQ::PERM_MANAGE` is `'faq.manage'` (`include/class.faq.php:48`), and
`scp/categories.php:21` gates the whole page on
`$thisstaff->hasPerm(FAQ::PERM_MANAGE)` — use the same check, via whatever
staff-permission helper `V2Controller` exposes (`CannedV2Controller::canManage()`
is the neighbouring example).

Reading the KB stays ungated, matching the web's `kbase` tab.

Note `faq.manage` **is** published to the app: `include/class.faq.php` is one of
the classes the bearer-token bootstrap already loads (confirmed in
`BACKEND_FIX_reports_permission.md`), so `/me` carries the code and the mobile
client gates the button on it correctly — unlike `reports.export`. The client
gate is cosmetic either way; this server check is the real one.

## Response

**201** with the created category in the *same shape* as
`GET /faq/categories/{id}`, so the client can parse one model:

```json
{
  "data": {
    "id": 9,
    "name": "Payins",
    "public": false,
    "type": "Private",
    "faq_count": 0,
    "faqs": []
  }
}
```

**Errors** use the standard envelope the app already parses
(`ApiException.fields` drives per-field messages in the form):

```json
{
  "error": {
    "code": "validation",
    "message": "",
    "fields": { "name": "Category already exists" }
  }
}
```

Field keys must be the request keys — `name`, `type`, `description`, `notes` —
so they land on the right input. `403` uses `code: "forbidden"`.

## Client behaviour to be aware of

* The app pre-validates `name` (present, 3+ chars) and `description` locally, so
  an empty-field round trip should not normally reach you.
* On success it re-fetches `GET /faq/categories`, so the new row must be visible
  to that listing immediately.
* `notes` is omitted from the payload entirely when left blank.
