# SyncBazaar — Terminal Commands

Quick reference for common dev tasks. Run these from the `syncbazaar/` project folder unless noted otherwise.

```bash
cd syncbazaar
```

If you open a brand new terminal window/tab, make sure `flutter`, `pod`, `java`, and `adb` are on your PATH first:

```bash
source ~/.zshrc
```

## Run the app in localhost (for testing in browser)

Flutter's `-d chrome` device only works with Chrome/Chromium (it relies on the Chrome DevTools Protocol). Firefox isn't a supported Flutter "device", so instead serve the app and open it in Firefox manually:

```bash
flutter run -d web-server --web-port=8080
```

- Then open **http://localhost:8080** in Firefox.
- Hot reload (`r`) / hot restart (`R`) still work from the terminal, but you'll need to manually refresh the Firefox tab afterward (the auto-refresh-on-reload behavior is Chrome-only).
- Press `q` in the terminal to stop the server.

## Run test cases

```bash
flutter test
```

- Runs all tests under `test/`.
- To run a single test file:

```bash
flutter test test/widget_test.dart
```

## Run the .py file with mock data for testing

```bash
python3 tool/generate_mock_data.py
```

- Regenerates `assets/dev/mock_data.json` with fresh random companies, bazaars (incoming/ongoing/finished), products (Nike/Adidas/On Cloud/Onitsuka Tiger with Color+Size variants), and sales/orders for the ongoing and finished bazaars.
- The app only loads this file in **debug builds** (`flutter run`, not `flutter build ... --release`) — it's seeded automatically on startup via `DevMockDataSeeder`, so nothing else to run.
- After regenerating, **hot restart (`R`)**, not hot reload (`r`) — the seeding happens once at app startup, so a plain hot reload won't pick up new data.
- To sanity-check the generated data without launching the full app:

```bash
flutter test test/dev_mock_data_seeder_test.dart
```

---

## Notes

- This file lives outside `syncbazaar/` on purpose, so it isn't tied to the Flutter project structure.
- Update this file whenever a new recurring dev command is introduced (new scripts, seeding tools, linting, build commands, etc.).


