# Backend fix — `reports.export` is never sent to the app

**Symptom:** the Reports entry never appears in the mobile Menu, for **any** account — manager, or even admin.

**Not an app bug.** The permission the entry is gated on never reaches the app, so there is nothing for it to check.

---

## Root cause

osTicket registers each permission from the bottom of the class file that owns it:

```php
// include/class.report.php:28  (last line of the file)
RolePermission::register(/* @trans */ 'Miscellaneous', ReportModel::getPermissions());
//                                    ^ stats.agents + reports.export
```

`scp/api.php` has **two** bootstraps, and only one of them ever loads that file:

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

`include/api/v2/class.reports.php` (the V2 controller) requires only `class.v2controller.php` — it does **not** pull in the `ReportModel` that owns the permission.

**Consequence:** on the app's path `RolePermission::allPermissions()` has no `reports.export`, so `MeV2Controller::allPermissionCodes()` omits it, and `GET /me` returns it in **neither** `global_permissions` nor any `permissions_by_department` map. `stats.agents` is missing the same way.

This is why it looks fine when checked from a browser: open `/scp/api.php/me` with a staff session and `reports.export` **is** there. Only token auth is affected.

---

## Fix (one line)

Add the model require to the V2 reports controller, so it loads on every API request regardless of auth mode:

```php
// include/api/v2/class.reports.php
 require_once INCLUDE_DIR.'api/v2/class.v2controller.php';
+require_once INCLUDE_DIR.'class.report.php';   // registers stats.agents + reports.export
```

Equivalent alternative — add it to the token branch of `scp/api.php`:

```php
 if ($__tokenMode) {
     require('../main.inc.php');
     require_once(INCLUDE_DIR.'class.staff.php');
+    require_once(INCLUDE_DIR.'class.report.php');
 }
```

**Verify:** `GET /me` with a bearer token returns a `reports.export` key (value `1` or `0`) inside `global_permissions` and inside each `permissions_by_department` entry.

---

## What the app does meanwhile

No app change is needed once the above ships. The gate already distinguishes **denied** from **not published**:

`/me` writes an explicit `1`/`0` for every code it knows, so a code that is *absent* was never registered. `Me.publishes(code)` detects that, and `Me._gate()` falls **open** for an unpublished code — an entry the backend will refuse anyway is better than one hidden from everyone forever.

So today the Reports entry shows for every agent. **The moment this fix ships, the real rule takes over automatically** — `reports.export` on the agent's own grants or on any of their roles, no admin bypass — matching `include/class.nav.php` and `scp/reports.php`. No rebuild required for the switchover beyond the app already running.

Covered by `test/menu_permission_gating_test.dart` → group *"an unpublished permission falls open"*.

## Worth checking at the same time

The same include-order trap applies to any permission whose owning class the token bootstrap misses. Currently loaded and therefore safe: `class.staff.php` (`visibility.agents`), `class.canned.php`, `class.faq.php`, `class.organization.php`, `class.user.php`, `class.ticket.php`, `class.task.php`, `class.search.php`. Only `class.report.php` is missing.
