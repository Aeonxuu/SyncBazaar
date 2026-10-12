# Refund backend: requests for Amrei

Checked against `syncbazaar_backend` at `447d9a2` (Oct 1).

## Needed before the app can ship refunds

1. **RA requests accept any `user_id`.** `ApprovalRequestSerializer` checks that `user_id` exists in `details_json` but not that the user is an employee assigned to that bazaar (or even the same vendor). Please validate it.
2. **Removing an employee from a bazaar leaves their refund authorization active.** `_resolve_authorizer` still accepts that person's password as a supervisor override for other staff. Please revoke the authorization when the `EventAssignment` is deleted.

## Would make the app simpler

3. **Direct grant endpoint.** Right now granting is two calls (create an RA approval request, then PATCH it to approved). A `POST event/<pk>/refund-authorization/` with `{"user_id"}` for owner/admin would replace that.
4. **Refunds in server reports.**
   - `ListOfOrdersApiView` (CSV and JSON): add refund rows with a negative amount and status "Refunded".
   - `DashboardApiView`: add refund rows to `transaction_history`.
   - A refund must always return the item. Please make `return_item` required and true (or drop the field and always return). A refund without a return leaves `order_status` at `CM`, so the sale still counts as revenue.
5. **Refund info on Sale JSON.** A nullable `refund` object (`id, amount, created_at`) on `SaleSerializer` would save the app a second request per bazaar.

## Offline refunds with a refund PIN (new, agreed with Lala)

The booth is often offline, and the login password can't be checked without the server. Putting anything made from the login password on the tablet would let someone who steals it crack the account offline. So refunds get a separate 6-digit refund PIN that only approves refunds.

6. **Refund PIN on the user.** Add `refund_pin_hash`. Store it with `make_password`, using a PBKDF2 hasher with a lower iteration count than login passwords, so a tablet can check one PIN in under a second (Lala will measure on the Xiaomi Pad 6). Endpoint: `POST /api/auth/refund-pin/` with `{password, pin}`. Requires the login password. PIN is exactly 6 digits.
7. **Verifier download.** `GET event/<pk>/refund-verifiers/` for the owner and users assigned to the bazaar. Returns `[{user_id, name, role, pin_hash}]` for the vendor's owners and the bazaar's active refund handler, only those who have set a PIN. `pin_hash` in Django's encoded format (`pbkdf2_sha256$iterations$salt$hash`) so the app can verify with the same algorithm.
8. **Refund endpoint changes.**
   - Online: accept `authorizer_pin` in place of `authorizer_password`, checked the same way `_resolve_authorizer` checks passwords now. Please rate-limit wrong PINs per user.
   - Offline sync: accept `authorized_by` (user id) and `authorized_at` (timestamp) with no PIN. Accept it only if that user was an owner, or the bazaar's handler with no revocation before `authorized_at`.
   - Accept `sale_client_uuid` as an alternative to `sale_pk`, for refunds of sales made offline. A new `POST event/<pk>/refund/` taking either would work.
   - A repeated `client_uuid` should return the existing refund with 200, not 400 "already refunded". The app retries after lost responses.
9. **Optional, stronger.** The offline path trusts the tablet's claim of who approved. If there's time: the tablet sends an HMAC of the refund data keyed by a second hash of the PIN that is never stored on the tablet, and the server, which stores that second hash, checks it. That proves the PIN was typed. Fine to leave for after the capstone and list as a limitation.

## To confirm

- One refund handler per bazaar is intended?
- Refund amount: the app will always send the full sale total for now (no partial refunds). OK on your side?
- The app shows the refund button to the owner and every employee assigned to the bazaar, and relies on `_resolve_authorizer` to accept only the owner's or that bazaar's handler's password. Please keep that behavior.
- Admins can assign the refund handler but cannot refund. That matches the current code, so no change needed.
