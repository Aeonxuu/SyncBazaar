# Refund backend: requests for Amrei

Checked against `syncbazaar_backend` at `ee9a1f1` (Oct 13). Done items are marked. Agreed with Lala: refunds approved by the owner's or the bazaar handler's password, online now, offline later through a password hash cached on the tablet.

## Fixes (safety)

1. **DONE (2ac6c12).** **RA requests accept any `user_id`.** Validate that the user is an employee assigned to that bazaar and the same vendor.
2. **DONE (2ac6c12, signal on EventAssignment delete).** **Removing an employee from a bazaar leaves their refund authorization active.** Revoke it when the `EventAssignment` is deleted. `_resolve_authorizer` still accepts that person's password otherwise.
3. **DONE (ef7f3ef).** **Every refund returns the item.** Make `return_item` required and true, or drop it and always return. A refund without a return leaves `order_status` at `CM`, so the sale still counts as revenue.
4. **Retry returns the original.** A repeated `client_uuid` should return the existing refund with 200, not 400 "already refunded".

## Needed now

5. **Reference number on Refund.** Add `reference` (nullable, like the payment's required information) for the GCash or bank send-back reference. The app already sends it.

## Needed for offline refunds

6. **Handler visible to the bazaar's staff.** Let users assigned to a bazaar read its active handler: `user_id` and `name`. Include `password_changed_at` for the vendor's owners and that handler, so the tablet can drop a stale cached hash. This needs a `password_changed_at` field on User, set by the four password-change endpoints.
7. **Accept refunds approved offline.** Accept `authorized_by` (user id) and `authorized_at` (timestamp) with no password. Accept only if that user was an owner, or that bazaar's handler with no revocation before `authorized_at`.
8. **Refund an offline sale.** Accept `sale_client_uuid` in place of `sale_pk`. A `POST event/<pk>/refund/` taking either would work.
9. **Minimum password length.** At least 10 characters, at least for owners and handlers. The cached hash on the tablet is only as strong as the password.

## Would make the app simpler

10. **DONE (ef7f3ef).** **Direct grant.** `POST event/<pk>/refund-authorization/` with `{"user_id"}` for owner/admin, in place of the two-call RA request and approve.
11. **DONE (f4e458e). Note: list-of-orders JSON key `sales` is now `transactions`.** **Refunds in server reports.**
    - `ListOfOrdersApiView` (CSV and JSON): refund rows with a negative amount and status "Refunded".
    - `DashboardApiView.transaction_history`: refund rows.
12. **DONE (b9fda6b).** **Refund info on Sale JSON.** A nullable `refund` object (`id, amount, created_at`) on `SaleSerializer`.

## Still open

- 4 (retry returns the original refund), 5 (reference number on Refund), and 6 to 9 (offline refunds).
- The grantee now gets a server notification, but the app does not read server notifications yet.

## To confirm

- One refund handler per bazaar is intended.
- The app always sends the full sale total. No partial refunds.
- Admins can assign the handler but cannot refund. That matches the current code.
- The app shows the refund button to the owner and all assigned employees and relies on `_resolve_authorizer` to accept only the owner's or that bazaar's handler's password. Please keep that behavior.
- No refunds after finalizing. The server already blocks returns on finalized bazaars.
