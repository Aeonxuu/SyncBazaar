# Refunds: build the app side

Read `CLAUDE.md` and `DESIGN_GUIDELINES.md` first. Explore the code, then show me a plan and wait for my OK before writing code.

Before branching: the working tree on `feature/vendor-payment-methods` has many uncommitted changes. Ask me whether to commit them first. Then work on a new branch `feature/refunds`.

## What we are building

Only two passwords can approve a refund: the owner's (works on every bazaar, past and future, by default) and the password of that bazaar's "refund handler" (one employee per bazaar, works only on that bazaar). The owner and every employee assigned to the bazaar see the refund button. Whoever taps it, the refund only goes through when one of those two passwords is typed. So a cashier can call the handler or the owner over to type their password. Admins cannot refund, but they can assign the refund handler. Every refund returns the item to the bazaar's stock. The person confirms with their own password. Each refund then shows as a negative row in Orders, in the Dashboard's Recent Orders, and in the orders workbook export.

## Approval method: password now, refund PIN later

Phases 1 to 4 use the login password and the online endpoint below, so refunds only work with a connection for now. The booth is often offline, and a pop-up can't ask a customer to come back another day, so phase 5 switches approval to a 6-digit refund PIN that the tablet can check offline. Phase 5 is blocked until Amrei ships the PIN endpoints (see `BACKEND_REQUEST_refunds.md`). Keep the approval step behind one seam (an `approveRefund` call in `RefundRepository` and one input widget in the dialog) so phase 5 swaps it without touching the rest.

## Backend contract

Source: `syncbazaar_backend`, commits `4541c11` to `447d9a2` (Oct 1). Use the same `/api/bazaar/` prefix the app already uses for sale endpoints. If the server behaves differently from what is written here, stop and tell me. Do not edit the backend repo.

### Issue a refund

`POST event/<event_pk>/sale/<sale_pk>/refund/`

Body:
- `amount`: decimal, greater than 0, not more than the sale total
- `method`: ModeOfPayment id (required)
- `reason`: optional, max 255 chars
- `return_item`: bool. Always send `true`. It marks the sale Returned and puts the quantity back into the bazaar's stock. The server rejects it on a finalized bazaar, so refunds only happen on bazaars that are not finalized.
- `authorizer_password`: required
- `client_uuid`: optional, for idempotent retry

201 returns the Refund: `id, sale, sale_return, amount, method, method_name, reason, issued_by, issued_by_name, authorized_by, authorized_by_name, customer_name, created_at, client_uuid`.

Errors:
- 403 `{"error": "No refund authorization available for this event."}` means wrong password OR no permission. The server does not say which.
- 400 `{"error": "This sale has already been refunded."}` (one refund per sale)
- 400 `{"error": "Cannot return items on a finalized event."}`
- 400 DRF field errors, for example amount above the sale total

Who may call it: the vendor's owner, or a user assigned to the bazaar. If the caller is the owner or the bazaar's refund handler, their own password must match. Otherwise the server tries the password against the owners and that bazaar's refund handler, and records whoever matches as `authorized_by`. `issued_by` is always the logged-in user. This is how a cashier's refund gets approved by the handler or owner on the same tablet. The app does not need to know who the handler is to make this work.

### List refunds

`GET event/<pk>/refund/` returns a list of Refund objects. Sale JSON carries no refund info, so join refunds to sales by `sale` id.

### Refund handler (RefundAuthorization), one active per bazaar

- `GET event/<pk>/refund-authorization/` (owner/admin only): `[{id, user, user_name, event, event_name, granted_at, granted_by, revoked_at, source_request}]`. Active means `revoked_at` is null.
- `POST event/<pk>/refund-authorization/<auth_pk>/revoke/` (owner/admin only)
- There is no direct grant endpoint yet. Granting is two calls:
  1. `POST event/<pk>/approval/` with `{"request_type": "RA", "details_json": {"user_id": <id>}}`
  2. `PATCH event/<pk>/approval/<new id>/` with `{"status": "AP"}` as owner/admin. This runs the grant. It returns 400 if another employee is already active.

