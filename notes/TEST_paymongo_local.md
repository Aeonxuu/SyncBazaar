# Testing the QR payment dialog against a local backend

**Written:** 2026-09-12
**For:** the `feature/paymongo-qr` branch, commit `b1acb36`
**Companion to:** `notes/PLAN_paymongo_qr_checkout.md`

This walks through running Amrei's backend on your Mac and pointing the app at it, so you can watch
the QR dialog talk to a real PayMongo test account.

Everything here was checked against the backend clone at
`/Users/lj/Documents/GitHub/syncbazaar_backend` on 2026-09-12, at commit `6b1173b`.

---

## Read this before anything else

> ### Never scan the QR with a real e-wallet app
>
> PayMongo's test mode issues **real QR codes**. Pointing GCash or Maya at one moves real money out
> of a real account. It does not matter that the key says `sk_test`.
>
> Pay the test QR by opening the **`test_url`** that comes back with it. That is the safe simulator,
> and part 4 below shows where to find it.
>
> Do not put a test QR on a projector, in a slide, or in a screenshot you share.

Two other things worth knowing before you start:

- **You need internet even though the server is on your laptop.** Your Mac talks to the local
  Django server, but Django talks out to PayMongo, and the QR picture itself is downloaded from
  PayMongo's servers.
- **You need your PayMongo test secret key**, the one starting `sk_test_`. It is in the PayMongo
  dashboard under *Developers → API Keys*. Keep it out of the Flutter app and out of git; part 1
  puts it in the one place it belongs.

---

## Part 1: Run the backend on your Mac

### 1. Open a terminal and go to the backend folder

```bash
cd ~/Documents/GitHub/syncbazaar_backend
```

Leave this terminal open. The server runs here, and you will want to watch what it prints.

### 2. Get the latest backend code

```bash
git pull
```

**What you should see:** either "Already up to date." or a list of changed files.

**If it complains about local changes:** you have edits in the backend repo. Do not force anything.
Run `git status` and ask Amrei, since that is their repo.

### 3. Put the PayMongo key in the `.env` file

The backend reads its secrets from a file called `.env`. Add your key to the end of it:

```bash
echo 'PAYMONGO_SECRET_KEY=sk_test_PUT_YOUR_KEY_HERE' >> .env
```

Replace `sk_test_PUT_YOUR_KEY_HERE` with your real test key first. Then check it landed:

```bash
grep PAYMONGO .env
```

**What you should see:** one line, `PAYMONGO_SECRET_KEY=sk_test_...`.

**If you see two lines:** you ran the command twice. Open the file (`open -e .env`) and delete the
duplicate. Django reads the first match, so a stale one on top will quietly win.

**Is it safe to put the key there?** Yes. The backend's `.gitignore` blocks anything starting with
`.env`, so the key cannot be committed by accident. It also never reaches the Flutter app: the app
only ever talks to your Django server, and the server is the only thing holding the key.

**Do not** put this key anywhere in the SyncBazaar Flutter repo. Anyone can unpack an installed app
and read what is inside it.

### 4. Turn on the Python environment and install what is missing

```bash
source venv/bin/activate
pip install -r requirements.txt
```

**What you should see:** your prompt gains a `(venv)` prefix, then either "Requirement already
satisfied" for everything, or a short download for anything new.

**If `source` fails with "No such file or directory":** the `venv` folder is missing. Create it with
`python3 -m venv venv`, then run the two commands above again.

### 5. Update the database

```bash
python manage.py migrate
```

**This one is not optional.** Your local database was last updated at migration `0007`, and the QR
payment table arrived in `0015`. Ten migrations will apply, including the one that creates the table
the QR endpoints write to. Skip this and every QR request fails with a database error about a
missing table.

**What you should see:** a list of `Applying bazaars.00xx... OK` lines.

### 6. Start the server

```bash
python manage.py runserver
```

**What you should see:** `Starting development server at http://127.0.0.1:8000/`.

