# Plan: registration and onboarding

**Status:** owner signup dropped; verification done; password management outstanding
**Owner:** frontend, with backend items listed for the backend developer
**Opened:** 2026-09-10

Corrections go in **Changes** at the bottom with a date and a reason, rather than being edited into
the text above, so a later session can see what was decided first and what moved.

---

## What we want

One screen offering **Sign in** or **Create account**, and a first run that ends with a usable app.

**Owner** creates an account, names their store, adds a venue, and invites staff. Adding staff is
skippable, since their people may not exist yet.

**Employee** creates an account and waits to be attached to a store. Until an owner adds them they
have nothing to see, and the app should say so rather than showing an empty till.

---

## What the server already does

Checked against the backend at `github.com/Allie1080/syncbazaar_backend` on 2026-09-10, and against
the live server.

| Capability | Endpoint | State |
| --- | --- | --- |
| Sign in | `POST /api/auth/login/` | Works. Refuses unverified accounts with 403. |
| Verify by emailed code | `POST /api/auth/verify-account/` | Exists, client does not use it |
| Resend that code | `POST /api/auth/resend-verification/` | Exists, client does not use it |
| Change own password | `POST /api/auth/change-password/` | Exists, client does not use it |
| Owner resets a password | `POST /api/auth/<pk>/reset-password/` | Exists, client does not use it |
| **Owner adds an employee** | `POST /api/core/vendor/<id>/employee/` | **Works, and does more than expected** |
| Create a store | `POST /api/core/vendor/` | Works for any signed-in user |
| Create a venue | `POST /api/core/establishment/` | Works |

**The employee half is nearly built already.** `EmployeeCreationSerializer.create` does three things
in one call: creates the user, attaches them to the vendor, and emails them a verification code. So
the intended flow is:

1. Owner adds the employee, choosing their email and an initial password.
2. The employee receives a code and verifies.
3. They sign in, already attached to the store.

That is a complete path, and the client uses none of it.

---

## What is missing

### 1. There is no public registration

`POST /api/user/` is the only way to create a user and it requires an authenticated owner or admin.
Unauthenticated it answers **401**, verified on the live server. So nobody can create their own
account, and the "Create account" half of the screen has nothing to call.

### 2. A new owner cannot set themselves up

Even with registration added, an owner would be stranded. Creating a store works, but nothing
attaches the person to it: `VendorAssignment` has a serializer and **no route**. Without an
assignment, login returns no `vendor_id`, and every screen in the app is scoped by vendor.

### 3. Employees cannot register themselves