Wrap this in one repository method, `grantRefundHandler(eventId, userId)`, so a direct endpoint can replace it later. Changing the handler means revoke the current one, then grant the new one.

## Known backend gaps (reported to Amrei, build around them)

1. Route every "may this user see the refund button at this bazaar" check through one function, `canRefund(user, event)`. It returns true for the owner, true for an employee assigned to that bazaar, and false for admins. The server decides whether the typed password is allowed, so the app never checks who the handler is.
2. The server does not yet check that an RA `user_id` is assigned to the bazaar, and does not revoke a handler who is removed from the bazaar. The app must cover both: only offer assigned employees, and revoke when the handler is unassigned.
3. `approval_api_mapper.dart` maps unknown request codes to the SOA type. New codes `RA` and `RF` would show in Pending Approvals as statement-of-account requests. Fix that so they never appear as SOA. Our grant flow approves RA requests right away, and RF requests are out of scope, so filtering both out of Pending Approvals is fine.

## UI

### 1. Assigning the refund handler

Places: the Preparations bazaar details step (staff assignment section), and `BazaarInfoDialog` in `pos_screen.dart` (the "i" button in Sales).

Add a "Refund handler" single-select under the assigned staff list. Options: "None" plus the employees assigned to this bazaar. Only owners and admins can change it. Employees do not see this control.

Why a single-select and not a separate "Refund" button that opens a list: the server allows one handler per bazaar, and a single-select states that rule on sight. It also sits next to the staff list it draws from, so there is no extra screen.

Rules:
- In Preparations the bazaar has no id until it is created. Send the grant after the bazaar and its staff assignments save.
- If the handler is removed from the bazaar's staff, revoke the handler.
- Owners already have refund rights everywhere. Admins cannot refund. List only employees as options.

### 2. Refund button in Orders

In a bazaar's order table, add a trailing column to the right of TOTAL with a square (1:1) icon button. Use `Icons.undo_rounded` or similar, with a "Refund" tooltip and semantics label. Neutral style, not red.

- Show it only when `canRefund(user, event)` is true, the sale has no refund, the sale is not already Returned, and the bazaar is not finalized.
- Keep the column width fixed on every row so totals stay aligned.
- On a sale that already has a refund, show a small "Refunded" tag in that slot.
- Until phase 5, disable the button when offline (`api.servingCacheFrom` is the signal), with the tooltip "Refunds need a connection". A network error in the dialog shows the same message. Do not queue refunds before phase 5.
- Keep `OrdersState.visibleRecords` as it is. Employees still see only their own sales, so they refund their own sales and the handler or owner types the password on their tablet.

### 3. Refund dialog

Reuse `confirmation_dialog.dart` and `floating_label_text_field.dart` where they fit.

Content:
- Sale summary: customer, product, payment method, time, total
- Amount: the full sale total, read-only. No partial refunds in this version.
- Refund via: payment method dropdown, default the sale's original method
- Reason: optional text
- A plain line saying the item goes back to the bazaar's stock. No checkbox, `return_item` is always true.
- Password: obscured field labelled "Owner or refund handler password", with helper text "Ask the owner or this bazaar's refund handler to enter their password."

Buttons: Cancel, and "Refund PHP 1,900.00" (the real amount) in the destructive color, disabled until the password field has text.

Behavior:
- Generate one `client_uuid` when the dialog opens and reuse it on retry. The server currently answers a repeated `client_uuid` with 400 "already refunded". Treat that as success: reload, and if the refund is there, close the dialog normally.
- Show a loading state while the request runs.
- On 403, keep the dialog open, clear the password, and show inline: "That password can't approve refunds at this bazaar."
- On other errors, show the server's message inline.
- On success, close, show a confirmation message that names who approved it (`authorized_by_name`), and reload the bazaar's sales and refunds.

### 4. Refunds in the records