**If it says "That port is already in use":** you have another server running from an earlier
session. Find it and stop it:

```bash
lsof -ti:8000 | xargs kill
```

Then start it again.

Leave this terminal running. Everything the app asks the server will scroll past here, which is how
you confirm the polling is really happening, and really stopping.

### 7. Check the server answers, before involving the app

Open a **second** terminal window (the first one is busy running the server) and ask it for a login
token:

```bash
curl -s -X POST http://127.0.0.1:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"owner@syncbazaar.com","password":"123456"}'
```

**What you should see:** a blob of JSON starting with `{"token":"...`.

**If you see nothing at all:** the server is not running. Go back to step 6.

**If you see `{"error":"Invalid login credentials"}`:** the local database does not have that
account. Seed it with `python manage.py seed_syncbazaar_data` in the first terminal (stop the server
with `Control-C`, run the seed, then start the server again).

Now try creating an actual payment code. Copy the token from the response above into this command:

```bash
curl -s -X POST http://127.0.0.1:8000/api/bazaar/qr-intent/create/ \
  -H "Authorization: Token PASTE_YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{"amount":"25.00"}'
```

**What you should see:** JSON with `intent_id`, `qr_image`, `test_url`, `"status":"PD"` and
`"amount":2500`.

- `"status":"PD"` means pending. That is correct for a code nobody has paid yet.
- `"amount":2500` is **not** a bug. You sent 25 pesos; the server stores centavos, because that is
  the unit PayMongo wants. 25 pesos is 2500 centavos.

**If you see `"error":"Failed to create payment intent."`:** the server reached PayMongo and
PayMongo refused. Look at the `detail` field in the same response. A `401` in there means the key in
`.env` is wrong or was not picked up, so restart the server after checking step 3.

**If the command hangs for a long time:** the server makes three calls out to PayMongo to build one
code. A slow connection shows up here. This matters later, and part 5 explains why.

Getting this far proves the backend half works. If the app then misbehaves, you know the problem is
on the app side.

---

## Part 2: Point the app at your Mac instead of Render

There is no setting to change and nothing to switch back afterwards. The address is passed in on the
command line each time you launch, so you pick which backend you get by picking which command you
run.

### Against your local server (what this test needs)

Open a **third** terminal:

```bash
cd ~/Documents/GitHub/SyncBazaar/syncbazaar
source ~/.zshrc
flutter run -d macos \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=USE_BACKEND=true
```

### Against Render again (to change it back)

Just run the other command. Nothing needs undoing:

```bash
flutter run -d macos \
  --dart-define=API_BASE_URL=https://syncbazaar-backend.onrender.com \
  --dart-define=USE_BACKEND=true
```

### Two things to know

**Use the Mac app, not the tablet, for this test.** `127.0.0.1` means "the machine I am running on",
so the tablet would look for the server on itself and find nothing. Running this on the tablet
instead needs `python manage.py runserver 0.0.0.0:8000` and your Mac's LAN IP in place of
`127.0.0.1`. Save that for after the Mac run works.

**Log in with `owner@syncbazaar.com` / `123456`.** Your local database has its own accounts, separate
from Render's. An account you made on the hosted backend does not exist here.

---

## Part 3: Open the dialog

Nothing in the app calls the new dialog yet. Wiring it into Finish properly is step 6 of the plan and
is deliberately not done, so to see it you add a temporary hook and take it out afterwards.

### 1. Open the POS screen file

```bash
open -a "Visual Studio Code" ~/Documents/GitHub/SyncBazaar/syncbazaar/lib/ui/screens/pos/pos_screen.dart
```

### 2. Add two imports

Near the top, after the line `import 'widgets/qr_payment_dialog.dart';` (line 37), add:

```dart
import 'widgets/qr_auto_payment_dialog.dart';
import '../../../services/qr_payment_service.dart';
```

### 3. Swap the dialog at the Finish button

Find this, at roughly line 806:

