# SyncBazaar — Backend Readiness Assessment

**Date:** 2026-08-02
**Question:** Is this project ready to be connected to backend APIs using a REST framework?
**Verdict:** **Not yet — but the expensive part is already right.**

The app's layering is sound, so connecting it to a real backend will not require rewriting screens. What's missing is everything that makes a call **fallible and slow** rather than instant and infallible. The gap is concentrated in five areas, and the riskiest of them is the *data contract*, not the HTTP plumbing.

---

## 1. How this was assessed

Every claim below is grounded in the code as it stands on the date above, not in impression. The checks used:

| Check | Command |
| --- | --- |
| Serialization coverage | `grep -rln "toJson\|fromJson" lib/models/` |
| Repository abstraction | `grep -rn "^abstract class\|implements .*Repository" lib/` |
| Failure handling | `grep -rn "throw \|Exception\|try {" lib/data/repositories/` |
| Client-generated IDs | `grep -rn "_next[A-Za-z]*Id = \|millisecondsSinceEpoch" lib/` |
| Per-load call count | `grep -n "await _productRepository\." lib/bloc/inventory/inventory_cubit.dart` |
| Error state in cubits | `grep -rln "String? error" lib/bloc/` |

Re-run these after any refactor to see whether an item below has actually been closed.

---

## 2. What is already in good shape

These are real assets. Do not undo them while wiring up the backend.

- **Correct layering.** No screen touches data directly. Every path is UI → Cubit → Repository, with repositories injected via `MultiRepositoryProvider` in `syncbazaar/lib/app.dart`. This is the single most expensive thing to get wrong, and it is right.
- **Async signatures throughout.** Every repository method already returns a `Future`, and cubits already `await` them. Call sites will not need restructuring when those futures start taking 100 ms instead of 0 ms.
- **Mutations already refresh state.** Every write is followed by `await load()`. The pattern is correct for REST even though its current granularity is wrong (see Blocker 1).
- **Intent already scaffolded.** `lib/data/remote/api_service.dart` and `lib/services/sync_service.dart` sketch the shape of the eventual integration, including a list of the intended endpoints.

---

## 3. Blockers

### Blocker 1 — N+1 request explosion (highest impact)

**Evidence:** `InventoryCubit.load()` (`syncbazaar/lib/bloc/inventory/inventory_cubit.dart`) issues, per product:

1. `variantGroupsForProduct(product.id)`
2. `variantOptionsForGroup(groups[0].id)`
3. `variantOptionsForGroup(groups[1].id)`
4. `combinationStocksForProduct(product.id)`

Plus two top-level calls (`listProducts`, `archivedAllocationKeys`).

With the current mock dataset — 12 products, each with a Color and a Size group — that is exactly **50 calls per load**.

**Why it is invisible today:** they are in-memory `Map` lookups that resolve in microseconds.

**Impact over REST:** at 100 ms latency, ~5 seconds per load. Worse, because every mutation ends in `await load()`, **archiving a single SKU would refetch the entire inventory.** The same applies to `deleteMany`, `setArchivedForKeys`, and `saveProduct`.

**What is needed:** an aggregate endpoint that returns products with their variants and per-combination stock nested in one response, e.g.

```
GET /api/products?expand=variants,stock
```

and a reshaped `load()` that consumes it. Ideally also targeted mutations that return the updated rows, so the UI can patch state instead of refetching everything.

> This will not emerge from "just add HTTP calls" — it is a change to the shape of the data layer and should be designed before any client code is written.

---

### Blocker 2 — No serialization layer

**Evidence:** only `syncbazaar/lib/models/user.dart` has any JSON handling. The following have none:

`approval_request.dart` · `bazaar_event.dart` · `company.dart` · `notification.dart` · `order.dart` · `product.dart` · `product_variant.dart` · `sale.dart`

**What is needed:** `fromJson` / `toJson` on every model, plus an agreed field-naming convention (snake_case on the wire ↔ camelCase in Dart). Decide whether to hand-write these or adopt code generation (`json_serializable`) before writing the first one — mixing approaches later is worse than either.

---

### Blocker 3 — Client-generated IDs

**Evidence:**

| Location | Code |
| --- | --- |
| `product_repository.dart:72` | `int _nextProductId = 1000;` |
| `product_repository.dart:73` | `int _nextVariantGroupId = 5000;` |
| `product_repository.dart:74` | `int _nextVariantOptionId = 9000;` |
| `settings_repository.dart:14` | `int _nextCompanyId = 1;` |
| `pre_bazaar_screen.dart:322` | `eventId: DateTime.now().millisecondsSinceEpoch` |

**Impact:** a server assigns identities. Every place the client invents an ID and then immediately uses it as a key must instead wait for the server's response and use what comes back. This is straightforward on its own, but it compounds badly with Blocker 4.

---

### Blocker 4 — `allocationKey` is an invented client-side composite

