# Offline product reads and recovery (Task 13)

## Supported behavior

An already validated, unexpired session can read products it successfully looked
up earlier when the server becomes unreachable. Cache misses are network errors,
never proof that a barcode is unknown. Unknown barcodes cannot create offline
products. Startup remains strict: a full restart still requires the existing
bounded session validation. Failed startup, expiry, logout and backend session
rejection end access. This deliberately follows the user's clarified policy.

Home lookup and Products repositories share a session-scoped cache. Only confirmed
product responses are stored. Cached details carry no edit/reference permissions.
Online permission checks are required again on recovery. No offline mutation,
outbox, background write or automatic write retry is implemented. Writes need
a verified connection and use the Mobile API v2 `If-Match` version and
`Idempotency-Key` contract online only.

## Architecture and security

- Drift 2.35.2 uses native SQLite in an application-support file, with a background
  database isolate. A versioned single-table schema uses parameterized custom SQL;
  no generated schema/build-runner dependency is necessary for this bounded cache.
- AES-256-GCM encrypts the approved product payload and local verification time.
  Each encryption uses a new random nonce and authenticates the schema and the
  row's opaque barcode code as AAD (`v2|code`), so payloads cannot be moved
  between rows. The key is domain-separated SHA-256 (`product-cache.v2`) of the
  session identity: environment, API base, company, user and session family
  (Stage 3). It contains no token, so access-token refresh keeps the cache. It
  is never written to SQLite. Tokens, scopes, credentials and pending writes
  are not cached.
- SQL identifiers contain opaque hashes for owner and barcode. Another login,
  user, company, server or flavor cannot read an earlier session's records.
  Logout, expiry and session disposal delete that owner's rows.
- Schema 2 (Mobile API v2): approved fields are ID, barcode, name, price,
  currency, quantity, tracked flag, unit, product reference, description,
  category ID/name, `updated_at` and tax display fields. Write-only data
  (`version`, permissions, adjustability, stock location, unit rounding) is
  never cached, so offline details have no edit permissions and cannot be
  written. Upgrading from schema 1 deletes all v1 snapshots; an envelope of
  another schema is a cache miss, and malformed or tampered rows are storage
  failures on read and are dropped during sync.
- Cached records older than 24 hours are not served. Storage is capped at 500
  entries across owners. The SQLite file itself is not SQLCipher-encrypted:
  product payloads and timestamps are encrypted, while counts and opaque indexes
  remain visible. Standard app sandbox and secure token storage protect access.
- Cache read corruption/storage failures produce a safe message. Cache save
  failures preserve a valid server response and show the failed sync indicator.
  Do not log payloads, keys, tokens, endpoints or raw exceptions.

## Recent scans

The same table also holds one encrypted row per session with the recently
scanned products for the scanner's "Last scanned" card (reserved code input
`\u0000recent`, AAD-bound like snapshots). It stores at most five entries of
`id`, `name`, `barcode`, `price`, `stock_quantity`, `uom` and the `category`
name (null without one), written by
`recordRecent` and read by `readRecents`.

- It has no 24-hour expiry; it lives as long as the session cache.
- A product write purges the snapshots but keeps this row; a confirmed write
  (`put`) refreshes the matching entry. The change feed refreshes or removes
  entries (removed products, lost barcodes), and losing feed access
  (`resetSync`), logout, expiry or session disposal delete it.
- The app keeps `readCacheProvider` listened to at the root, so closing the
  cache (and deleting its rows) happens at logout, not at the next read.
- Tampered or malformed data is a safe storage failure on read and is replaced
  by the next scan; the history never blocks scanning.

## Synchronization and conflicts

| Phase | Icon | Meaning |
| --- | --- | --- |
| Pending | Sync arrows | Server verification is in progress |
| Successful | Cloud check | Product was verified by the server |
| Offline | Cloud off | Potentially outdated cached information |
| Failed | Sync problem | A read/cache operation failed |

Every Products name card, including details, price, edit and creation, displays
the indicator opposite the untinted app logo. Tooltips/accessibility explain the
state and last local verification time; no extra visible text is added to the
card. Stock badges and existing gradients, fixed headers and glass actions remain.
Figma MCP was rate-limited; placement follows the attached marked card and existing
components, not a newly verified Figma extraction.

Connectivity Plus provides interface-change hints, not proof of backend health.
Cached snapshots are refreshed from `GET /products/changes` when the session
cache opens and on each recovery event. The first position is five minutes
before the oldest snapshot; afterwards the saved `next_since` (encrypted) is
used. Only already cached products are updated: changed products replace
their snapshot unless it has a newer `updated_at`, a new barcode drops the old
entry, and `removed_ids` are deleted. Pages are bounded per run and the position
is saved after each applied page, so interrupted syncs resume. A definitive
authentication rejection of the feed (`TOKEN_REVOKED`, `TOKEN_INVALID`,
`AUTH_REQUIRED`) is routed to the session sign-out handler, guarded by the
session identity so a stale failure never signs out a replacement session; the
sign-out purges the session cache. Outages never sign out. Mutations or
logout during a page cancel it. `SYNC_TOKEN_EXPIRED` (410) or lost read access
(403) delete the session's snapshots; other failures, a disabled feed or
malformed pages keep valid data untouched. Products the user can no longer
read are omitted by the feed and removed when an online read is rejected.
Confirmed write responses replace the snapshot purged before the write.

When connectivity returns, active details/edit/price/create controllers re-read
appropriate product data, preserving drafts. Only a successful server request
restores online status. Pull-to-refresh provides an explicit probe when the POS
recovers without a Wi-Fi change. There is no periodic ping loop. Offline reads of
known products do not repeatedly hit an unreachable server.