```dart
                          if (state.requiresQrPresentment) {
                            final reference = await showQrPaymentDialog(
                              context: context,
                              paymentMethod: state.selectedPaymentMethod,
                              qrBytes: state.selectedPaymentQr!,
                              amount: state.total,
                              extraFieldLabel: state.selectedExtraFieldLabel,
                            );
                            if (reference == null) return;
                            posCubit.updatePaymentExtraFieldValue(reference);
                          }
```

Replace the whole block with this:

```dart
                          // TEMPORARY test hook for the PayMongo QR dialog.
                          // Revert with: git checkout lib/ui/screens/pos/pos_screen.dart
                          if (!state.requiresCashTendered) {
                            final result = await showQrAutoPaymentDialog(
                              context: context,
                              paymentMethod: state.selectedPaymentMethod,
                              amount: state.total,
                              service: QrPaymentService(
                                auth: context.read<AuthRepository>(),
                              ),
                              extraFieldLabel: state.selectedExtraFieldLabel,
                            );
                            if (result == null) return;
                            posCubit.updatePaymentExtraFieldValue(result.reference);
                          }
```

The condition changed on purpose. The old one only fired for a payment method with a QR picture
saved on the device, which would mean uploading one first. The new one fires for **any payment
method that is not cash**, so there is nothing to set up.

### 4. Take the hook out when you are finished testing

```bash
cd ~/Documents/GitHub/SyncBazaar/syncbazaar
git checkout lib/ui/screens/pos/pos_screen.dart
```

That undoes both edits in one go. Run `git status` afterwards and confirm `pos_screen.dart` is no
longer listed. **Do not commit this hook.** Step 6 of the plan wires this in properly, with the
reference marked as automatic or manual, and this shortcut skips all of that.

### 5. Get to the dialog in the running app

1. Log in as `owner@syncbazaar.com` / `123456`.
2. Open **POS** and pick a bazaar that is running today.
3. Add a product to the cart. Keep the total **above 1 peso**, since the backend rejects anything
   smaller.
4. Choose any payment method **other than CASH**.
5. Tap **Finish**.

The QR dialog should appear.

---

## Part 4: What you should see, and what it means if you do not

### Step 1: The dialog opens on "preparing"

**You should see:** a brief loading state while the app asks the server for a code.

**If it sits there for more than about ten seconds and then says it failed:** the app gives up after
ten seconds. Look at the server terminal. If it is still working, the request went out fine and
PayMongo was just slow.

To retry, tap **Cancel** and tap **Finish** again. There is no retry button on the failure state
itself, only on expiry, which is worth knowing before you go looking for one.

**If it fails instantly:** check the server terminal for a red error. No request arriving at all
means the app is pointed at the wrong address, so check the `API_BASE_URL` in your run command.

### Step 2: The QR appears

**You should see:** a QR code, the amount, and wording asking the customer to scan. Below it, an
**Enter reference manually** button and a **Cancel**.

**If you get a broken image icon instead:** the picture is downloaded from PayMongo's servers, so
this is your internet, not the local server.

**In the server terminal you should see:** a `GET /api/bazaar/qr-intent/.../status/` line appearing
every three seconds. That is the app checking whether the money arrived. If those lines are not
appearing, the polling is not running and that is a real bug worth reporting.

### Step 3: Pay it, safely

**Do not scan the code.** Get the `test_url` instead and open it in your browser. Two ways:

- Easiest: run the `curl` create command from part 1 step 7 in your second terminal, and use the
  `test_url` from that response. It gives you a separate code you can pay freely.
- Or look in the server terminal output for the intent, and fetch it from the PayMongo dashboard.

Opening the `test_url` gives you a page where you choose to authorise or fail the payment.

**You should see, within about three seconds of authorising:** the dialog switches to a paid
confirmation, holds for a moment so it can actually be read, then closes on its own and drops the
reference number into the payment field behind it.