Today the owner creates the whole account, password included. The flow described above ("employee
signs up, then waits to be added") is a different model and needs the owner to be able to attach an
account that already exists.

### 4. Worth fixing while in there: vendors are not scoped

`VendorListGenericApiView` and `VendorDetailGenericApiView` declare no `permission_classes`, so they
fall back to `IsAuthenticated` with `queryset = Vendor.objects.all()`. Any signed-in user can list,
edit or delete **any** vendor. Only one vendor exists today so nothing is leaking, but a second
business would see and be able to delete the first.

---

## To ask the backend developer

Forwardable as-is.

> Four things for the sign-up flow, roughly in order of how much they block us.
>
> **1. A public registration endpoint.** Something like `POST /api/auth/register/`, unauthenticated,
> taking name, email, password and role, creating the user unverified and sending the existing
> verification code. We would then use `verify-account/`, which already works.
>
> **2. A way for a new owner to end up attached to a store.** Right now `VendorAssignment` has a
> serializer but no route, so a newly registered owner can create a vendor and still not belong to
> it, and login returns no `vendor_id`. Either an endpoint to create the assignment, or have vendor
> creation attach the creator automatically when they have no assignment yet. The second is fewer
> moving parts and harder to misuse.
>
> **3. A way to attach an employee who already has an account.** `POST /vendor/<id>/employee/`
> creates the user outright, which is good when the owner is setting someone up. If an employee is
> to register themselves first, an owner needs to add an existing account by email, and to be told
> plainly when that email already belongs to another store.
>
> **4. Vendor endpoints are unscoped.** `VendorListGenericApiView` and `VendorDetailGenericApiView`
> have no `permission_classes` and use `Vendor.objects.all()`, so any signed-in user can list, edit
> or delete any vendor. Only one vendor exists so nothing is exposed yet, but it is worth closing
> before there are two.
>
> **5. Venues should belong to a store, not be shared by everyone.** `Establishment` has no vendor
> field, so every stall sees and can edit the same venue rows. That is wrong for two reasons:
> `incentive_percent` and `buffer_percent` are terms negotiated between one stall and one venue, and
> in the real world different stores trade at different places. Right now one stall changing its
> terms changes them for everybody, and any signed-in user can delete a venue another stall's bazaar
> depends on.
>
> What that needs:
>
> - A `vendor` foreign key on `Establishment`, with a migration assigning the three existing rows to
>   vendor 1.
> - The endpoints moved under the vendor, matching the pattern products, employees and payment
>   methods already follow: `/api/core/vendor/<vendor_pk>/establishment/`, scoped to that vendor.
> - `BazaarEventSerializer.establishment` currently accepts `Establishment.objects.all()`, so a
>   bazaar can be attached to another stall's venue. It needs scoping to the requester's vendor too,
>   or the foreign key above can be bypassed on the way in.
>
> Worth saying explicitly: **two stalls both trading at MSEUF Campus should end up with two rows**,
> one each, with their own terms. Duplicate names across vendors are correct here, not something to
> deduplicate.
>
> One question rather than a request: **should owners be able to sign up at all**, or are owner
> accounts something you create? If owner accounts are provisioned, item 2 goes away and public
> registration only has to serve employees, which is a much smaller job.

---

## Testing with real stalls at the English Festival

Several stalls, each a separate business with its own products and takings, on a day when things
have to work. This does **not** need self-registration.

**Create each stall by hand before the day.** Django admin is enabled at `/admin/`, and `User`,
`Vendor` and `VendorAssignment` are all registered, so for each stall:

1. A `Vendor` with the stall's business name.
2. A `User` with role Owner, **with `is_verified` ticked**, so they can sign in straight away
   rather than waiting on an emailed code on the day.
3. A `VendorAssignment` linking that user to that vendor.

Each stall then signs in and sees only their own catalogue, bazaars and sales. Nothing new is
needed server-side for this.

**One thing must be fixed first.** `VendorListGenericApiView` and `VendorDetailGenericApiView`
declare no `permission_classes` and use `Vendor.objects.all()`. With one vendor that is harmless.
With five stalls, **every stall owner can list, rename and delete every other stall**, on a day when
real vendors are recording real sales. Backend item 4 stops being theoretical the moment a second
vendor exists, and should be done before the festival rather than after.

**Venues need to become per-stall too, and that is backend item 5.** They are currently shared:
`Establishment` has no vendor field. That is survivable for this one festival, where every stall
really is at MSEUF Campus, but the terms are not shared even then. `incentive_percent` and
`buffer_percent` are negotiated between one stall and one venue, so one stall editing them changes
every other stall's terms, and any signed-in user can delete a venue another stall's bazaar
depends on.

Ordering for the festival: item 4 (scoping vendors) is the one that must be done. Item 5 can follow,
as long as nobody edits venue terms on the day.

## Client phases

Ordered so each lands something usable, and so the parts that are blocked come last.

### Phase 1: the screen itself — not blocked

Rebuild the auth screen with **Sign in** and **Create account**, with only sign-in working. The
register side collects details and explains that accounts are currently created by the store owner.

Worth doing first because the current screen has no room for a second path, and every later phase
needs somewhere to put it.

- Sign in / Create account as two paths on one screen
- Role chosen on the register side: **I own a store** or **I work at a store**
- Password rules and a visible strength requirement, since a till account guards real takings
- Keeps the existing "Account not verified" message, which already works

### Phase 2: verification — not blocked

Everything for this exists server-side and the client uses none of it.

- After an owner adds an employee, that person needs a code screen: enter the emailed code, or
  resend it
- Reached from sign-in when login answers 403 unverified, which is exactly when it is needed
- Uses `verify-account/` and `resend-verification/`

This alone fixes a live gap: **an employee added today cannot sign in**, because accounts are
created unverified and the app offers no way to verify.

### Phase 3: owner onboarding — blocked on backend items 1 and 2

First run for a new owner, as a short sequence that can be left and resumed:

1. Name the store
2. Add a venue, or skip
3. Invite staff, or skip

Skipping must be genuinely skippable. A stall run by one person has no staff to add, and an
onboarding that insists is one people abandon.

### Phase 4: employee onboarding — blocked on backend item 3

A signed-in employee with no store sees a plain waiting screen naming the email their owner needs,
rather than an empty till that looks broken.

### Phase 5: account management — not blocked

- Change your own password (`change-password/`)
- Owner resets an employee's password (`<pk>/reset-password/`)

Both endpoints exist and neither is used.

---

## Decisions to make first

- **Should owners be able to self-register?** If owner accounts are provisioned by you or by an
  administrator, phase 3 and backend item 2 both disappear.
- **Who sets an employee's first password?** The owner, as today, or the employee at registration.
  This decides whether backend item 3 is needed at all.
- **Is email actually reaching people?** The verification code is emailed, and the whole flow rests
  on that arriving. Worth confirming a real message lands before building screens that wait for one.

## Risks

- **Phases 3 and 4 are blocked**, so this cannot be finished in one go. Phases 1, 2 and 5 are worth
  landing on their own.
- **Verification is a hard gate.** Login refuses an unverified account, so anything that creates
  accounts without a working code screen creates accounts nobody can use.
- **Onboarding is where people give up.** Every required step loses someone. Only the store name is
  genuinely required; everything else should be skippable and reachable later from Settings.

---

## Changes

**2026-09-10 — Owners will be provisioned, not self-registered.** Decided with the user. Backend
items 1, 2 and 3 are dropped: no public signup endpoint, no self-attaching owner, and no way to
attach an existing employee, because owners already create employee accounts outright through
`POST /vendor/<id>/employee/`, which the app has always used. Phases 1, 3 and 4 go with them.
Remaining backend work is item 4 (scope the vendor endpoints, before the festival) and item 5
(venues per store).

**2026-09-10 — Verification built.** Phase 2 done. Sign-in offers "Enter the code from your email"
when the server refuses an unverified account, and signs the person in once confirmed rather than
returning them to a form they have to submit again. This closed a live gap: every employee an owner
added was unverified, sign-in refuses unverified accounts, and the app offered nothing to do about
it.

The dialog says the code expires in ten minutes before it is needed rather than after it fails,
and keeps the server's own wording, since "invalid" and "expired" call for different actions.

**2026-09-10 — Venues become per-store.** Added as backend item 5 at the user's direction. The
original note recorded shared venues as intended; that was wrong about the terms. Incentive and
buffer percentages are negotiated per stall, and different stores trade at different places, so
`Establishment` needs a vendor and its endpoints need moving under the vendor path. Nothing can be
done client-side first: there is no owner on the row to filter by.

Client work once that lands: point `SettingsRepository` at
`/api/core/vendor/<id>/establishment/` instead of `/api/core/establishment/`, for both reading and
creating. The mapper itself should not need changing.
