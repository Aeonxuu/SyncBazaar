# Refunds: build the app side

Read `CLAUDE.md` and `DESIGN_GUIDELINES.md` first. Work on `feature/refunds`. Stop after each phase so I can test.

This brief replaces the earlier version. Your answers from the planning round still stand unless this file says otherwise:
- Returned sales drop out of every money and unit sum (revenue, today, daily chart, average order value, top bazaar, busiest day, top product and variant, units sold). Total Orders and the completion rate keep counting them. The change to sales the server already marked Returned is intended. Never subtract refund rows.
- Offline signal is `api.servingCacheFrom`, plus network errors in the dialog. No `connectivity_plus`.
- The handler pick in `BazaarInfoDialog` applies immediately with an inline spinner and error.
- A 400 "already refunded" on a repeated `client_uuid` counts as success after a reload.
- After a failed grant, delete the stray RA request, best effort.
- The `assignedEventIds`-at-login risk is accepted. Keep it in the test steps.

## The rules

- **Who approves.** Only two passwords approve a refund: the owner's (every bazaar, past and future) and the password of that bazaar's refund handler (one employee per bazaar, that bazaar only). Admins cannot refund but can choose the handler.
- **Who taps.** The owner and every employee assigned to the bazaar see the refund button. Whoever taps it, the owner or handler types their own password on that tablet.
- **Item comes back.** Every refund returns the item to the bazaar's stock (`return_item: true` always).
- **Full refunds only.** The amount is always the sale total. One refund per sale.
- **Until finalized.** Refunds are allowed until the bazaar is finalized. After that, no refund button.
- **Exchanges.** A size exchange is a refund (reason "Wrong size") plus a new sale. Nothing extra to build.
- **Online first, offline later.** Phases 1 to 5 are online only. Phase 6 adds offline approval with a cached password hash and is blocked on backend work. Keep approval behind one seam (`approveRefund` in `RefundRepository` and one password widget in the dialog) so phase 6 adds a path without reshaping the rest.

## Backend contract (as of `447d9a2`, Oct 1)

Same `/api/bazaar/` prefix as the sale endpoints. If the server behaves differently, stop and tell me. Do not edit the backend repo.

### Issue a refund

`POST event/<event_pk>/sale/<sale_pk>/refund/`

Body: `amount` (sale total), `method` (ModeOfPayment id), `reason` (max 255), `return_item: true`, `authorizer_password`, `client_uuid`. Also send `reference` (see the dialog section). The server ignores it until Amrei adds the field, and starts storing it after, with no app change.

201 returns `id, sale, sale_return, amount, method, method_name, reason, issued_by, issued_by_name, authorized_by, authorized_by_name, customer_name, created_at, client_uuid`.

Errors:
- 403 `{"error": "No refund authorization available for this event."}`: wrong password or no permission
- 400 "This sale has already been refunded."
- 400 "Cannot return items on a finalized event."
- DRF field errors

If the caller is the owner or the handler, their own password must match. Otherwise the server tries the password against the owners and that bazaar's handler and records the match as `authorized_by`. `issued_by` is always the logged-in user.

### List refunds

`GET event/<pk>/refund/`. Join to sales by `sale` id.

### Refund handler

- `GET event/<pk>/refund-authorization/` (owner/admin): active means `revoked_at` is null
- `POST event/<pk>/refund-authorization/<auth_pk>/revoke/` (owner/admin)
- Grant (backend `ef7f3ef`, Oct 13): `POST event/<pk>/refund-authorization/` with `{"user_id": id}` (owner/admin). Returns 201 with the authorization, or 400 if the user isn't in the vendor, isn't assigned to the bazaar, or another handler is active. The old two-call RA flow still works but is no longer needed.
- Sale JSON now carries `refund`: null or `{id, amount, created_at}` (backend `b9fda6b`).
- The server now always returns the item and ignores `return_item`. It rejects a refund on a sale already Returned with 400 "Sale is already marked returned."
- The server now auto-revokes a handler when their bazaar assignment is deleted.

Wrap these as `grantRefundHandler`, `revokeRefundHandler`, `currentHandler`, `changeHandler` in `RefundRepository`.

## Phases

### Phase 1: data layer
- `Refund` model, `refund_api_mapper.dart` (read `reference` if present)
- `SalesRepository` also loads `event/<id>/refund/` and exposes `listRefunds()`
- `RefundRepository` wired in `app.dart`, null without a backend
- `approval_api_mapper.dart`: RA and RF are never SOA, and the repository skips them
- `canRefund(user, event)`: owner true, assigned employee true, admin false, and false when the bazaar is finalized
- Unit tests

