# Flutter Web Migration Plan — Zebu Helpdesk

**Goal:** Add Web as a third build target (alongside Android + iOS) from a single
shared `lib/`. Mobile UX must not regress. Web is *additive*.

**Status:** Phases A–E + G complete. Web builds & runs against the helpdesk
API. CLAUDE.md added. Phase F items (Firebase, deep links, master-detail
routing, encrypted web storage) are deferred per agreement.

---

## 1. Current-State Audit

### 1.1 Project structure (today)

```
lib/
├── app.dart                # MaterialApp.router wiring
├── main.dart               # ensureInitialized + HttpOverrides + runApp
├── providers.dart          # Centralised Riverpod providers (acts as DI)
├── app/
├── core/
│   ├── api/                # api_client.dart, json.dart, paginated.dart, exceptions
│   ├── auth/               # auth_controller.dart, token_storage.dart
│   ├── config.dart         # base URL
│   ├── network/ssl_override.dart   # dart:io  <-- web-incompatible
│   ├── export/table_export.dart    # dart:io  <-- web-incompatible
│   ├── router/             # app_router.dart (go_router), routes.dart
│   └── theme/              # AppTheme + theme_controller
├── data/                   # *_repository.dart (one per feature)
├── features/               # auth, dashboard, tickets, tasks, users, orgs,
│   │                       # queues, reports, faq, canned, profile, more,
│   │                       # notifications, splash, shell
│   └── <feature>/
│       ├── *_screen.dart
│       └── widgets/        # feature-local widgets
├── models/                 # data classes
└── widgets/                # cross-feature reusable widgets
```

**Platforms present:** `android/`, `ios/`. **No `web/` folder yet.**

### 1.2 Pubspec snapshot

```
flutter_svg ^2.0.17               ✅ web-safe
dio ^5.9.2                        ✅ web-safe (uses BrowserHttpClientAdapter)
flutter_riverpod ^3.3.2           ✅ web-safe
go_router ^17.3.0                 ✅ web-safe (supports usePathUrlStrategy)
flutter_secure_storage ^10.3.1    ⚠  works on web but stores in localStorage (not encrypted) — needs abstraction
intl ^0.20.2                      ✅
file_picker 10.3.10               ✅ web-safe (returns bytes, no path)
image_picker ^1.2.2               ✅ web-safe (already uses bytes in our code)
timeago ^3.7.1                    ✅
google_fonts ^8.1.0               ✅
url_launcher ^6.3.2               ✅ web-safe
characters ^1.4.0                 ✅
pdf ^3.11.1                       ✅ pure dart, web-safe (output to bytes)
excel ^4.0.6                      ✅ pure dart, web-safe
fleather >=1.18.0 <1.27.0         ✅ web-safe
parchment >=1.18.0 <2.0.0         ✅
flutter_widget_from_html_core ^0.17.2  ✅
```

**No mobile-only packages are blockers.** The friction is in our *code*, not deps.

### 1.3 `dart:io` and platform-coupled call sites

