# Backend fix — v2 task create drops `parent_id` (and `priority_id`)

**File:** `include/api/v2/class.tasks.php` → `TasksV2Controller::create()`
**Affects:** `POST /tasks` and `POST /tasks/{id}/subtasks` (both run this method)
**Symptom:** a subtask is created but comes back with `parent_id: null` — it never appears
under the parent's Subtasks. Priority set at create time is likely lost the same way.

## Cause

`Task::create()` takes the parent and the priority out of the **internal form's** clean
data — `class.task.php:2258` (`$vars['internal_formdata']['parent_id']`) and `:2268`
(`priority_id`) — and stamps them on the row **before** the insert. That is how the web
does it: `ajax.tasks.php::addSubtask()` puts `parent_id` into `TaskForm::getInternalForm()`
as a locked field (field id 5), so it arrives inside `internal_formdata`.

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
controller then tries to patch the column afterwards:

```php
// class.tasks.php:382
$changed = false;
if ($parentId)                  { $task->parent_id = $parentId; $changed = true; }
if (!empty($in['priority_id'])) { $task->priority_id = (int)$in['priority_id']; $changed = true; }
if (isset($in['progress']))     { $task->progress = max(0, min(100, (int)$in['progress'])); $changed = true; }
if ($changed) { try { $task->save(); } catch (Exception $e) {} }
```

That save is failing on live and the `catch` swallows it, so the parent is lost silently.

## Fix — put them in the form source, like the web

**1. `class.tasks.php:333` — add two keys to `$src`:**

```php
$src = array(
    'title'       => trim($in['title']),
    'description' => ThreadEntryBody::clean($in['description']),
    'dept_id'     => (int)$in['dept_id'],
    'duedate'     => $in['duedate'] ?? '',
    'parent_id'   => $parentId,                          // NEW — TaskInternalForm field id 5
    'priority_id' => (int)($in['priority_id'] ?? 0),      // NEW — TaskInternalForm field id 4
);
```

`$parentId` is already resolved above (line 320: route arg, else `$in['parent_id']`).

**2. `class.tasks.php:382` — drop parent/priority from the post-create patch, keep progress
(it is not a form field):**

```php
$changed = false;
if (isset($in['progress'])) { $task->progress = max(0, min(100, (int)$in['progress'])); $changed = true; }
if ($changed) { try { $task->save(); } catch (Exception $e) {} }
```

## Why this is the right shape

- One code path for web and API — no more silent post-create patching that can fail unnoticed.
- `Task::create()` re-validates the parent (unknown parent / no permission → `parent_id`
  error, cycles impossible on a brand-new task) instead of writing an unchecked id.
- Errors keyed by field id already work in the app: it maps 1=dept_id, 3=duedate,
  4=priority_id, 5=parent_id back to names.

**Heads-up:** once `priority_id` goes through the form, an unknown or **inactive** priority
id is rejected (422, field `4`) instead of being written silently. That matches the web —
please confirm it is wanted.

## Verify after deploy

```
POST /api/v2/tasks/{parent}/subtasks
{ "title":"t", "description":"d", "dept_id":<parent dept>, "duedate":"<future>" }
→ 201, and the response must have  "parent_id": <parent>   (currently null)

POST /api/v2/tasks
{ "title":"t", "description":"d", "dept_id":1, "duedate":"<future>",
  "parent_id":<parent>, "priority_id":<active id> }
→ 201, "parent_id": <parent>, "priority": {...}   (currently parent_id null)

GET /api/v2/tasks/{parent}/subtasks  → the new task is listed
```

Note: the mobile app currently also sends `custom_fields: {parent_id, priority_id}` as a
client-side workaround (it gets merged into `$src` at line 341, which is the same source).
That keeps working after this fix — the values are identical — and can be removed from the
app once the fix is live.