**The reference looks like `pay_abc123...`.** That is PayMongo's own payment id. It is **not** the
reference number a customer sees in their GCash app, so do not expect those to match.

**If it stays on "waiting" after you authorised:** watch the server terminal. It prints
`PayMongo status:` on every check. If that keeps saying `awaiting_next_action`, PayMongo has not
registered the payment yet and waiting longer is the right move.

### Step 4: Losing the connection mid-wait

With the QR on screen, stop the server: click the first terminal and press `Control-C`.

**You should see:** the QR stays on screen and a small reconnecting note appears. The dialog must
**not** fail, and must **not** close.

Start the server again (`python manage.py runserver`).

**You should see:** the note disappears by itself within a few seconds, and the waiting carries on.

This is the behaviour you asked for: a customer may have already paid, so one dropped request is not
a reason to give up.

### Step 5: The manual way out

Tap **Enter reference manually** at any point while it is waiting.

**You should see:** the QR is replaced by a text field, and the polling stops. Check the server
terminal, the status lines should stop appearing. If they keep coming, that is a real bug.

Typing a reference and confirming closes the dialog with what you typed.

### Step 6: Cancelling

Tap **Cancel** while waiting.

**You should see:** the dialog closes, no sale is created, and the polling stops in the server
terminal.

Read part 5 before judging what happens on the server side afterwards.

---

## Part 5: Known issues, so you do not report them as new

These are already recorded. Seeing them in this test is expected.

### 1. Cancelling leaves a stuck record on the server

There is no cancel endpoint. When you close the dialog, the app simply stops asking, and the payment
record stays on the server as pending forever. Nothing cleans it up.

It is harmless in testing, but it means a count of pending payments is not a count of anything real.
Amrei has this on their list.

### 2. Closing the app mid-wait loses the payment

There is no webhook, so the server only ever learns about a payment because the app asked. Close the
app while a customer is paying and the money goes through at PayMongo while your system has no
record of it and no sale.

The workaround is the one in the plan: find the payment in the PayMongo dashboard and redo the sale
with a manually typed reference. This is a genuine limitation of the current design, not a bug to
report.

### 3. The failed state is very hard to trigger

The backend translates PayMongo's wording into its own codes, and it looks for the words `failed`
and `expired`. PayMongo's payment intents do not actually use those words; a refused payment goes
back to `awaiting_payment_method` with the reason attached separately.

So even if you choose "fail" on the test page, expect the dialog to keep waiting rather than show
the failure. The app's failed state is tested and works, it just has nothing to trigger it yet.

### 4. Expiry takes thirty minutes

The server marks a code expired after thirty minutes, and only when something asks about it. So
testing the expired state means leaving the dialog open for half an hour.

### 5. `paid_at` is when the server noticed, not when the customer paid

It is stamped at the moment a check comes back paid. If nobody is checking, it is never set at all.
Do not read it as the time of payment.

### 6. The amount reads oddly in the database

The app sends pesos as a decimal string, like `"2300.50"`. The server stores centavos, so Django
admin shows `230050`. Both are correct; they are just different units.

### 7. Sales under 1 peso are refused

The backend sets a floor of 1 peso. Not a problem in real use, but it will stop a tiny test cart.

---

## Quick reference

| What | Command |
| --- | --- |
| Start the backend | `cd ~/Documents/GitHub/syncbazaar_backend && source venv/bin/activate && python manage.py runserver` |
| Stop the backend | `Control-C` in that terminal |
| Free up port 8000 | `lsof -ti:8000 \| xargs kill` |
| App against local | `flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=USE_BACKEND=true` |
| App against Render | `flutter run -d macos --dart-define=API_BASE_URL=https://syncbazaar-backend.onrender.com --dart-define=USE_BACKEND=true` |
| Remove the test hook | `cd ~/Documents/GitHub/SyncBazaar/syncbazaar && git checkout lib/ui/screens/pos/pos_screen.dart` |

Local login: `owner@syncbazaar.com` / `123456`
