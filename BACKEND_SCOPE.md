# SyncBazaar — Backend Scope

Which features move to the server, which stay in Flutter, and what each side owns.
Companion to `BACKEND_READINESS.md`, which covers whether the *client* is ready to connect.

All paths are relative to `syncbazaar/`.

---

## 1. Where things stand

There is no backend.

- No `http`, `dio`, `firebase_*`, `supabase`, or database client in `pubspec.yaml`. Only
  `shared_preferences`.
- `lib/data/remote/api_service.dart` is a 20-line stub — both methods `await Future.delayed(...)`
  and return. The endpoints exist only as comments.
- `lib/services/sync_service.dart` counts unsynced records, calls that stub, waits 600 ms, then
  reports "Sync completed." **Success is reported for an operation that never leaves the device.**
- Every repository in `lib/data/repositories/` is an in-memory Dart collection, rebuilt on each
  launch (`lib/app.dart:80-86`).

**Every sale, order, and approval is lost when the app closes.** Only the login session and one
settings string survive, via `shared_preferences`.

**Deployment context:** production is an **Android tablet used as a till at bazaars**, where network
is unreliable or absent. Anything on the path to completing a sale must work offline.

---

## 2. The rule

> **If two tablets did this at the same time, would they disagree?**
> Yes → backend. No → frontend.

Second test: **would it be bad if this vanished when the app closes?** If yes it needs a server
database. `shared_preferences` is not one.

---

## 3. Must be backend

Each of these is broken today, not merely unpolished.

| # | Feature | Current location | Why it must move |
|---|---|---|---|
| 3.1 | Auth, users, roles | `data/repositories/auth_repository.dart:12-60` | Six users hardcoded with **plaintext passwords** (`123456`, `missy123`). Anyone decompiling the APK reads them. Roles are enforced **only in the UI** — a modified client ignores every restriction. |
| 3.2 | Stock quantities | `product_repository.dart:383-441` | Overselling race — see below. |
| 3.3 | Sales & orders | `sales_repository.dart`, `orders_repository.dart` | `final List<Sale> _sales = []`. The core business records, destroyed on restart. |
| 3.4 | Receipt numbers & IDs | `pos_cubit.dart:589` | `SB-260810-144233` comes from the device clock to the second — two tablets selling in the same second collide. Other IDs use `microsecondsSinceEpoch`, same flaw. |
| 3.5 | Approvals | `approvals_repository.dart` | An employee requests, an owner approves — different devices. In memory, the request never reaches the approver. **Cannot work at all today.** |
| 3.6 | Post-bazaar finalization | `post_bazaar_screen.dart:890-906` | Three mutations with no transaction — see below. |
| 3.7 | SOA generation | `post_bazaar_screen.dart:698-712` | "Generate Draft SOA" currently only shows a snackbar. It is unbuilt, and a statement of account is a financial record — build it server-side, not in the widget. |

### 3.2 The overselling race — the strongest argument for a server

`reserveForSale` reads, checks, then writes:

```dart
final current = _stockByAllocationKey[key];
if (current == null || quantity <= 0 || current < quantity) return false;
_stockByAllocationKey[key] = current - quantity;
```

Correct on one device. With **two tablets at one stall**, both read "1 left", both pass the check,
both complete the sale — the stall sells stock it does not have. No client-side code fixes this.

**Backend owns:** stock levels, and a reservation endpoint that decrements **inside a transaction**
and rejects the loser.

### 3.6 Finalization needs one atomic endpoint

Finalizing a bazaar runs three sequential mutations from a button handler:

```dart
await productRepository.adjustStocksByAllocationKey(allocations); // release stock
await eventRepository.clearAllocationsForEvent(event.id);
await eventRepository.finalizeEvent(event.id);
```

If step 2 fails after step 1 succeeds, stock is released but the allocation still exists — the same
stock is counted twice. In memory this never fails. Over a network it will.

**Backend owns:** one `POST /events/:id/finalize` that does all three in a transaction.

