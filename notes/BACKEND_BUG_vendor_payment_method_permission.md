# Bug: nobody but a superuser can read or delete a vendor payment method

**Where:** `bazaars/permissions.py`, `IsAdminOrEventVendor`, used by
`core/views.py` → `VendorPaymentMethodDetailApiView`
**Impact:** blocks the client from finishing QR support. Create and image-upload work;
retrieve, update and delete do not.
**Found:** 2026-09-09, against `syncbazaar-backend.onrender.com`

## What happens

`IsAdminOrEventVendor` decides from an `event_pk` in the URL:

```python
def has_permission(self, request, view):
    if request.user.is_superuser:
        return True

    event_pk = view.kwargs.get('event_pk')

    if not event_pk:
        return False        # <-- every non-event URL lands here
    ...
```

`VendorPaymentMethodDetailApiView` is routed as
`core/vendor/<vendor_pk>/payment-method/<payment_method_pk>/`. There is no `event_pk`, so
the check returns `False` for everyone except a superuser.

Reproduced as `owner@syncbazaar.com` (role OW, vendor 1):

| Request | Result |
| --- | --- |
| `POST /api/core/vendor/1/payment-method/` | 201, works |
| `PUT  /api/core/vendor/1/payment-method/1/image/` | 200, works |
| `DELETE /api/core/vendor/1/payment-method/1/` | **403** |

The two that work use different permission classes, which is why the gap went unnoticed.

## Suggested fix

That permission is written for event-scoped URLs. The payment-method detail view is
vendor-scoped, so it needs a vendor-scoped check instead. Something like:

```python
class IsVendorMember(BasePermission):
    """For /core/vendor/<vendor_pk>/... URLs, where scope comes from the vendor."""
    def has_permission(self, request, view):
        if request.user.is_superuser:
            return True

        vendor_pk = view.kwargs.get('vendor_pk')
        if not vendor_pk:
            return False

        try:
            return str(request.user.vendor_assignment.vendor_id) == str(vendor_pk)
        except VendorAssignment.DoesNotExist:
            return False
```

then in `VendorPaymentMethodDetailApiView`:

```python
def get_permissions(self):
    permissions = [IsAuthenticated(), IsVendorMember()]
    if self.request.method in ['PUT', 'PATCH', 'DELETE']:
        permissions.append(IsAdminOrOwner())
    return permissions
```

Worth checking whether any other non-event view uses `IsAdminOrEventVendor` with the same
result.

## Leftover to clean up

Probing the endpoints created a real row that then could not be deleted:

```
vendor 1, mode_of_payment 2 (GCash), qr_code_image = .../vendor_payment_qr_codes/probe.png
```

The row itself is wanted, so it can stay; the image is an 8x8 black square and will be
overwritten the first time a real QR is uploaded from the app. Delete it directly if you
would rather start clean.

## Client side

Waiting on this. The plan is for the app to read QR codes from these endpoints instead of
storing them per device, so a code uploaded on the laptop shows up on the tablet. Create
and upload are enough to build against; remove-a-QR needs the fix above.
