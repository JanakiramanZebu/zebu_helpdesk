# Zebu Helpdesk (staff app)

A Flutter mobile client for the Zebu Helpdesk **osTicket `/api/v2`** staff API
(the same API that powers the web console at `ticket.mynt.in`). Full-helpdesk
scope: tickets, tasks, users, organizations, canned responses, knowledgebase,
saved queues, notifications, reports, and the agent profile.

## Stack

| Concern | Choice |
| --- | --- |
| State management | `flutter_riverpod` 3.x |
| HTTP | `dio` (bearer + transparent token refresh interceptor) |
| Navigation | `go_router` (auth-guarded, bottom-nav shell) |
| Token storage | `flutter_secure_storage` (encrypted JWT pair) |
| Typography | `google_fonts` (Inter) |
| Misc | `intl`, `timeago`, `url_launcher`, `file_picker`, `image_picker` |

## Configuration

The API base URL defaults to `https://ticket.mynt.in` and can be overridden at
build time:

```sh
flutter run --dart-define=ZEBU_BASE_URL=https://your-helpdesk.example.com
```

All calls go through the single dispatcher `{BASE}/scp/api.php/<path>`.

## Architecture

```
lib/
  main.dart / app.dart          App entry + MaterialApp.router
  core/
    config.dart                 Base URL, timeouts, page size
    api/
      api_client.dart           Dio wrapper: bearer inject, 401-refresh-retry,
                                error normalization, multipart, raw bytes
      api_exception.dart        Parses { "error": { code, message, fields } }
      json.dart                 Defensive JSON readers (J.*)
      paginated.dart            Paginated<T> from { data, pagination }
    auth/
      token_storage.dart        Secure JWT + agent snapshot store
      auth_controller.dart      Session lifecycle (Riverpod Notifier)
    theme/app_theme.dart        Material 3 theme, status colors, hex parsing
    router/                     routes.dart + app_router.dart (guarded shell)
    format.dart                 Fmt.* (dates, relative time, file size, HTML)
  models/                       One file per entity (ticket, task, user, org,
                                canned, faq, saved_queue, app_notification,
                                reports, meta, me, common)
  data/                         One repository per API module, each taking the
                                ApiClient (tickets, tasks, users, orgs, canned,
                                faq, queues, notifications, push, reports, meta,
                                me, auth)
  providers.dart                Central Riverpod DI graph
  widgets/                      Shared UI (PagedListView, StatusChip, states,
                                UserAvatar, AttachmentTile)
  features/                     One folder per screen group
    auth/ splash/ shell/ dashboard/ reports/ tickets/ tasks/ users/
    organizations/ faq/ canned/ queues/ notifications/ profile/ more/
```

### Conventions

- Screens are `ConsumerStatefulWidget` / `ConsumerWidget`; they call
  `ref.read(xRepositoryProvider)` and surface `ApiException.message` via
  `SnackBar`, with `ApiException.fields` mapped onto form field errors.
- Lists use the reusable `PagedListView<T>` (infinite scroll + pull-to-refresh);
  pass a new `refreshKey` to reload on filter/search changes.
- Action endpoints that return the full ticket/task object update local state
  in place; structural changes (assign/transfer/status) trigger a reload.

## Run / build

```sh
flutter pub get
flutter analyze          # clean
flutter test             # boot smoke test
flutter run              # device/emulator
flutter build apk --debug
```

## Not yet wired

- FCM push registration (`/push/devices`) — `PushRepository` exists; hooking up
  `firebase_messaging` + device-token upload is a follow-up.
- Inline `cid:` thread images are bearer-authed (`/files/{id}`); currently
  attachments open externally and HTML bodies render as sanitized text.
- Ticket/task **create** flows and attachment **pickers** are stubbed at the
  repository layer; wire `file_picker`/`image_picker` into the composer next.
