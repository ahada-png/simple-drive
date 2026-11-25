# Simple Drive

A Ruby on Rails API for storing and retrieving blobs by id, with one interface
over several storage backends:

| Backend    | How it works |
|------------|--------------|
| `local`    | Files under a configured directory |
| `database` | Rows in a dedicated `blob_contents` table, separate from the metadata table |
| `s3`       | Any S3-compatible service (AWS S3, MinIO, DigitalOcean Spaces, Linode). Uses **only `Net::HTTP`** with a hand-written AWS Signature V4 signer. No S3 SDK. |
| `ftp`      | FTP server via `net-ftp` (bonus) |

Requests are authenticated with Bearer tokens.

## Quick start

```bash
bundle install                        # creates Gemfile.lock: commit it
bin/rails db:prepare
bin/rails "api_tokens:create[me]"     # prints a token once; copy it
bin/rails server
```

```bash
TOKEN=sd_xxx   # from the step above

# Store
curl -X POST http://localhost:3000/v1/blobs \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"id": "any_valid_string_or_identifier", "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh"}'

# Retrieve
curl http://localhost:3000/v1/blobs/any_valid_string_or_identifier \
  -H "Authorization: Bearer $TOKEN"
```

```json
{
  "id": "any_valid_string_or_identifier",
  "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh",
  "size": "27",
  "created_at": "2026-11-25T11:37:55Z"
}
```

Ids can be any string, including paths such as `photos/2026/cat.png`; `GET /v1/blobs/photos/2026/cat.png` works.

## API

| Method | Path | Success | Errors |
|--------|------|---------|--------|
| `POST` | `/v1/blobs` | `201` with `{id, size, created_at}` | `400` malformed JSON · `401` bad/missing token · `409` id already exists · `413` blob larger than `MAX_BLOB_SIZE` · `422` missing id/data or data is not valid Base64 · `502` storage backend failed |
| `GET`  | `/v1/blobs/<id>` | `200` with `{id, data, size, created_at}` | `401` · `404` unknown id · `500` checksum mismatch · `502` storage backend failed |

`data` must be standard, padded Base64 (`Base64.strict_decode64`). Anything else is rejected.

**Authentication.** Every route requires `Authorization: Bearer <token>`. Other schemes (`Token`, `Basic`, a bare token) are rejected with `401`. There are no public routes, not even a health check.

**Size limit.** `MAX_BLOB_SIZE` (bytes, default 10 MB) caps the decoded blob. Bodies whose `Content-Length` is already over the limit are refused before the JSON is parsed, so a huge upload never gets decoded into memory.

**Ids in URLs.** Ids can contain anything (Arabic, spaces, `#`, `?`, `%`, emoji). Percent-encode them in the URL as usual, e.g. `GET /v1/blobs/%D8%AA%D9%82%D8%B1%D9%8A%D8%B1%20%231.pdf`.

## Choosing a backend

Set `STORAGE_BACKEND` to `local`, `database`, `s3` or `ftp`. All settings live in
`config/simple_drive.yml` and can be overridden with environment variables (see `.env.example`).

```bash
# Local file system (the only required setting is the directory)
STORAGE_BACKEND=local LOCAL_STORAGE_PATH=/home/john/server_storage bin/rails s

# Database
STORAGE_BACKEND=database bin/rails s

# S3 / MinIO
docker compose up -d minio minio-setup
STORAGE_BACKEND=s3 S3_ENDPOINT=http://localhost:9000 S3_BUCKET=simple-drive \
  S3_ACCESS_KEY_ID=minioadmin S3_SECRET_ACCESS_KEY=minioadmin bin/rails s

# FTP
docker compose up -d ftp
STORAGE_BACKEND=ftp FTP_HOST=localhost FTP_USERNAME=drive FTP_PASSWORD=drivepass bin/rails s
```

For AWS itself, use `S3_ENDPOINT=https://s3.<region>.amazonaws.com` and `S3_FORCE_PATH_STYLE=false`.

Each blob records which backend it was written to, so changing `STORAGE_BACKEND`
later doesn't break reads of older blobs.

