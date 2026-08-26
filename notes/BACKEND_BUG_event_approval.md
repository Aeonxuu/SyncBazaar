# Bug: every new bazaar is forced to "needs approval", including owners' and admins'

**Where:** `bazaars/views.py`, `perform_create`, line 76
**Impact:** high. Causes lost sales, not just a cosmetic problem.
**Found:** 2026-08-26, testing against `syncbazaar-backend.onrender.com`

## What happens

```python
def perform_create(self, serializer):
    vendor = self.request.user.vendor_assignment.vendor
    event = serializer.save(vendor=vendor, is_approved=False)   # <-- always False

    ApprovalRequest.objects.create(
        event=event,
        requester=self.request.user,
        request_type=ApprovalRequest.REQUEST_TYPE_EVENT_CREATION,
        details_json={},
    )
```

`is_approved=False` is hardcoded, so whatever the client sends in the request body is
discarded. Every bazaar becomes a pending proposal regardless of who created it, and an
`ApprovalRequest` is raised even when there is nobody above the creator to approve it.

The Flutter client does send the field. `POST /api/bazaar/event/` from an owner includes
`"is_approved": true`, and it is ignored.

## Why it matters

Reproduced end to end today. An owner created a bazaar named "Cyberlympics":

1. Client sent `is_approved: true` and got a `201` back.
2. Client treated it as live, listed it, and **rang up real sales against it**.
3. Server had it as `is_approved: False`.
4. On the next reload the client filtered it out, and the bazaar plus its sales disappeared
   from the UI.

Confirmed still on the server, unapproved:

```
GET /api/bazaar/event/
  ... 12 approved bazaars ...
  - Cyberlympics   2026-08-26 -> 2026-08-29   is_approved: False
```

So the two sides disagreed about whether a bazaar existed, and stock was sold from a stall
that the server considered a proposal. That is the dangerous part: it is silent, and it is
sales data.

## Suggested fix

Honour the requester's role, which is what the client already assumes:

```python
def perform_create(self, serializer):
    user = self.request.user
    vendor = user.vendor_assignment.vendor

    # An owner or admin creating a bazaar has nobody to ask, so it goes live
    # immediately. An employee's is a proposal and needs a request raised.
    role = user.vendor_assignment.role          # adjust to however role is stored
    can_self_approve = role in ('owner', 'admin')

    event = serializer.save(vendor=vendor, is_approved=can_self_approve)

    if not can_self_approve:
        ApprovalRequest.objects.create(
            event=event,
            requester=user,
            request_type=ApprovalRequest.REQUEST_TYPE_EVENT_CREATION,
            details_json={},
        )
```

Please don't take `is_approved` straight from the request body: an employee could then
approve their own bazaar by sending `true`. Deciding it server-side from the role is both
the safe option and what the client expects.

## Second issue in the same method: duplicate approval requests

`perform_create` raises an `ApprovalRequest` itself, but the Flutter client already raises
its own when an employee proposes a bazaar, and that one carries the actual stock
allocations in `details_json`. The server's is empty (`{}`).

So once the role fix lands, an employee proposing a bazaar produces **two** pending
requests for the same event:

| Raised by | request_type | details_json | Useful? |
| --- | --- | --- | --- |
| Client | `ST` | the allocations | yes, this is the one an owner needs |
| Server | `EC` | `{}` | no, an empty duplicate |

Suggest dropping the `ApprovalRequest.objects.create(...)` from `perform_create` entirely
and letting the client raise it, since only the client knows the allocations being
proposed. If you would rather the server own it, say so and we will remove it from the
client instead. Either is fine, but not both.

Confirmed on the live server, the one request against Cyberlympics (event 13) is the
server's empty `EC`:

```json
{"id":1,"request_type":"EC","status":"PD","details_json":{},"event":13,"requester":2}
```

## Worth checking too

- `ApprovalRequest` rows already created for owner/admin bazaars are orphaned. There may be
  some in the database from testing, including Cyberlympics.
- `bazaars/tests.py` has no case covering "owner creates a bazaar, it is live immediately".
  That is the test that would have caught this.

## Client side

No change needed, and none is being asked for. The client already sends the right value.
It has been made stricter in one way: it now reads `is_approved` back from the create
response and believes the server rather than its own request, so a bazaar the server
considers unapproved can no longer be sold against locally. That closes the lost-sales
path from this side, but the bazaar still will not go live until the above is fixed.
