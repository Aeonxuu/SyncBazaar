# Plan: automatic QR payment with PayMongo

**Status:** not started, waiting on backend endpoints (simpler flow chosen 2026-09-12)
**Opened:** 2026-09-12
**Why:** advisers asked that cashiers stop typing reference numbers by hand

Corrections go in **Changes** at the bottom with a date and a reason, rather than being edited into
the text above.

---

## Read this first

> **Superseded in part.** The 2026-09-12 "simpler flow" entry under **Changes** at the bottom
> replaces this section. Read that first.

Two things to settle before anyone writes code.

### The instructions this came from describe a different app

The brief mentions **Riverpod providers**, **Drift tables**, a **local Drift ID** and a `docs/`
folder. SyncBazaar uses **flutter_bloc** for state, **shared_preferences** for storage, and keeps
notes in `notes/`. There is no Drift and no local database at all. The *flow* in the brief is sound
and is what this plan follows; the file paths in it are not ours.

### One checkout is not one sale

This is the part that breaks the proposed API, and it is better found now than after it is built.

`PosCubit.completeSale` (`lib/bloc/pos/pos_cubit.dart:628`) loops over the cart and creates **one
`Sale` per line item**, each with its own `clientUuid` (`pos_cubit.dart:657-681`). A basket of four
products is four sale rows. There is no basket, order or checkout id grouping them: `Sale` and
`Order` both have no such field.

So `POST /sales/<sale_id>/qr/` has no single sale to attach to. A customer pays **one amount for the
whole basket**, not four amounts for four rows.

The backend needs something that represents the basket. Two ways, and the teammate should pick:

- **A checkout or payment record** the sale rows belong to. The QR attaches to that, and the
  reference lands on it once. Cleanest, and it matches what a receipt already shows.
- **The existing `Payment` model**, if it can hold one payment covering several sales. Worth
  checking what it links to today before inventing anything.

Until that is decided, nothing on the client can be built against a final shape.

---

## Is PayMongo feasible for a capstone?

Yes, in test mode, with one serious caution.

**What test mode gives you.** PayMongo issues test API keys from the dashboard under *Developers →
API Keys*. Test mode supports QR Ph, GCash, Maya, GrabPay and ShopeePay, and e-wallet payments can
be authorised without any real wallet account: the response carries a redirect where you choose
*Authorize* or *Fail*.

**The caution, and it matters more than anything else here.** PayMongo's own documentation says
that **in test mode, QR Ph still generates real QR codes**, and scanning one processes a real
transaction. At a capstone demo, in a room where people have phones, a QR on a projector is
something somebody will scan. Use the `test_url` the API returns to simulate payment instead.

**The uncertainty, stated plainly.** PayMongo's docs describe test keys and describe business
verification (KYB) for live mode, but do not say in so many words whether test keys are issued
before a business is verified. Every indication is that they are, since test mode exists to build
against before going live. **Confirm this by signing up and looking for the test key before
committing to the feature.** If test keys turn out to need verification, this whole plan stops.

**The secret key never goes in the Flutter app.** Anyone can unpack an APK and read it. Only the
backend talks to PayMongo. That is not a preference, it is the whole reason the flow below routes
through your own server.

---

## The current flow

What happens today when a cashier presses **Finish**, with file paths.

| Step | Where |
| --- | --- |
| Validate the reference field and cash tendered | `lib/ui/screens/pos/pos_screen.dart:779-800` |
| If the method has a QR, show it and collect the reference by hand | `pos_screen.dart:807-818`, dialog in `lib/ui/screens/pos/widgets/qr_payment_dialog.dart` |
| Confirm the sale | `pos_screen.dart:819`, dialog in `widgets/confirm_sale_dialog.dart` |
| Deduct stock, create one `Sale` per cart line, create `Order` rows | `lib/bloc/pos/pos_cubit.dart:628-690` |
| Save each sale to the device | `lib/data/repositories/sales_repository.dart`, `addSale` |
| Upload, fire and forget | `pos_cubit.dart` `_uploadSalesQuietly` at line 349 |
| Print the receipt | `pos_screen.dart:846`, `widgets/receipt_print_dialog.dart` |

**Answers to the questions the brief asked:**

- **When is the sale created and sent?** Created locally in `completeSale`. Sent afterwards by
  `SaleUploadService.uploadPending` (`lib/services/sale_upload_service.dart:49`), started with
  `unawaited(...)` so checkout never waits for it.
- **Does the sale reach the backend before payment?** **No.** Payment is settled first: the cashier
  types the reference into the QR dialog, then the sale is created. The server hears about it later,
  possibly much later if there is no signal.
- **How does the app get the server sale id?** **It does not.** Sales upload in a batch to
  `POST /api/bazaar/event/<id>/batch-sale/` (`sale_upload_service.dart:124`) and the response is
  discarded. The app tracks delivery with its own `clientUuid`, never a server id.
