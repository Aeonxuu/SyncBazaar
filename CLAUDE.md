# SyncBazaar

Flutter app for running pop-up bazaar/market events: pre-bazaar stock allocation, an on-site POS
till, orders, approvals, staff, and post-bazaar reporting.

## Repo layout

Docs live at the repo root; the Flutter project is one level down in `syncbazaar/`.
**Almost every command must be run from `syncbazaar/`, not the repo root.**

| Path | What's there |
| --- | --- |
| `syncbazaar/lib/bloc/<feature>/` | One Cubit per feature (`flutter_bloc`). All state lives here. |
| `syncbazaar/lib/data/repositories/` | Data access. In-memory Dart collections, wired up in `lib/app.dart`. |
| `syncbazaar/lib/data/remote/api_service.dart` | Stub. Both methods just `await Future.delayed(...)`. |
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
python3 tool/generate_mock_data.py           # regenerate mock data, then hot RESTART (R), not reload
```

`COMMANDS.md` at the repo root is the source of truth for dev commands — update it when a new
recurring one appears.

## Things that will bite you

- **There is no backend.** Every repository is rebuilt in memory on launch, so sales, orders, and
  approvals are lost when the app closes. Only the login session and one settings string survive,
  via `shared_preferences`. `SyncService` reports "Sync completed" for an operation that never
  leaves the device. Backend work is a separate teammate's scope — see `BACKEND_SCOPE.md` (what
  moves server-side) and `BACKEND_READINESS.md` (whether the client is ready to connect).
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
