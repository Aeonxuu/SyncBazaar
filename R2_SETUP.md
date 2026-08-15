# Product images on Cloudflare R2

Wiring the existing R2 bucket into the Django API with `django-storages` and `boto3`, so the tablet
can upload a product photo and every client can read it back from a public URL.

Written for Gwendolyn to run top to bottom on their machine, against
`github.com/Allie1080/syncbazaar_backend`.

**Verified against:** Django 6.0.3 · django-storages 1.14.6 · boto3 1.43.53 (13 Aug 2026)

---

## Where the repo currently stands

**Already true**

- `django-storages 1.14.6` and `boto3 1.43.53` are in `requirements.txt` — no new install needed for
  storage itself.
- The R2 bucket exists and an API token has been created.
- `.env*` is gitignored, and `settings.py` already reads secrets through `python-decouple`.

**Missing**

- No `STORAGES`, `MEDIA_*`, or `STATIC_ROOT` in `settings.py` — only `STATIC_URL = 'static/'`.
- No image field anywhere. `ProductVariant.image_link` is a plain `CharField(max_length=127)`.
- No upload endpoint.

**Needs LJ's go-ahead before installing**

- `Pillow` — required by `ImageField`, not currently in `requirements.txt`.
- `whitenoise` — only if we decide Django should serve its own admin CSS in production.

---

## The two decisions this rests on

Everything below follows from these. Change either one and the settings block changes with it.

1. **The bucket is public, not presigned.** Product photos are catalogue data — the same image is
   fetched by every tablet, over and over, and it is not confidential. A public bucket gives us
   stable, cacheable URLs. Presigned URLs expire, so the tablet would have to re-ask the API for a
   fresh link every time it renders a grid, which defeats offline caching.

2. **Media goes to R2; static stays with Django.** The only static files this project has are the
   Django admin's own CSS. Pushing them to R2 buys nothing and costs a `collectstatic` upload on
   every deploy. Uploads (media) are the thing that actually needs to live off the dyno.

---

## Step 1 — Collect the four values from the Cloudflare dashboard

R2 speaks the S3 API, so boto3 talks to it the same way it talks to AWS — it just needs a different
endpoint. Four values, all from **R2 Object Storage** in the Cloudflare dashboard:

1. **Account ID** — shown on the R2 overview page. The endpoint is
   `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`. Note there is no bucket name and no region in
   that URL.
2. **Bucket name** — exactly as created, case-sensitive.
3. **Access Key ID** and **Secret Access Key** — from *Manage R2 API Tokens → Create API Token*.
   Give it **Object Read & Write** and scope it to this one bucket; Admin permissions would let a
   leaked key delete buckets. The secret is displayed once and never again.

> **If the token was already made:** if the secret has been pasted into chat, a screenshot, or a
> shared doc at any point, roll it now and create a fresh one. It is thirty seconds of work and the
> alternative is an open write handle on our storage.

---

## Step 2 — Turn on public read access for the bucket

R2 buckets are private by default and have no per-object ACLs — public access is a bucket-level
switch, which is why you will never set `default_acl` in Django. Two ways to expose it:

- **Public Development URL** (*Settings → Public Development URL → Enable*, type `allow` to
  confirm). Gives you a `https://pub-<hash>.r2.dev` hostname. Fine for now.
- **Custom domain** (*Settings → Custom Domains → Add*), e.g. `media.syncbazaar.com`, on a zone
  already in Cloudflare. This is the production answer.

> **Don't ship on r2.dev.** Cloudflare rate-limits the `r2.dev` development URL and explicitly says
> not to use it for production, and it can't sit behind caching, WAF rules, or bot management. It is
> fine while we're building; a custom domain has to land before the defense demo. Because the
> hostname is one env var, swapping later is a one-line change.

Whichever you pick, copy the hostname **without** the `https://` — django-storages wants a bare host
in `custom_domain`.

---

## Step 3 — Add a CORS policy

Needed because the Flutter web build fetches images through the browser's network stack, and without
a policy the browser blocks the response even though the URL is valid. The Android tablet doesn't
care, but our fastest test loop does.

*Bucket → Settings → CORS Policy → Add CORS policy*, JSON tab:

```json
[
  {
    "AllowedOrigins": ["http://localhost:8080", "https://syncbazaar.example"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3600
  }
]
```

`localhost:8080` is the port our `flutter run -d web-server` loop uses. `GET` and `HEAD` only — the
browser never writes to the bucket, since uploads go through Django.

---

## Step 4 — Put the credentials in `.env`

Same pattern as `SECRET_KEY` and `DATABASE_URL` already in there. `.gitignore` covers `.env*`, so
nothing here can be committed by accident.

```ini
# --- Cloudflare R2 ---
USE_R2=True
R2_ACCOUNT_ID=a1b2c3…
R2_BUCKET_NAME=syncbazaar-media
R2_ACCESS_KEY_ID=…
R2_SECRET_ACCESS_KEY=…
R2_PUBLIC_HOST=pub-xxxxxxxx.r2.dev
```

