# SyncBazaar

Flutter app for running pop-up bazaar/market events: pre-bazaar stock allocation, an on-site POS
till, orders, approvals, staff, and post-bazaar reporting.

## Repo layout

Docs live at the repo root; the Flutter project is one level down in `syncbazaar/`.
**Almost every command must be run from `syncbazaar/`, not the repo root.**

| Path | What's there |
| --- | --- |
| `syncbazaar/lib/bloc/<feature>/` | One Cubit per feature (`flutter_bloc`). All state lives here. |
| `syncbazaar/lib/data/repositories/` | Data access, wired up in `lib/app.dart`. All but `orders_repository` fetch from the API when a session exists and fall back to in-memory otherwise. |
| `syncbazaar/lib/data/remote/` | `api_client.dart` (the HTTP client, error kinds, token) plus one `*_api_mapper.dart` per resource, turning API JSON into models. |
| `syncbazaar/lib/models/` | Plain data classes. |
| `syncbazaar/lib/services/` | Cross-cutting logic: receipts, sync, notifications, dashboard analytics. |
| `syncbazaar/lib/ui/screens/<feature>/` | Screens, plus a `widgets/` subfolder for screen-local widgets. |
| `syncbazaar/lib/ui/widgets/` | Shared widgets. Check here before building a new control. |
| `syncbazaar/lib/core/constants/` | `colors.dart` and `motion.dart` — the canonical design tokens. |
| `syncbazaar/lib/core/routing/app_router.dart`, `core/theme/app_theme.dart` | Navigation and theme. |
| `syncbazaar/lib/dev/dev_mock_data_seeder.dart` | Loads `assets/dev/mock_data.json` on boot, debug builds only. |

## Commands

```bash
cd syncbazaar
source ~/.zshrc                              # new terminal: puts flutter/java/adb on PATH
flutter run -d web-server --web-port=8080    # browser testing (see COMMANDS.md for why not -d chrome)
flutter test                                 # widget + unit tests in test/
flutter analyze                              # flutter_lints ruleset
```

`COMMANDS.md` at the repo root is the source of truth for dev commands, including the flags for
running against the backend — update it when a new recurring one appears.

## Things that will bite you

- **The backend is real, but off by default.** `flutter run` with no flags boots the seeded demo
  data with no server involved. Pass `--dart-define=USE_BACKEND=true` (and `API_BASE_URL`) to talk
  to the Django API — see `COMMANDS.md`. The two are mutually exclusive on purpose: seeding is
  `kDebugMode && !ApiConfig.useBackend`, so a screen never mixes twelve server products with twelve
  seeded ones. Backend work is a separate teammate's scope; see `BACKEND_SCOPE.md` and
  `BACKEND_READINESS.md`.
- **Nothing is stored on the device except the session, the store name, and payment QR codes.**
  Products, bazaars, orders and sales are held in memory, so the app needs a connection when it
  cold-starts under `USE_BACKEND`. Selling continues once it is running and unsent sales queue with
  a `clientUuid` for idempotent retry, but that queue does not survive the app closing. Local
  persistence is the next substantial piece of work.
- **The mock fixture ages, and the seeder compensates.** `assets/dev/mock_data.json` holds absolute
  dates and records the day it was generated; `DevMockDataSeeder` shifts every bazaar forward by
  whole weeks on load so there is always one running today. August Fair is exempt and stays on its
  real calendar dates, because the revenue-shape test measures against it.
- **`tool/generate_mock_data.py` currently emits data that fails its own tests.** It can assign one
  employee to two overlapping bazaars, and its upcoming-event count can fall below what
  `dev_mock_data_seeder_test.dart` requires. You should not need to run it — the seeder's date
  shifting keeps the committed fixture current — so prefer leaving it alone until it is fixed.
- **Landscape-only, Android tablet first.** `main.dart` locks orientation to landscape. The
  production target is an Android tablet; macOS is the dev convenience and web is for quick testing.
  Judge layout and platform behavior against the tablet, not the browser window.
- **Booting the app in a widget test needs `seedMockData: false`.** The seeder does real
  `rootBundle` I/O, which never completes inside `testWidgets`' fake-async zone — a test that boots
  with seeding on hangs in `pumpAndSettle` until timeout. See the doc comment in `lib/app.dart`.
- **Fonts are bundled, not fetched.** Inter ships in `assets/fonts/` on purpose: `google_fonts`
  throws on an offline tablet, which once took down receipt printing entirely. Don't swap it for a
  runtime fetch.

## Design work

Read `DESIGN_GUIDELINES.md` before redesigning or restyling any screen. It carries the UI/UX laws,
numeric tokens, and component recipes established during the POS redesign. Two rules from it worth
repeating here:

- When the doc and the code disagree, **the code is correct** (`core/constants/colors.dart`,
  `motion.dart`) and the doc is stale — fix the doc.
- Reuse an existing widget from `lib/ui/widgets/` rather than inventing a parallel one. Consistency
  with the rest of this app beats any single screen looking slightly better in isolation.