- **How is the reference captured now?** Typed into `qr_payment_dialog.dart`, carried on
  `Sale.employeeId` (a badly named field that holds the reference), and uploaded as
  `required_information` (`sale_upload_service.dart:113-115`).

---

## What has to change, and what it costs

> **Superseded in part.** The 2026-09-12 "simpler flow" entry under **Changes** at the bottom
> replaces this section. Read that first.

The new flow **inverts the order**: the sale must exist on the server *before* payment, because the
QR is generated against it. Today the sale is created after payment and uploaded later.

That collides directly with the offline work finished on 10 September, where the till sells with no
signal and queues sales. **A PayMongo QR cannot work offline** — it needs the server, which needs
the internet, which is the thing a bazaar does not have. So this is an additional path, never a
replacement. See `notes/PLAN_offline_storage.md`.

---

## Step-by-step changes

In order. Each step is useful on its own and can be checked before the next.

### 1. Give a checkout an identity

**File:** `lib/models/sale.dart`
**Change:** add a basket identifier that every sale in one checkout shares, minted once in
`completeSale` rather than per line.
**Why:** a QR is paid once for the whole basket, and today nothing ties the rows of one basket
together. This is also what the backend record in "Read this first" attaches to.

### 2. Let a sale be created on the server on demand

**File:** `lib/services/sale_upload_service.dart`
**Change:** add a method that uploads **one checkout immediately and returns the server's answer**,
alongside the existing `uploadPending`. Do not change `uploadPending`; the offline queue depends on
it behaving exactly as it does.
**Why:** the QR needs a server-side record to attach to, and the current upload is fire-and-forget
with its response thrown away.

### 3. Add a payment service

**File:** new, `lib/services/qr_payment_service.dart`
**Change:** three calls against your own backend, never PayMongo directly: ask for a QR, ask for its
status, cancel it.
**Why:** keeps PayMongo entirely behind your server, and gives one place to change when the response
shapes settle.

### 4. Rebuild the QR dialog around waiting

**File:** `lib/ui/screens/pos/widgets/qr_payment_dialog.dart`
**Change:** it currently shows a stored image and a text field. It becomes a screen with states:
asking for a QR, showing it and waiting, paid, expired, failed.
**Why:** the cashier no longer types anything. They watch for the app to say it arrived.

### 5. Poll for payment

**File:** the dialog's state class
**Change:** ask the backend every three seconds while the dialog is open. Stop on paid, expired,
failed, or when the dialog closes.
**Why:** the customer pays on their own phone, so the app has no other way to learn it happened.
**Watch for:** the timer must be cancelled in `dispose`. A timer left running after the dialog
closes keeps calling the server for the rest of the shift.

### 6. Wire it into Finish

**File:** `lib/ui/screens/pos/pos_screen.dart`, around line 807
**Change:** for a method with automatic payment, create the sale server-side first, then show the
QR, then wait. Only on payment does it continue to confirm and receipt.
**Why:** this is the inversion described above, and it is the step that changes the shape of
checkout.

### 7. Keep the manual path

**File:** `pos_screen.dart` and the dialog
**Change:** fall back to today's flow — stored QR, typed reference — when there is no connection,
when the QR expires, or when the cashier chooses to.
**Why:** a bazaar with no signal still has to take money. Removing the manual path would trade a
working offline till for a convenience.

### 8. Record how the reference arrived

**File:** `lib/models/sale.dart`, `lib/services/sale_upload_service.dart`
**Change:** mark each sale's reference as automatic or manual.
**Why:** when a figure is questioned later, "the gateway confirmed this" and "someone typed this"
are different kinds of evidence.

---

## Screen states

What the cashier sees. Every one of these needs a way forward; a state with no way out is where
people get stuck at a till with a customer waiting.

| State | Shows | Way out |
| --- | --- | --- |
| Preparing | Spinner, "Preparing the code" | Cancel |
| Waiting | The QR, the amount, "Waiting for payment" | Cancel, or switch to manual |
| Paid | Confirmation, then straight on to confirm and receipt | Continues by itself |
| Expired | "This code has expired", after 30 minutes | New code, or manual, or cancel |
| Failed | What went wrong, in the server's words | Try again, or manual, or cancel |
| Offline | "No connection. Use the saved code and enter the reference." | The current manual flow |

---

## API assumptions

**Every line below is an assumption.** The endpoints do not exist yet and the shapes are not final.
The backend teammate should confirm or correct each one before either side builds.

- **Assumed:** the QR is requested per checkout, not per sale row. See "One checkout is not one
  sale" above; the brief's `POST /sales/<sale_id>/qr/` cannot work as written.
- **Assumed:** the QR comes back as base64 so the app can show it without another fetch.
- **Assumed:** the response includes an expiry the app can display, rather than the app assuming 30
  minutes.
- **Assumed:** a status call returns something like pending, paid, expired or failed, plus the
  reference number once paid.
- **Assumed:** the backend writes the `Payment` and marks the sale paid, not the app. The app must
  never be the thing that decides a payment happened.
- **Assumed:** the backend handles PayMongo's webhook, so payment is recorded even if the app closes
  mid-wait.