---

## 4. Should be backend

Shared state every tablet must agree on.

| Feature | Current location | Why |
|---|---|---|
| Bazaar events + allocations | `event_repository.dart` | Shared across staff; today each tablet has its own list |
| Event status | `_statusFor()`, same file, line 12 | Computed from `DateTime.now()` — a wrong tablet date shows a wrong status |
| Staff assigned to events | `assignEmployeesToBazaar()` in `auth_repository.dart` | An owner's assignment must reach the employee's device |
| Companies / venues | `settings_repository.dart` | Printed on receipts; must match everywhere |
| Payment methods | same | Per-event config all cashiers share |
| Store name | one `shared_preferences` key | Same reason |
| Notifications | `services/notification_service.dart` | Only meaningful cross-device ("your request was approved") |

**Analytics is a split.** `services/dashboard_analytics_service.dart` is sound arithmetic, but it
only sees sales in memory on *that tablet*. Backend returns the aggregates; frontend keeps
`AnalyticsMetric` formatting and the charts.

---

## 5. Stays on the frontend

Receipt rendering and saving · receipt layout (`receipt_payment_sections.dart`) · cart state before
checkout · all screens, navigation, theme, formatters · image picking and compression · the offline
queue.

### Why receipt rendering must not move

1. **A backend cannot render Flutter widgets.** The receipt *is* a widget captured to PNG. Moving it
   means rewriting it as HTML/PDF and discarding `receipt_document.dart` plus the texture-limit
   handling in `receipt_service.dart:77-95`.
2. **This already broke once here.** `receipt_service.dart:46-49` records a real bug: a network font
   fetch threw on an offline tablet and killed printing — a sale completed and printed nothing. The
   comment concludes *"A till must not depend on the network to hand over a receipt."*

> **The backend stores the receipt record. The tablet draws the picture.**

Four test files cover this (`test/receipt_*.dart`) and should keep passing untouched.

---

## 6. Offline — the decision that sets project size

Pattern: **write locally → queue → upload when online.** The `synced` flags on `Sale`, `Order`, and
`ApprovalRequest` exist for this.

- **Frontend owns:** local persistence, queue, retry, sync status in the UI.
- **Backend owns:** an **idempotent** batch upload — a retried sale must not be recorded twice. This
  requires **client-generated UUIDs**, replacing `microsecondsSinceEpoch`. Agree before the first
  endpoint; painful to retrofit.

### The local database does not exist

Easy to miss, because it sits on the *client* side of a server document.

There is no `sqflite`, `drift`, `hive`, or `isar` in `pubspec.yaml`. All state is in RAM.
`shared_preferences` is a key-value store for preferences, not a database.

So offline-first needs **three** pieces, not two:

| Piece | Status | Owner |
|---|---|---|
| Server + database | To build | Backend |
| **Local database on the tablet** | **Does not exist** | **Frontend** |
| Sync layer | Stub only | Both |

### The fork

| Approach | Client adds | Trade-off |
|---|---|---|
| **Online-only** | HTTP, JSON, error states | ~Half the work. **The till cannot sell without signal.** |
| **Offline-first** | The above **+ local DB + sync queue** | ~Double. Preserves today's behaviour. |

The codebase already chose offline-first twice in writing (`receipt_service.dart:49`, and the
`synced` flags). Choosing online-only as a deliberate first step is fine — **drifting into it is
not.**

---

## 7. Migration order

`BACKEND_READINESS.md` measured ~50 calls per inventory load (N+1). The aggregate endpoint must be
designed **before** any client HTTP code.

1. **Auth** — smallest surface, removes the plaintext passwords.
2. **Products + stock** — fixes overselling. Needs `GET /api/products?expand=variants,stock`.
3. **Sales + orders + receipt records** — with UUIDs and idempotent upload.
4. **Approvals**, then **finalization + SOA**.
5. **Events, settings, notifications, reports.**

---