| File | What it does | Web fix |
|---|---|---|
| [lib/main.dart](lib/main.dart#L1-L15) | `HttpOverrides.global = MyHttpOverrides()` to bypass incomplete TLS chain | Wrap in `if (!kIsWeb)` — web uses the browser's TLS store, override is impossible and unnecessary |
| [lib/core/network/ssl_override.dart](lib/core/network/ssl_override.dart) | `dart:io` `HttpOverrides` subclass | Move behind `lib/platform/ssl_override_io.dart` + no-op `ssl_override_web.dart` |
| [lib/core/export/table_export.dart](lib/core/export/table_export.dart#L43-L46) | `File('${Directory.systemTemp.path}/$baseName.${format.ext}')` + `launchUrl(Uri.file(...))` | Web: trigger browser download from bytes (`AnchorElement` / `package:web` blob). Mobile: keep as-is. Abstract behind `lib/platform/file_save_io.dart` / `_web.dart` |
| [lib/widgets/pickers.dart](lib/widgets/pickers.dart#L92-L97) | `ImagePicker().pickImage(source: ImageSource.camera)` | Works on web but UX is poor. Hide the *Camera* menu entry on web (`kIsWeb`), keep Photos + Files |
| [lib/core/auth/token_storage.dart](lib/core/auth/token_storage.dart) | `FlutterSecureStorage` | Package works on web but uses unencrypted localStorage. Either accept that for v1 or abstract behind `lib/platform/secure_storage_*.dart` |
| [lib/core/theme/theme_controller.dart](lib/core/theme/theme_controller.dart) | `FlutterSecureStorage` for theme prefs | Should move to `SharedPreferences` regardless — theme isn't a secret |

**That's the entire mobile→web friction surface.** Six files. Everything else (providers, models, repositories, screens, router) is already platform-neutral.

### 1.4 What the user's spec calls for vs. what we already have

| User's proposed layout | Today | Recommendation |
|---|---|---|
| `lib/api/` | `lib/core/api/` | **Keep as-is** — rename is churn with no benefit |
| `lib/provider/` | `lib/providers.dart` + Riverpod everywhere | **Keep as-is** |
| `lib/screens/responsive/` | `lib/features/<feature>/*_screen.dart` | **Keep features structure**, add `lib/core/responsive/` for breakpoints helper |
| `lib/sharedWidget/` | `lib/widgets/` | **Keep as-is** — same idea, different name |
| `lib/routes/` | `lib/core/router/` | **Keep as-is** |
| `lib/res/` (colors, theme) | `lib/core/theme/` | **Keep as-is** |
| `lib/locator/` (GetIt) | Riverpod providers in `lib/providers.dart` | **Skip GetIt.** Riverpod already does DI. Two DI containers is a smell — see decision §2.1 |
| `lib/notification/` | *(none — no FCM in repo today)* | Add only when push is actually wired up |
| `lib/platform/` | *(none)* | **Create** — this is the real new directory |
| `lib/utils/` | scattered | Create when needed; not a day-1 task |

**Bottom line:** the existing structure is sound. We don't need a rename pass. The genuine new work is `lib/platform/` + a responsive helper.

### 1.5 Things the spec mentions that don't exist in this codebase yet

These appear in your requirements but are *not* present in the current code, so they're out-of-scope for the migration itself:

- Firebase / FCM — no `firebase_*` packages, no `google-services.json`, no Firebase init
- Push notifications (any kind) — `notifications_repository.dart` exists but it polls the API, no native push handler
- Deep links (`uni_links` / `app_links`)
- WebView, QR scanner, biometrics / `local_auth`
- `share_plus`

I'll flag these as **future work** in the plan, not blockers.

---

## 2. Decisions (locked)

### 2.1 DI → Riverpod-only ✅
Repo already uses Riverpod providers ([lib/providers.dart](lib/providers.dart)). GetIt would be a second source of truth for zero gain. The Mynt Plus Web spec said GetIt because that's what the reference uses, not because it's better.

### 2.2 Folder layout → keep `core/data/features/widgets` ✅
Renaming ~80 files for zero behavioural change destroys git blame. The spec's structure was descriptive (clear separation), not prescriptive (literal names). New work goes into `lib/platform/` and `lib/core/responsive/`.

### 2.3 Web secure storage → accept localStorage on v1 ✅
`flutter_secure_storage` on web ≈ unencrypted localStorage. Encrypting localStorage with a key that also lives in JS is security theater — anyone with XSS gets both. Real fix is short-lived tokens + httpOnly refresh cookies, which is a backend change. **Park for v2 with security review.**

### 2.4 TLS for `ticket.mynt.in` → fix server, don't block coding ✅
- File infra ticket to install the correct intermediate cert bundle on `ticket.mynt.in`.
- **Also file CORS headers on the same ticket** — web needs `Access-Control-Allow-Origin`, `Access-Control-Allow-Headers: Authorization, Content-Type, Accept`, `Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS` on `/scp/api.php/*`. Mobile doesn't enforce CORS so this never surfaced before.
- Web targets staging (`https://staging-ticket.mynt.in`) until both are fixed.
- Add a clear web-only error in the API client when handshake/CORS fails: *"Helpdesk server is not reachable from the browser — contact infra."*
- **Release-gate, not coding-gate.** Proceed with everything except shipping web to prod users.

### 2.5 Web export UX → Blob + `URL.createObjectURL` + anchor click ✅
Standard, works in every browser. `data:` URLs cap around 2 MB in some browsers and look sketchy. Mobile keeps the existing temp-file + `launchUrl` flow.

### 2.6 Base URL env-var name → `API_BASE_URL` ✅
Current code reads `String.fromEnvironment('ZEBU_BASE_URL')`. Renaming to `API_BASE_URL` matches the staging-build command and is more conventional. Two-file edit (`config.dart` + `README.md`); no automated pipeline depends on the old name. Default URL (`https://ticket.mynt.in`) unchanged.

### 2.7 Build-gate matrix ✅
| Where | Gate |
|---|---|
| Every commit (Windows dev) | `flutter analyze` + `flutter build apk --debug` + `flutter build web --debug` |
| Pre-PR (Mac) | `flutter build ios --debug --no-codesign` |
| Merge to main | All three (apk, ios, web) green |

### 2.8 Web branding ✅
Pulled from mobile identity. Exact `theme_color` and brand color values to be confirmed from [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart) at step 10 (placeholder `#0052CC` until then).
- `<title>`: **Mynt Helpdesk**
- meta description: *"Mynt Helpdesk — staff ticketing console"*
- manifest `name`/`short_name`: *"Mynt Helpdesk"* / *"Helpdesk"*
- PWA `display: standalone`, `start_url: "."`, `background_color: "#FFFFFF"`
- Icons: reuse highest-res Android launcher icon, resize to 192 / 512 / 512-maskable, drop into `web/icons/`

### 2.9 Staging URL ✅
Working assumption: `https://staging-ticket.mynt.in`. Wired via `--dart-define=API_BASE_URL=https://staging-ticket.mynt.in`. Hostname is being confirmed with infra in parallel — if it differs, that's a one-line CLI swap, **not** a code change. Not a blocker.

---

## 3. Target structure after migration

Only **net-new** items shown; everything else stays where it is.

```
lib/
├── ...                                  # all existing files unchanged
├── core/
│   ├── responsive/
│   │   ├── breakpoints.dart             # 600 / 905 / 1240 / 1440 cutoffs
│   │   └── responsive.dart              # isMobile / isTablet / isDesktop helpers
│   ├── network/
│   │   └── ssl_override.dart            # becomes a barrel; see lib/platform
│   └── export/
│       └── table_export.dart            # uses lib/platform/file_save.dart
└── platform/
    ├── ssl_override.dart                # conditional export
    ├── ssl_override_io.dart             # current HttpOverrides logic
    ├── ssl_override_web.dart            # no-op
    ├── file_save.dart                   # conditional export
    ├── file_save_io.dart                # File + launchUrl
    ├── file_save_web.dart               # blob download via package:web
    ├── secure_storage.dart              # conditional export (only if §2.3 → option b)
    ├── secure_storage_io.dart
    └── secure_storage_web.dart

web/                                     # generated by flutter create
├── index.html
├── manifest.json
├── favicon.png
└── icons/...
```

Conditional-import pattern (used by all three abstractions):

```dart
// lib/platform/file_save.dart
export 'file_save_io.dart'
    if (dart.library.js_interop) 'file_save_web.dart';
```

---

## 4. Execution order (small, verifiable steps)

Every step ends with the gate: `flutter analyze` **and** `flutter build apk --debug` succeed. From step 3 onward, `flutter build web --debug` also succeeds.

### Phase A — Make sure mobile is healthy
1. **Rename env var.** `ZEBU_BASE_URL` → `API_BASE_URL` in [lib/core/config.dart](lib/core/config.dart) and [README.md](README.md). Two-line change, no other refs in repo. *(Decision §2.6)*
2. **Baseline build.** Run `flutter pub get`, `flutter analyze`, `flutter build apk --debug`. Mac pre-PR also runs `flutter build ios --debug --no-codesign`. Record green state. Commit: `chore: rename ZEBU_BASE_URL to API_BASE_URL`.

### Phase B — Add web target (no code changes)
3. **`flutter create . --platforms=web`** — adds `web/` only. Verify `android/` and `ios/` untouched.
4. **First web build attempt.** `flutter build web --debug` will fail on the `dart:io` imports in `main.dart`, `ssl_override.dart`, `table_export.dart`. Expected; this step exists to *see* the failures and confirm no other surprise.
5. **Re-run mobile build.** Confirm `flutter build apk --debug` still green. Commit: `chore: add web platform target`.

### Phase C — Platform abstractions
6. **SSL override.** Create `lib/platform/ssl_override.{dart,_io.dart,_web.dart}`. Update `lib/main.dart` to call the abstracted version. Delete `lib/core/network/ssl_override.dart` (moved). Gate: mobile + web debug build. Commit.
7. **File save / export.** Create `lib/platform/file_save.{dart,_io.dart,_web.dart}` exposing `Future<void> saveAndReveal(Uint8List bytes, String filename, String mime)`. Refactor `table_export.dart` to use it. Web impl: blob + `URL.createObjectURL` + anchor click. Gate: mobile + web debug build, then **manual smoke test of export on Android**. Commit.
8. **Camera picker on web.** In `lib/widgets/pickers.dart` `attachMenuItems()`, hide the camera entry when `kIsWeb`. Gate: builds. Commit.
9. **Skip secure-storage abstraction** per §2.3 — accept localStorage on web v1.

### Phase D — Web infrastructure
10. **URL strategy.** Call `usePathUrlStrategy()` in `main.dart` (web-only via conditional import). Verify mobile deep-link behaviour unchanged. Gate: builds.
11. **`web/index.html` polish.** Apply §2.8 branding: title "Mynt Helpdesk", meta description, theme color (read from `app_theme.dart`), viewport, PWA manifest, favicon, app icons. Gate: `flutter build web --release` produces a working bundle locally (`flutter run -d chrome --dart-define=API_BASE_URL=https://staging-ticket.mynt.in`).

### Phase E — Responsive layer (one screen at a time)
12. **Responsive helper.** Add `lib/core/responsive/breakpoints.dart` + `responsive.dart` (600 / 905 / 1240 / 1440 cutoffs). Pure utility; doesn't change UI yet.
13. **Pilot screen — Dashboard.** Wrap [DashboardScreen](lib/features/dashboard/dashboard_screen.dart) in `LayoutBuilder`; on `>= 905` width, use a multi-column layout. Phone layout untouched at narrow widths. Manual mobile sanity check.
14. **Repeat per feature:** Tickets list → Ticket detail → Tasks → Users → Organizations → Reports → Settings/More. Each is its own commit. Each ends with a mobile build smoke.

### Phase F — Future work (not in this migration)
- Firebase init + `firebase_options.dart` — only when push/FCM is being added
- Web FCM service worker (`web/firebase-messaging-sw.js`)
- Deep links (`uni_links` / `app_links`)
- Web auth flow review (cookie vs. token storage)
- WebAuthn / biometrics, QR scanner, share_plus, WebView abstractions

### Phase G — Documentation
15. **CLAUDE.md** describing platform layout, build commands for all three targets (with `--dart-define=API_BASE_URL=...`), conditional-import pattern, and the "every change must build on mobile + web" rule.

---

## 5. Definition of done

- `flutter build apk --release`, `flutter build appbundle --release`, `flutter build ios --release`, `flutter build web --release` all green.
- No business logic, model, provider, or repository is duplicated between mobile and web. Only files under `lib/platform/` have `_io` / `_web` variants.
- All existing mobile screens render and behave identically to pre-migration (manual smoke test against staging).
- Web app loads at `/`, supports browser back/forward and shareable URLs (no `#`), and logs in against staging.
- A widescreen layout exists for at least Dashboard, Tickets list, and Ticket detail. Other screens degrade gracefully (mobile layout, centered with max-width) on wide viewports until they're tackled.

---

## 6. Infra ticket (parallel to coding — release-gate only)

File one ticket against the helpdesk server team covering both items:

1. **TLS intermediate cert bundle** on `ticket.mynt.in` — current chain is incomplete; mobile bypasses via `HttpOverrides`, browsers cannot. Required before web ships to prod.
2. **CORS headers** on `/scp/api.php/*`:
   - `Access-Control-Allow-Origin: <web origin>` (specific origin in prod; `*` acceptable for staging)
   - `Access-Control-Allow-Headers: Authorization, Content-Type, Accept`
   - `Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS`
   - Handle `OPTIONS` preflight with `204` + the headers above.
3. **Confirm staging hostname** = `https://staging-ticket.mynt.in` (if different, one-line CLI swap).

Track ticket # here once filed: `_____`.
