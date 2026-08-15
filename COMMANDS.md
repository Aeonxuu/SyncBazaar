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

## Run the app against the backend

The app talks to the mock dataset unless told otherwise. `USE_BACKEND=true` switches it to the real
API and suppresses the mock seeding, so the two never appear on screen at once.

**Against the hosted backend** — the usual choice. Nothing to start, and the URL does not change
when the wifi does:

```bash
flutter run -d macos \
  --dart-define=API_BASE_URL=https://syncbazaar-backend.onrender.com \
  --dart-define=USE_BACKEND=true
```

**Against a backend running on this machine** — for testing changes to the API before they are
pushed:

```bash
# in the backend repo, after any git pull:
cd ~/Documents/GitHub/syncbazaar_backend
source venv/bin/activate
pip install -r requirements.txt    # skip and you get ModuleNotFoundError
python manage.py migrate
python manage.py runserver

# then, in syncbazaar/:
flutter run -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=USE_BACKEND=true
```

The host differs by target, because "this machine" means something different to each:

| Target                | Host                                  |
| --------------------- | ------------------------------------- |
| macOS / web / desktop | `http://127.0.0.1:8000`               |
| Android emulator      | `http://10.0.2.2:8000`                |
| Physical tablet       | this Mac's LAN IP, e.g. `192.168.1.x` |

The tablet cases need `python manage.py runserver 0.0.0.0:8000` — the default binds to localhost
only and refuses connections from the network. The hosted backend avoids all of this, which is why
it is the default choice for tablet testing.

**The first call after a quiet spell is slow.** The hosted backend sleeps after about fifteen
minutes idle and takes roughly twenty seconds to wake. The app allows for this; a login that seems
to hang for twenty seconds is normal, and only the first one does it.

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