## 8. Frontend work this implies

| # | Task | Size | Detail |
|---|---|---|---|
| 1 | `toJson`/`fromJson` on 8 models | Small | Only `models/user.dart` has them. Mechanical except §8.1. |
| 2 | Add `http` or `dio` | Trivial | Neither is in `pubspec.yaml`. |
| 3 | Repository interfaces | Small | 7 repos → `abstract class`, rename existing to `InMemoryX`. |
| 4 | UUIDs replacing `microsecondsSinceEpoch` | Small | Required for idempotency. |
| 5 | **Error + loading states** | **Large — the real work** | See §8.2. |
| 6 | Route 3 screens through cubits | Medium | See §8.3. |
| 7 | Fix the N+1 in `inventory_cubit` | Medium | Blocked on the aggregate endpoint. |
| 8 | Local database + sync queue | Large | Only if offline-first. |

### 8.1 Product images

`models/product.dart:50` holds `Uint8List? imageBytes` — raw photo bytes. **These cannot go in
JSON:** base64 inflates ~33% and would sit inside every product-list response. They need a
**multipart upload endpoint returning a URL**, which the client stores in `imagePath`. The model's
own comment already anticipates this ("a CDN once there's a backend").

An extra endpoint the backend developer may not have scoped.

### 8.2 Error handling is the largest task

- **Zero `try {` blocks across all 7 repositories.**
- **9 of 12 cubits have no error or loading state**, including the largest — `pos_cubit.dart` (659
  lines) and `dashboard_cubit.dart` (472).

Nothing in the app can currently express *"the request failed"* or *"still loading."* That means new
cubit states plus loading and error UI on every screen that reads data. **The networking is easy;
teaching the UI to tolerate failure is the job.**

### 8.3 Three screens bypass their cubits

Layering is *mostly* clean — but not entirely, and the exceptions are the screens that most need
care:

| Screen | Direct repository calls |
|---|---|
| `post_bazaar_screen.dart` (1138 lines) | 7 |
| `pre_bazaar_screen.dart` (716 lines) | 4 |
| `pos_screen.dart` | 1 |

These read repositories straight from `context.read<XRepository>()` inside widgets, so they have
nowhere to put a loading or error state. Route them through cubits **before** wiring them to HTTP,
or the error handling in §8.2 has no home in exactly the screens that run finalization and stock
allocation.

Everywhere else the layering is correct and already `async`, so swapping in REST touches no other
screen.

---

## 9. Decide before coding

**Blocking**

- [ ] **Offline-first or online-only?** (§6) Sets the size of everything. *Frontend decides, jointly
      confirmed — it changes what the API must support.*
- [ ] **How do product images upload?** (§8.1) Multipart URL or base64? *Joint.*
- [ ] **Aggregate products/stock response shape** — blocks the N+1 fix. *Backend leads.*
- [ ] **Wire field naming** — snake_case ↔ camelCase? Trivial now, painful later.
- [ ] **UUIDs and the idempotency key** (§6).

**Soon, not blocking**

- [ ] Token lifetime — what happens to a tablet offline for six hours mid-bazaar?
- [ ] Conflict rule when a queued offline sale arrives for stock already sold out.

**Deferrable**

- [ ] Receipt numbers global, or sequenced per event?
- [ ] Does `allocationKey` (`"$productId:$optionIdA:$optionIdB"`, `product_repository.dart:107`)
      stay the wire format, or does the server model variants relationally? Decide before step 2.

---

## 10. How to verify

- **Overselling:** two clients reserve the last unit at once → exactly one succeeds.
- **Finalization:** kill the server mid-finalize → stock and allocations stay consistent.
- **Offline:** airplane mode → sell → receipt still prints → reconnect → sale appears **once**.
- **Roles:** owner-only endpoint with an employee token → rejected **by the server**.
- **Persistence:** sell → force-quit → relaunch → the sale is still there.
- **Regression:** the four receipt test files pass unchanged.
