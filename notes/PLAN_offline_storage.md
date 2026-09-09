# Plan: offline storage

**Status:** not started
**Owner:** frontend
**Opened:** 2026-09-09

Keep this file current as the work proceeds. Corrections go in **Changes** at the bottom, with a
date and a reason, rather than being edited into the text above. The point is to be able to see
what was decided originally and what moved, so a session picking this up later is not guessing.

---

## Why

The app is a till for pop-up bazaars, where the network is unreliable or absent. It is not built
for that yet, and one gap loses money.

Two problems, in order of severity:

1. **Unsent sales are held in memory.** `SalesRepository._sales` is a plain Dart list
   (`sales_repository.dart:26`). A sale rung up without signal is marked unsent and queued for
   retry, and that queue exists nowhere else. A crash, a force-close, or Android reclaiming memory
   loses a day of takings with no trace. This is the only defect in the app that destroys real
   money.
2. **Nothing can be sold without a connection at launch.** Products, bazaars and allocations are
   fetched from the API and never written to the device, so opening the app offline shows an empty
   catalogue. Selling works only if the app was already running and loaded.

The retry half of offline-first is already built and is good: every sale carries a `clientUuid`, so
the server recognises a repeat rather than double-counting; `SaleUploadService.uploadPending()`
reports how many are still waiting; and `_loadFromApi` deliberately keeps unsent sales when
refreshing (`sales_repository.dart:106-114`). What is missing underneath it is durability.

## What this is not

- Not a sync engine. The server stays the source of truth and last-write-wins is fine; two tills
  editing the same bazaar is not a scenario this app has.
- Not offline login. `restoreSession()` already works from stored preferences when "remember me"
  was ticked. Signing in for the first time still needs the server, which is acceptable.
- Not caching for speed. This is about working at all, not about being faster.

---

## Storage choice

**`shared_preferences`, one JSON string per collection**, behind a small `LocalStore` class.

The whole seeded dataset is **112 KB** (12 products, 12 bazaars, 244 sales). A day's real trading
is a few hundred sales. That is far below the point where a database earns its keep, and sqflite,
hive or drift would each bring code generation, a migration story, and a separate web
implementation for less data than a single photo.

`shared_preferences` is already a direct dependency, behaves identically on the tablet, macOS and
web, and can be faked in tests with `SharedPreferences.setMockInitialValues({})`, which matters
because most of the risk here is in code paths that are awkward to reach any other way. The app
already stores QR images there at up to 512 KB each, so a 60 KB sales queue is not a new kind of
use.

If sales ever outgrow it, the backend swaps behind `LocalStore` without touching a caller.

**Rejected:** `path_provider` + JSON files. Correct for the job and already a transitive
dependency, but it needs `dart:io`, so it needs a second implementation for web and a temp
directory in every test. Not worth it at this volume.

---

## Phase 1: never lose a sale

The whole data-loss risk, and small enough to land on its own.

**New:** `lib/services/local_store.dart`

```dart
class LocalStore {
  Future<List<Map<String, dynamic>>> readList(String key);
  Future<void> writeList(String key, List<Map<String, dynamic>> rows);
  Future<void> clear(String key);
}
```

JSON in, JSON out, one `shared_preferences` string per key. No models, so it can be tested on its
own and reused by phase 2.

**`Sale` gains `toJson`/`fromJson`.** It has none today. The API mappers convert *server* shapes,
which are not the same thing: the queue must round-trip the client's own fields, `clientUuid` and
`synced` included.

**`SalesRepository`** (`sales_repository.dart`) persists the unsent queue at three existing seams:

| Seam | Line | Change |
| --- | --- | --- |
| `addSale` | 28 | Write the queue after appending. |
| `markSynced` | 137 | Rewrite the queue, minus what the server confirmed. |
| `_loadFromApi` | 106-114 | Already keeps unsent sales on refresh; write after merging. |
| construction | — | Load the queue before first use, so a relaunch resumes it. |

**Ordering rule, and the point of the whole phase:** a sale must be on disk *before* the cashier is
told it completed. `PosCubit.completeSale` writes the sale, then uploads quietly
(`_uploadSalesQuietly`, `pos_cubit.dart:349`), then the screen shows "Sale completed." The write
must be awaited and durable before that message, or the gap between them is exactly where a crash
loses the sale it just claimed to have made.

**Tests**
- A queued sale survives a new `SalesRepository` over the same storage.
- `markSynced` removes only what the server confirmed; the rest stay queued.
- A refresh keeps unsent sales and does not duplicate ones that came back from the server.
- Round-trip: a sale read back equals what was written, `clientUuid` and `synced` included.
- Corrupt or unreadable stored JSON is discarded rather than crashing startup. A till that will
  not open is worse than a lost queue, and the same rule already applies to stored QR codes.

**Done when:** ring up sales with the network off, force-close the app, reopen, and the sales are
still queued and still upload when the signal returns.

---

## Phase 2: cold-start with no network

What makes the app genuinely offline-first rather than offline-tolerant.

**Cache after each successful load, read when the server cannot be reached.** Both repositories
already funnel through a single method, so there is one place to write and one to fall back to:

- `ProductRepository._loadFromApi` (`product_repository.dart:579`) — products and variants
- `EventRepository._loadFromApi` (`event_repository.dart:200`) — bazaars, allocations, stock row
  ids, payment methods

`_ensureLoaded` currently returns early on a cache marker and throws when the API fails. It gains a
third path: on failure, load from `LocalStore` and carry on.

**Stale data must announce itself.** Stock counts move while a device is offline, so the app must
say it is working from a stored copy and when that copy was taken, rather than presenting old
numbers as current. A quiet line in the POS header, not a modal; a cashier cannot act on it and
does not need interrupting.

**Tests**
- A repository with a working API writes a cache.
- A repository whose API fails serves the cache instead of an empty catalogue.
- With no cache and no API, the app reports having nothing rather than crashing.
- The cache records when it was taken, and the app can read that back to display it.

**Done when:** turn the network off, force-close, reopen, and a bazaar can be opened and sold from.

---

## Risks

- **Silent divergence.** A device selling from a stale catalogue can oversell stock the server has
  already given away. Out of scope to solve properly; the mitigation is showing the staleness and
  keeping the cache short-lived in practice.
- **Doing too much at once.** Phase 1 is worth landing and verifying on the tablet on its own.
  Phase 2 touches the load path of both repositories, which is the code everything else depends on.
- **`shared_preferences` write cost.** The whole queue is rewritten per sale. At a few hundred
  sales of roughly 200 bytes this is tens of kilobytes and unmeasurable on a tablet. Worth
  remeasuring if a bazaar ever runs into the thousands.

## Out of scope, tracked elsewhere

- QR codes moving to the server, blocked on
  `notes/BACKEND_BUG_vendor_payment_method_permission.md`.
- `tool/generate_mock_data.py` emitting data that fails its own tests.

---

## Changes

*Nothing yet. Append here as decisions move, with the date and the reason.*