> **Watch for:** no quotes, no trailing spaces, no newline inside the secret. A stray space at the
> end of `R2_SECRET_ACCESS_KEY` produces `SignatureDoesNotMatch`, which reads like a permissions
> problem and isn't.

`USE_R2` is a switch, not decoration: with it off, storage falls back to the local filesystem, so
anyone can run the API and the test suite without credentials. Add the same six keys to Render's
environment when we deploy.

---

## Step 5 — Wire `settings.py`

Django 5.1 removed `DEFAULT_FILE_STORAGE` and `STATICFILES_STORAGE`, so on Django 6 the `STORAGES`
dict is the only way to do this — **most R2 tutorials online are still written against the old
settings and will silently do nothing here.**

Add `"storages"` to `INSTALLED_APPS`, then append this block at the bottom of
`syncbazaar_api/settings.py`, replacing the lone `STATIC_URL = 'static/'` line:

```python
# --- Files: media on Cloudflare R2, static served locally -------------------
#
# R2 is S3-compatible, so django-storages' S3 backend drives it unchanged; the
# only differences from AWS are the endpoint and region_name="auto". Uploads
# are catalogue photos, not private documents, so the bucket is public-read and
# querystring_auth is off -- signed URLs expire, and the tablet caches images
# across sessions.
#
# USE_R2 defaults to False so a fresh clone runs, and the tests run, without
# credentials.

USE_R2 = config("USE_R2", default=False, cast=bool)

MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"          # only used when USE_R2 is off

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"   # collectstatic target on Render

if USE_R2:
    R2_ACCOUNT_ID = config("R2_ACCOUNT_ID")

    STORAGES = {
        "default": {
            "BACKEND": "storages.backends.s3.S3Storage",
            "OPTIONS": {
                "bucket_name": config("R2_BUCKET_NAME"),
                "access_key": config("R2_ACCESS_KEY_ID"),
                "secret_key": config("R2_SECRET_ACCESS_KEY"),
                "endpoint_url": f"https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com",
                "region_name": "auto",          # R2's only region
                "signature_version": "s3v4",    # R2 rejects SigV2
                "custom_domain": config("R2_PUBLIC_HOST"),  # host only, no scheme
                "querystring_auth": False,      # plain public URLs
                "file_overwrite": False,        # two "shoe.jpg" uploads must not collide
                "location": "media",            # key prefix inside the bucket
                # default_acl is deliberately unset: R2 has no object ACLs.
            },
        },
        "staticfiles": {
            "BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage",
        },
    }
```

With `custom_domain` set and `querystring_auth` off, a file saved as `products/abc.jpg` gets the URL
`https://<R2_PUBLIC_HOST>/media/products/abc.jpg` — the `location` prefix is part of the key, so it
appears in the path. That is the single most common source of 404s later on.

> **Static files on Render:** uncomment the `collectstatic` line in `build.sh` now that
> `STATIC_ROOT` exists. With `DEBUG=False` Django still won't *serve* those files — the admin will
> render unstyled. That's cosmetic and only affects the admin, so it can wait; the fix is WhiteNoise,
> which is a new dependency and so LJ's call.

---

## Step 6 — Smoke-test the connection before touching any models

Prove the credentials work in isolation. If this fails, nothing downstream is worth debugging.

```python
# python manage.py shell
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage

name = default_storage.save("smoke-test.txt", ContentFile(b"hello r2"))
print(name)                          # smoke-test.txt
print(default_storage.url(name))     # https://pub-….r2.dev/media/smoke-test.txt
print(default_storage.exists(name))  # True
```

Open the printed URL in a browser — you should see `hello r2` with no login. Confirm the object is
listed in the Cloudflare dashboard under `media/`, then clean up with
`default_storage.delete(name)`.

Green here means credentials, endpoint, region, and public access are all correct. Every remaining
failure from this point on is Django-side.

---

## Step 7 — Give the model a real image field

`ProductVariant.image_link` is a `CharField(max_length=127)` holding a URL someone typed. It can stay
for now, but an uploaded file needs a field Django can write to.

```python
# core/models.py — ProductVariant
image = models.ImageField(
    upload_to="products/",
    max_length=255,      # default is 100; R2 keys get long
    null=True,
    blank=True,
)
```

`upload_to` stacks on top of the storage's `location`, so the final key is
`media/products/<filename>`. Then `makemigrations core && migrate`.

> **Dependency gate:** `ImageField` imports Pillow, which is not in `requirements.txt`. Two options:
> add Pillow (it validates that the upload is really an image and gives us width/height), or use
> `FileField` and validate the content type in the serializer. Pillow is the normal answer, but
> adding it is LJ's call — flag it and wait.

Serve one field to the client rather than making the app choose between old and new:

```python
# core/serializers.py — read side
image_url = serializers.SerializerMethodField()

def get_image_url(self, obj):
    # Uploaded file wins; image_link is the legacy hand-entered URL.
    if obj.image:
        return obj.image.url
    return obj.image_link or None
```