### Phase 2: refund button and dialog
- **Button.** Trailing 1:1 icon button right of TOTAL (`Icons.undo_rounded`, "Refund" tooltip and semantics, neutral style). Fixed column width.
  - Shown when `canRefund` is true and the sale has no refund and is not Returned.
  - A refunded sale shows a "Refunded" tag in that slot.
  - Disabled offline, with "Refunds need a connection".
- **Dialog.** Build it from `confirmation_dialog.dart`'s structure. Extend `FloatingLabelTextField` with `onChanged`, `enabled`, `errorText`, `helperText` (defaults unchanged).
  - Sale summary: customer, product, payment method, time, total.
  - Reason (required): chips for Wrong size, Defective, Changed mind, Other. Other opens a short text field. Send `reason` as the chip label, or `Other: <text>`.
  - Refund via: always the sale's original method, shown read-only. Money goes back the way it came in (cash to cash, GCash to GCash), for record keeping and anti-money-laundering practice.
  - Reference number: shown and required when Refund via is not Cash. Labelled with the method's extra-field label (the same one the POS uses, for example "GCash reference no."). Helper text: "Reference of the money sent back to the customer."
  - Line: "The item goes back to this bazaar's stock."
  - Password field labelled "Owner or refund handler password", helper "Ask the owner or this bazaar's refund handler to enter their password."
  - Buttons: Cancel, and "Refund PHP <total>" in the destructive color, disabled until the reason and password (and reference, when needed) are filled.
- **Behavior.**
  - One `client_uuid` per dialog open.
  - Loading state.
  - On 403, clear the password and show "That password can't approve refunds at this bazaar."
  - On success, close, name the approver (`authorized_by_name`) in the confirmation, then reload.

### Phase 3: refund handler picker
- A "Refund handler" single-select under the assigned staff in the Preparations bazaar details step and in `BazaarInfoDialog`. Options: None plus assigned employees. Owner and admin only. Employees don't see it.
- In Preparations, grant after `createEvent` and `assignEmployeesToBazaar` succeed.
- Revoke when the handler is removed from the bazaar (the edit-bazaar save loop in `pos_screen.dart`). Removing the chosen employee in Preparations clears the pick.

### Phase 4: records
- **Refund rows** are their own rows: `created_at` time, negative amount, status "Refunded", refund method, approver name. They carry the original sale's `soldById`, so `visibleRecords` stays unchanged.
- **Orders screen:** refund rows sort by time. The total shows as `-PHP x` in the error color.
- **Dashboard Recent Orders:** refund rows with a negative amount and "Refunded".
- **Orders workbook:** the refund line goes on the sheet of the refund method, which is always the original sale's method, with negative unit price and total, status "Refunded", and the reference in the reference column.
- **Revenue rule** as agreed above. A test pins that refund rows never reach a sum.

### Phase 5: refund receipt
- After a successful refund, offer the same save and share flow as sale receipts (PNG via `RepaintBoundary`).
- Title "REFUND". Show customer, product, original sale time and method, refund amount as negative, refund method and reference, reason, and approver name.

### Phase 6: offline approval with a cached password hash (blocked, do not start)

Starts after two things:
- Amrei ships the backend items marked "offline" in `BACKEND_REQUEST_refunds.md`.
- The unsent queue survives an app restart (local persistence). This is separate work.

Design:
- **Caching.** When the owner or any employee logs in on this tablet while online, and whenever an online refund succeeds, cache a verifier for the person whose password the server just accepted. On refund success that person is `authorized_by`.
  - Verifier: PBKDF2-HMAC-SHA256 with a random 16-byte salt. Tune iterations so one check takes about 300 to 500 ms on the Xiaomi Pad 6.
  - Store `{userId, salt, iterations, hash, cachedAt}` in `flutter_secure_storage`.
  - Never store the password.
- **Who counts offline.** The owner, and the bazaar's handler as last fetched from the server (cached per bazaar).
- **Offline refund.** Hash the typed password with each candidate's salt and compare. On a match, save the refund locally with `authorized_by` and `authorized_at`, return the item to local stock, show the row, and queue it.
- **Lockout.** 5 wrong tries blocks refunds for 5 minutes. Persist the counter.
- **Expiry.** Delete a verifier when every bazaar it served has ended or been finalized, on explicit "remove offline access", or when the server reports a newer `password_changed_at` for that user.
- **Sync.** Sales first, then refunds. A refund for an offline sale uses `sale_client_uuid`. A refund the server rejects stays visible as "Refund rejected by server" and notifies the owner, because the cash already went out.
- **Limits to document:**
  - A handler change made while offline reaches the tablet only on the next sync.
  - A stolen tablet with extracted storage could be attacked offline. This is mitigated by the slow hash, encrypted storage, lockout, expiry and a minimum password length.

## Tests each phase

Run `flutter analyze` and `flutter test`. Unit tests for new logic, widget tests for dialog states. List manual macOS steps for `USE_BACKEND=true`, and say when a step needs the tablet.