- **Assumed:** there is a way to cancel or abandon a pending QR, so a walked-away customer does not
  leave a sale stuck.
- **Assumed:** the test `test_url` is passed through in test mode, so the app can offer a safe way
  to simulate payment without scanning.

---

## Offline fallback

If the connection is gone at checkout, the app uses **exactly today's flow**: show the stored QR
from Venues & Terms, take a typed reference, record it as manual, queue the sale as usual.

This is not a lesser path. A stall with no signal is the normal case at a bazaar, and the offline
work finished on 10 September exists precisely for it.

---

## Edge cases

- **Customer pays twice.** Two payments against one QR. The backend has to decide what happens;
  the app cannot.
- **Customer pays as the code expires.** The app may show expired while the money is in flight.
  The backend's webhook is the authority, not the app's polling.
- **App closes mid-wait.** The payment still lands. The sale must not be left unpaid because the
  tablet was locked, which is why the webhook matters more than the polling.
- **Cashier cancels after payment.** Needs a refund path, or a rule that cancel is unavailable once
  payment is detected.
- **Connection drops while waiting.** The poll fails. Keep the QR up and keep trying rather than
  declaring failure, since the customer may already have paid.
- **Two tills, one bazaar.** Two QRs at once is normal and must not collide.
- **Partial payment.** QR Ph may allow a different amount. Decide whether under-payment is a failure
  or a part-payment.

---

## Test checklist

> **Never scan a PayMongo test QR with a real e-wallet.** PayMongo's documentation states that test
> mode generates **real** QR Ph codes and scanning one processes a real transaction. Use the
> `test_url` from the response to simulate payment. This matters most during the demo itself, where
> a code on a screen in a room full of phones is exactly the situation where somebody scans it.

- [ ] Confirm test API keys are issued without business verification, before building anything else
- [ ] A basket of several products produces **one** QR for the total, not one per item
- [ ] Paying through `test_url` moves the app to paid within a few seconds
- [ ] The reference recorded matches the one PayMongo reports
- [ ] The receipt prints with that reference
- [ ] Expiry shows the expired state with a way forward
- [ ] Cancelling leaves no half-finished sale
- [ ] Killing the app mid-wait still results in a recorded payment
- [ ] Turning Wi-Fi off falls back to the manual flow
- [ ] A manual sale is marked manual, an automatic one automatic
- [ ] Closing the dialog stops the polling, verified by watching the server's logs
- [ ] Cash checkout is untouched

---

## Open questions

1. **What does the QR attach to?** Blocking. A checkout has several sale rows and no grouping id.
2. **Are test keys available before verification?** Blocking. Everything stops if not.
3. **Which methods become automatic?** GCash only, or every e-wallet? Today any method with an
   uploaded QR shows one.
4. **Who watches the tablet while waiting?** If the cashier serves the next customer, the QR screen
   is in the way. Does waiting need to move out of the modal?
5. **What happens to the stored QR codes** already uploaded per payment method? Kept for offline,
   or retired?
6. **Does the adviser expect this working, or designed?** A capstone can reasonably show a designed
   integration in test mode. Worth agreeing which, because "working with real money" is a much
   bigger commitment.
7. **Does PayMongo settle to an account you have?** Test mode does not move money, but a demo that
   claims a real payment path should be honest about whose account it would reach.

---

## Changes

**2026-09-12 — Test API keys confirmed.** Lala got the `sk_test` key after personal identity
verification. No DTI or BIR needed. Closes open question 2.

**2026-09-12 — Switched to a simpler flow.** The QR is no longer attached to a sale or a checkout.
Payment still happens before the sale is created, same as today.

Reason: the Checkout design needed a new model, immediate sale uploads, and changes to
`completeSale`, which is too much for our timeline.

New flow:

1. Cashier taps QR Ph. The app sends the basket total to `POST /qr/create/`.
2. Backend creates the PayMongo QR and returns `qr_image`, `intent_id`, and `test_url` if
   available.
3. App shows the QR and polls `GET /qr/<intent_id>/status/` every 3 seconds.
4. When paid, the backend returns `reference_number`. The app fills it into the existing reference
   field.
5. The app creates and uploads the sales exactly as it does today.

Cancelled: step 1 (checkout identity), step 2 (upload on demand), and the "create the sale
server-side first" part of step 6. The Checkout record in "Read this first" is no longer needed.

Still planned: step 3 (payment service), step 4 (dialog states), step 5 (polling, timer cancelled in
`dispose`), step 7 (manual fallback), step 8 (mark reference as auto or manual).

Backend: Amrei builds one standalone `QRPaymentIntent` model (`intent_id`, `amount`, `status`,
`reference_number`, `created_at`) and the two endpoints. `Sale`, `Payment` and `batch-sale` stay
unchanged.

Known limitations: the amount comes from the app. If the tablet closes mid-wait, the payment goes
through but no sale is created. The cashier finds the payment in the PayMongo dashboard and redoes
the sale with manual entry.