Each refund is its own row: timestamp is the refund's `created_at`, amount is negative, status is "Refunded". The original sale row keeps its positive total and shows as Returned, since every refund brings the item back. The money came in and then went out, so a column of totals sums to the cash actually on hand.

- Orders screen: refund rows sort by time with the rest. Total shows as `-PHP 1,900.00` in the error color. Sub-line: refund time, refund method, and `authorized_by_name`.
- Dashboard Recent Orders (`customer_history_card.dart`, built in `dashboard_cubit.dart`): refund rows with a negative amount and status "Refunded".
- Orders workbook (`orders_workbook.dart`, exported from `post_bazaar_screen.dart`): a refund line goes on the sheet of the refund's method, with negative total and unit price, and status "Refunded". Sheet totals net out.
- Dashboard revenue: Returned sales drop out of every money and unit sum (revenue, today, daily chart, average order value, top bazaar, busiest day, top product and variant, units sold). Total Orders and the completion rate still count them. Every refunded sale is Returned, so this also removes refunds from revenue. Do not subtract refund rows on top of that, or the refund counts twice. Refund rows are for display only, and a test pins that they never reach a sum. This also changes the numbers for sales the server already marked Returned. That is intended.
- Leave `report_service.exportListOfOrders` (the server CSV) alone. Nothing in the UI calls it, and Amrei is updating the server report.

Data layer: add a `Refund` model and an api mapper. Fetch refunds per bazaar next to sales in `SalesRepository._fetchEventSales`, or in a new `RefundRepository` wired in `app.dart`. Give `TransactionRecord` a kind (sale or refund), or add a separate record type, whichever reads cleaner.

## Tests

- Unit: refund mapper, revenue not double-counting refunds, the workbook refund line, `canRefund`, the approval mapper no longer turning RA/RF into SOA
- Widget: refund dialog states (empty password, loading, 403, success)
- Run `flutter analyze` and `flutter test`

## Order of work

Stop after each phase so I can test on macOS with `USE_BACKEND=true`.

1. Data layer: Refund model, mapper, repository calls, grant/revoke methods, approval mapper fix
2. Orders: refund column, dialog, refund rows
3. Refund handler single-select in Preparations and the bazaar info dialog
4. Records: dashboard rows and revenue rule, orders workbook
5. Offline refunds with a refund PIN (blocked on backend, see below)

## Phase 5: offline refunds with a refund PIN

Start only after Amrei ships the PIN endpoints and after the sale queue survives an app restart (local persistence). A refund made offline must not vanish when the app closes.

- **Setting a PIN.** Owner and employees can set a 6-digit refund PIN from their account, online, by confirming their login password. `POST /api/auth/refund-pin/` with `{password, pin}`.
- **Downloading verifiers.** When a bazaar opens while online, fetch `GET event/<pk>/refund-verifiers/`: PIN hashes for the vendor's owners and the bazaar's active handler. Store them with `flutter_secure_storage`, scoped to that bazaar. Delete them on logout and when the bazaar is finalized or ends.
- **Dialog.** Replace the password field with a 6-digit PIN pad labelled "Owner or refund handler PIN".
- **Online.** Send `authorizer_pin` to the refund endpoint and let the server check it.
- **Offline.** Hash the typed PIN with the stored salt and iterations and compare it to each stored verifier. On a match, record the refund locally with `authorized_by` set to that person and `authorized_at` set to now, return the item to local stock, show it in Orders, and queue it. Never store the PIN itself.
- **Lockout.** After 5 wrong PINs on this tablet, block refunds for 5 minutes. Persist the counter so a restart does not reset it.
- **Sync order.** Send queued sales first, then queued refunds. A refund for a sale made offline points to the sale by `sale_client_uuid`.
- **Rejected at sync.** If the server refuses a queued refund (for example, the handler was revoked before the refund time), keep the row, mark it "Refund rejected by server", and notify the owner on next login. The cash already went out, so it must stay visible for the owner to settle.
- **Known limitation to document.** A handler change made while the tablet is offline only reaches the tablet on its next sync.