Concurrent reads are coalesced; repository details reads share their current
permission result. Concurrent mutations are rejected rather than queued. Before
a mutation, the session cache is invalidated, so an uncertain write cannot fall
back to pre-write data. Generation guards prevent a late read from repopulating
the cache after invalidation/logout. The backend remains authoritative; offline
conflicts are avoided by prohibiting offline writes, not by inventing merge rules.

## Verification

```sh
flutter test test/core/storage/encrypted_read_cache_test.dart
flutter test test/core/storage/read_cache_schema_test.dart
flutter test test/features/products/product_cache_sync_test.dart
flutter test test/features/products/offline_product_repository_test.dart
flutter test test/shared/product_sync_indicator_test.dart
flutter test --coverage
flutter test integration_test/offline_cache_test.dart --flavor development -d DEVICE_ID
```

Unit/widget tests use real in-memory Drift plus controlled network responses.
The manual device test uses a disposable on-device SQLite file, synthetic products
and simulated failures. It tests encrypted persistence, offline write blocking
and recovery icons without contacting Odoo or modifying inventory. It does not
prove real radio transitions or optical barcode recognition. Device tests stay
outside CI.

Verified on 2026-10-20: 373 unit/widget tests passed with coverage; static analysis
reported no issues and the exact format gate reported 142 files, zero changes.
The controlled device smoke test passed on Samsung A31 (SM-A315F), using the real
native Drift file and simulated network failures. No live Odoo writes or real
radio-outage test was performed. The development APK was built for ARM64.

On this Windows workstation, Java's default Unix socket location caused Gradle
to report `Unable to establish loopback connection`. The build used Android
Studio's bundled JDK and a command-local socket-directory override, without
changing repository Gradle settings:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\Users\Startklar\Pictures\Orangeone\build'
```

References: [Drift native setup](https://drift.simonbinder.eu/platforms/vm/),
[custom queries](https://drift.simonbinder.eu/sql_api/custom_queries/),
[encryption options](https://drift.simonbinder.eu/platforms/encryption/).

## Review fixes: repeated recovery and cache boundaries

Changes/recovery streams emit monotonic integer counters so Riverpod 3 observes
all events, including the second and later connectivity cycles. Tests exercise
pending/online/offline icon updates, management-button re-enabling and repeated
refreshes for details, price, edit and creation controllers. Drafts survive these
refreshes. Offline editing/creation stays prohibited; reconnection plus successful
server verification restores permitted actions.

Creation validates and rechecks its barcode/permissions before entering the cache
write critical section. Only backend save and legacy empty-tax correction are
guarded as writes. Cache read/decryption converts malformed-envelope and type
errors as well as ordinary exceptions into a safe storage failure and failed sync
status. Tests include a valid encrypted payload with one ciphertext byte changed.

Review-fix verification on 2026-10-20: all 381 unit/widget tests passed; analysis
reported no issues and the format gate reported 143 files with zero changes.
The Samsung A31 device test passed two offline/recovery icon cycles using a real
Drift file and controlled failures. Creation and tax correction were tested with
mocked backend responses and a real in-memory encrypted cache, not live Odoo writes.


## Integration with corrected CI branches (2026-10-20)

The corrected `feature/android_iOSbuild_CD` history, including the PR #9 testing
and license restoration, is merged into `feature/Offline-Sync` without rebasing
or changing main. Existing offline application code and locked dependencies are
preserved. Native flavor builds, manual protected distribution and executable
release regression checks are inherited from that branch.

The initial restored policy rejected the existing transitive Linux packages
`dbus` and `nm` (MPL-2.0), introduced through `connectivity_plus`. Following the
owner's request to resolve this CI failure, MPL-2.0 is included in the license
allowlist alongside MIT, BSD-3-Clause, BSD-2-Clause and Apache-2.0. The policy
still checks direct, development and transitive dependencies, skips no packages,
and fails on retrieval errors or licenses outside the explicit allowlist.
Adding a license to CI does not remove its license/notice obligations.


## Explicit read-only recovery (Issue #20)

Scanner Retry and Create Product Check pass `refresh: true` through their domain
repository contracts. Data repositories reuse `EncryptedReadCache.retryRead()`
before loading, allowing one authoritative read attempt even if the network
interface has not changed. Normal reads retain the offline short-circuit.
A failed probe keeps offline safety; a successful server read restores fresh
status and checks current permissions. Creation Check preserves the draft and
only checks availability/references; it never submits or replays a save.

## Authoritative reads and persistence failures (Issue #21)

`loadResult` returns per-operation server provenance separately from the product
sync phase. Successful Odoo reads recover connectivity even when SQLite cannot
save or remove the snapshot; the sync indicator remains failed in that case.
Products retain only permissions verified by that operation's server response.
Cached fallback results never carry verified permissions.

After a failed snapshot replacement/removal, the older persisted snapshot is
deleted before returning fresh data. The barcode also remains unavailable for
cache fallback in the current instance until a later persistence attempt succeeds,
including when durable cleanup itself fails. Fresh server data remains usable. Mutations still invalidate snapshots
before dispatch: failed invalidation produces a typed storage failure and sends
no backend mutation. No offline writes are enabled.


## Persistence ordering (Issue #24)

Snapshot encryption and identifier resolution finish before the revision/closed
check at SQL dispatch. A session-local persistence queue orders snapshot INSERT,
eviction/removal, mutation invalidation and session purge. An already dispatched
INSERT finishes before its purge; a read still preparing its INSERT is cancelled
when its revision changes. Backend mutations remain single-flight and are never
queued or replayed by this mechanism.