## Design

```
V1::BlobsController         HTTP only: parse request, render JSON
        │
BlobService                 validation, Base64 decoding, metadata, checksum
        │
Storage.adapter             picks the backend from config
        │
Storage::Adapter            store(key, bytes) / retrieve(key) / delete(key)
  ├── LocalAdapter
  ├── DatabaseAdapter       → blob_contents table
  ├── S3Adapter             → S3::Signer (SigV4) + S3::HttpClient (Net::HTTP)
  └── FtpAdapter            → net-ftp
```

- **One interface.** Each backend subclasses `Storage::Adapter` and implements three methods. Adding a backend means one new class plus one line in `Storage::BACKENDS`.
- **Metadata separate from bytes.** The `blobs` table holds `identifier`, `size`, `checksum`, `backend` and `storage_key`. The bytes live only in the backend.
- **Safe backend keys.** Client ids can be anything, so each backend gets `SHA256(id)` as its key. That's always a valid filename, S3 key or FTP path, and it rules out path traversal (`../../etc/passwd`).
- **Consistency.** See [Consistency](#consistency) below.
- **Integrity.** A SHA-256 checksum is stored on upload and checked on every read.
- **Local writes are atomic.** Each file is written to a temp file, then renamed.
- **Tokens.** Only a SHA-256 digest of each token is stored, and lookup goes by digest. Manage tokens with `api_tokens:create[name]`, `api_tokens:list` and `api_tokens:revoke[id]`. `API_TOKEN=... bin/rails db:seed` creates a known token for scripts.

### S3 without an SDK

`Storage::S3::Signer` implements [AWS Signature Version 4](https://docs.aws.amazon.com/IAM/latest/UserGuide/create-signed-request.html):
canonical request → string to sign → HMAC-derived signing key (date → region → service → `aws4_request`)
→ `Authorization` header, plus `x-amz-date` and `x-amz-content-sha256`. The adapter calls the S3 REST API
(`PUT`/`GET`/`DELETE /<bucket>/<key>`) and supports both path-style and virtual-hosted-style URLs.
The signer is tested against AWS's published SigV4 test-suite vectors.

## Consistency

The metadata row (in `blobs`) and the bytes (in the backend) must agree. How that's guaranteed depends on the backend:

| Backend | Guarantee |
|---------|-----------|
| `database` | **Atomic.** The bytes are written inside the same DB transaction as the metadata, so both commit or neither does. |
| `local`, `s3`, `ftp` | **Compensated.** A DB transaction can't cover an external system, so the service (1) inserts the metadata row, where the unique index claims the id, (2) writes the bytes, (3) commits. If step 2 or 3 fails (a backend error, a timeout after the server had in fact stored the object, or a failed COMMIT), the row is rolled back and the bytes are deleted from the backend. |

Two cases are handled on purpose:
- **Duplicate id:** the insert fails before anything is written, so the original blob's bytes are never touched.
- **Concurrent uploads of the same id:** the unique index lets exactly one win; the other gets `409`.

**Known limitation:** if the process is killed between writing the bytes and committing, or the compensating delete itself fails (that case is logged), an orphaned object can remain in the external backend. It's harmless, since no metadata points to it and its key is derived from the id, but it uses space. A production system would add a periodic sweep comparing backend keys with `blobs.storage_key`, or an outbox/"pending" status column.

## Tests

```bash
bin/rails test
```

- Unit tests for every adapter, the signer (AWS test vectors), the service, the factory and tokens.
- Integration tests for the HTTP API: auth, validation, duplicates, 404, path ids, the database backend end to end, and backend failure → 502.
- Ids with Arabic text, spaces, `#`, `?`, `%`, `+` and emoji, sent percent-encoded and read back.
- Live tests against real servers: `test/integration/s3_live_test.rb` (MinIO, `S3_LIVE_TEST=1`) and `test/integration/ftp_live_test.rb` (FTP, `FTP_LIVE_TEST=1`). CI (GitHub Actions) starts a real MinIO and a real FTP server and runs both.