**Evidence:** `product_repository.dart:105`

```dart
String allocationKey(int productId, {int? optionIdA, int? optionIdB}) {
  return '$productId:${optionIdA ?? 0}:${optionIdB ?? 0}';
}
```

This string is **the most load-bearing concept the client made up.** It is used as:

- the primary key for all stock (`_stockByAllocationKey`)
- the key set for individually archived SKUs (`_archivedAllocationKeys`)
- the key for per-event allocations (`Event.allocations`)
- an embedded field inside the approval payload JSON sent to Approvals
- a parseable value — `productIdFromKey()` splits it back apart, and `pos_cubit.dart` does `int.tryParse(entry.key.split(':').first)`

**What is needed — decide this with the backend team first:**

- **Option A:** the server adopts the same composite key format. Cheapest for the client; couples the server to a client-side encoding.
- **Option B:** the server exposes a real `variant_id` per sellable combination. Cleaner and more conventional, but every one of the usages above has to be migrated, including the persisted approval payloads.

Option B is the better long-term design. Either way, **this decision determines the shape of a large amount of client code and should be made before anything else is built.**

---

### Blocker 5 — Nothing can fail

**Evidence:** across all seven files in `lib/data/repositories/`, there are **zero** occurrences of `throw`, `try`, or `Exception`. Every method signature asserts "this always succeeds." Only `AuthState` carries an `error` field; `InventoryState` has `isLoading` but nowhere to record a failure, and no screen renders one.

**Impact:** over a network, every call can time out, 401, 500, or fail offline. Today there is no place to put that information and no UI to surface it. This touches every cubit and most screens.

**What is needed:**

1. A failure representation at the repository boundary — either typed exceptions or a `Result`/`Either` type. Pick one and use it everywhere.
2. An `error` field on each cubit state alongside the existing `isLoading`.
3. One reusable error surface in the UI (inline banner and/or retry affordance), so failure handling does not get reinvented per screen.

---

## 4. Secondary gaps

Not blockers, but cheap now and painful later.

- **No repository interfaces.** All seven are concrete classes constructed directly in `app.dart` (lines 80–86). There is no seam to swap a REST implementation in while keeping the in-memory one for tests and demos. Extract `abstract class ProductRepository` with `InMemoryProductRepository` / `RestProductRepository` implementations. **This is the highest-value task that does not depend on the API contract existing yet.**
- **No auth token handling.** `AuthRepository` returns an `AppUser` with no token attached. `ApiService` has no header injection, no refresh flow, and no 401 interceptor.
- **`SyncService` carries no data.** `syncNow()` currently sends counts, not records:
  ```dart
  final payload = <Map<String, dynamic>>[
    {'sales': unsyncedSales.length},
    ...
  ];
  ```
  It is correctly shaped as a placeholder but transmits nothing usable.

---

## 5. The offline-first question — settle this first

The top bar advertises **"Offline-ready"**, and `SalesRepository.listUnsyncedSales()` / `OrdersRepository.listUnsyncedOrders()` imply an offline-first design was intended.

But as of 2026-08-02 **all state is RAM-only** — restart the app and everything is gone. The only local persistence layer (`lib/data/local/database_helper.dart`, a SQLite schema) was never referenced by anything and was deleted during the same cleanup, along with the `sqflite` and `path` dependencies.

**This needs an explicit decision:**

- **If offline-first is a real requirement**, it is substantially more work than "connect to REST": local persistence, a durable outbound sync queue, and a conflict-resolution policy. Scope it separately and early.
- **If it is aspirational**, say so plainly — and consider softening the "Offline-ready" label so the UI does not claim a capability the app does not have.

---

## 6. Recommended sequence

Ordered by dependency, not by ease.

| # | Task | Depends on |
| --- | --- | --- |
| 1 | **Agree the API contract** — especially variant/stock representation and the fate of `allocationKey` (Blocker 4) | Backend team |
| 2 | Add `fromJson` / `toJson` to all models (Blocker 2) | 1 |
| 3 | Extract repository interfaces; keep in-memory versions as the test/demo implementation | — (start now) |
| 4 | Collapse the N+1 into aggregate endpoints and reshape `load()` (Blocker 1) | 1, 2, 3 |
| 5 | Add `error` to cubit states plus one standard error surface (Blocker 5) | 3 |
| 6 | Auth tokens, headers, refresh, 401 handling | 3 |
| 7 | Sync / offline persistence — **only if actually required** (§5) | 5 |

**Start with 3.** It is the only item that delivers real value without waiting on the backend contract, and it makes everything after it easier to test.

---

## 7. Bottom line

The architecture will not fight you. The boundaries are in the right places, so the screens survive the transition largely untouched.

The real risk sits in **items 1 and 4** — the shape of the data and the number of round trips it takes to get it. Both are design decisions, and both get more expensive the later they are made. The HTTP plumbing itself is the easy part.