Once every variant has an uploaded image, `image_link` can be dropped in a later migration.

---

## Step 8 — Expose an upload endpoint and test it end to end

DRF parses JSON by default, so an upload view has to declare multipart parsers explicitly or it will
reject the request with a 415.

```python
# core/views.py
from rest_framework.parsers import MultiPartParser, FormParser

class ProductVariantImageView(generics.UpdateAPIView):
    queryset = ProductVariant.objects.all()
    serializer_class = ProductVariantImageSerializer
    parser_classes = [MultiPartParser, FormParser]
```

Route it, then hit it the way `file_tests/curl_file.sh` does — DRF token auth, not Bearer:

```bash
curl -X PATCH \
  -H "Authorization: Token <owner-token>" \
  -F "image=@shoe.jpg" \
  http://localhost:8000/api/variant/12/image/
```

The response should contain an absolute `image_url` on the R2 host. Paste it into a browser: the
photo loads, no signature in the query string, no expiry. That URL is what the Flutter app stores and
caches.

---

## When it breaks

Ordered roughly by how often they bite. The first row catches people who followed an older tutorial.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Unsupported header 'x-amz-sdk-checksum-algorithm'` or `… CRC32 not implemented` | boto3 ≥ 1.36 sends integrity checksums by default. Cloudflare shipped support in Feb 2025, so boto3 1.43 should be fine — but this is what it looks like if some operation still isn't covered. | Add `"client_config": Config(request_checksum_calculation="when_required", response_checksum_validation="when_required")` to `OPTIONS`, importing `Config` from `botocore.config`. Don't downgrade boto3. |
| `SignatureDoesNotMatch` | `region_name` isn't `"auto"`, the endpoint has the bucket name baked into it, or the secret in `.env` has whitespace. | Endpoint is account-level only. Re-paste the secret with no quotes or trailing space. |
| `AccessDenied` on write, reads fine | Token is *Object Read only*, or scoped to a different bucket. | Reissue with *Object Read & Write* scoped to this bucket. |
| `NoSuchBucket` | Bucket name typo, or the account ID in the endpoint belongs to another account. | Both come straight off the R2 dashboard; compare character by character. |
| Upload succeeds, public URL 401s or 404s | Public access never enabled, or the URL is missing the `media/` prefix that `location` adds. | Enable the development URL or custom domain; use `obj.image.url` rather than hand-building paths. |
| Image loads on the tablet, blank on Flutter web | Missing CORS policy — the browser blocks a valid response. | Add the policy from step 3, including the dev origin. |
| ACL-related error on save | `default_acl` set to `"public-read"`, copied from an AWS guide. | Remove it. R2 has no object ACLs; public access is bucket-level. |
| Files still land in the project folder | `USE_R2` is falsy, or an old `DEFAULT_FILE_STORAGE` line is doing nothing on Django 6. | Check `USE_R2`, and confirm `STORAGES["default"]` is what's actually set. |

---

## What lands on the Flutter side

Nothing until step 8 is green. After that, the API returns an absolute `image_url` per variant and
the app treats it as an ordinary network image — no auth header, no signing, no refresh. Two things
to confirm on our end when we get there: the URL survives round-tripping through the offline cache,
and a null `image_url` still renders the placeholder rather than an error tile.

---

## Sources

1. [django-storages — Cloudflare R2 backend](https://django-storages.readthedocs.io/en/latest/backends/s3_compatible/cloudflare-r2.html)
   — endpoint format, custom-domain requirement
2. [django-storages — Amazon S3 backend](https://django-storages.readthedocs.io/en/latest/backends/amazon-S3.html)
   — every `OPTIONS` key used above
3. [Cloudflare R2 — Authentication](https://developers.cloudflare.com/r2/api/tokens/)
   — token permission levels, bucket scoping, secret shown once
4. [Cloudflare R2 — S3 API compatibility](https://developers.cloudflare.com/r2/api/s3/api/)
   — endpoint, `region = auto`, unimplemented operations
5. [Cloudflare R2 — Public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)
   — development URL, rate limits, custom domains
6. [Cloudflare R2 — CORS](https://developers.cloudflare.com/r2/buckets/cors/)
   — policy shape and when it's required
7. [django-storages issue #1498](https://github.com/jschneier/django-storages/issues/1498)
   — the boto3 checksum workaround, verbatim
8. [Cloudflare Community — SDK checksum breakage](https://community.cloudflare.com/t/aws-sdk-client-s3-v3-729-0-breaks-uploadpart-and-putobject-r2-s3-api-compatibility/758637)
   — context and the Feb 2025 resolution
9. [Django 6.0 — `STORAGES` setting](https://docs.djangoproject.com/en/6.0/ref/settings/#storages)
   — why the old storage settings no longer apply

---

Repo facts (versions, existing fields, `build.sh`, `.gitignore`) were read from the local clone at
`~/Documents/GitHub/syncbazaar_backend` on 13 Aug 2026. The code blocks are written against that
state and not yet applied.
