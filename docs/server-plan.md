# Aircheck server side — plan (2026-09-04, draft)

The phone is a player of station packs. Generation happens on the fleet
(MBP + AI box). Neither can talk to the other directly: the AI box is behind
NAT and powered off overnight, and phones are only online when the user
opens the app. The server is the thing in the middle that both sides can
always reach. It holds generated content so it is made once and reused, it
holds user state, and it carries generation requests from phones to the
fleet and finished packs back.

## Roles

1. **Content store.** Every generated element (audio + its script + how it
   was made) and every assembled pack manifest, immutable and addressed by
   content hash. Reuse is the whole point; see *Element reuse* below.
2. **Source cache.** ARSA surveys, Billboard weeks, headline text for a date.
   Fetched once by the generator, stored forever, never re-fetched. This also
   keeps us polite to ARSA (one hit per station-week, ever).
3. **Users.** Identity, favourites, recent stations, playback position within
   a pack, later entitlements (if the LLC ever charges). Deliberately thin.
4. **Job queue.** "Nobody has built WLS / 1983-06-11 yet" becomes a job. The
   AI box polls for jobs when it is awake, generates, uploads, marks done.
   The phone sees the pack appear (poll or push). Also lets the MBP queue
   bulk pre-generation of popular station-weeks.
5. **Catalogue.** Which station-weeks exist, which are pending, which stations
   have survey coverage at all (so the app can offer real choices instead of
   a blank date picker).

## Recommended stack: Cloudflare

Workers (API) + D1 (SQLite: metadata, users, jobs) + R2 (blobs: audio,
manifests, cached sources). Auth via Sign in with Apple, verified in the
Worker, which issues its own session token.

Why this over the alternatives:

- **R2 has zero egress cost.** Audio is the only thing here with real
  bandwidth. Every other object store charges to send it to phones.
- **Free tier covers development and a small launch** (Workers 100k req/day,
  D1 5 GB, R2 10 GB). Fits the "local first, save money" rule.
- **The fleet can upload from anywhere.** R2 speaks S3; a Python or Swift
  generator on the AI box, OPS, or MBP writes to it with one credential.
- **Not Apple-only.** Leaves the door open to a web preview or Android without
  rebuilding the backend.
- Tooling is already on the MBP (Cloudflare MCP plugin, wrangler).

**Alternative considered: CloudKit.** Free with the developer membership, no
auth to build (iCloud identity), no server code, public database for shared
packs and private database for user state. It loses on the generator side:
writing to the public database from a Linux/Windows box means CloudKit Web
Services with server-to-server keys, and a job queue polled by the fleet is
awkward to model. It is also Apple-only forever. Reasonable fallback if the
Cloudflare auth work turns out to be more than a day or two.

**Not recommended:** AWS or a VPS on OPS. AWS is more ops and more bill for
the same shape; OPS is a home machine and should not be a public endpoint
for an app in the store.

## Element reuse (the core of the content store)

An element is one finished audio file plus its provenance. Elements are
addressed by a hash of everything that determined the audio:

    element_id = sha256(kind + script_text + voice_id + tts_model + tts_version + bed_id + mix_version)

Same inputs, same id, no second render. Reuse falls out of scope:

| Scope | Examples | Reused across |
|---|---|---|
| Era-generic | PSAs, national-brand ads, decade-flavoured sweeper copy | every station and week in that era |
| Station | legal ID, slogan liner, jingle-style ID, DJ name drop | every week for that station |
| Station-week | song intros/back-announces (tied to the survey) | every listener of that station-week |
| Date | newscast, weather | that date, any station in the market |

A **pack** is a manifest (JSON) listing element ids in hot-clock order plus
the song list with Apple Music catalog ids. It is also content-addressed. A
station-week can have several packs over time (new voice, better scripts)
and the catalogue points at the current one; old packs stay valid so an app
mid-play never has its manifest pulled out from under it.

The phone downloads the manifest, then only the elements it does not already
have on disk. Local cache is keyed by element id, so a listener who has
heard WLS all week already has most of next week's pack.

## Data model (D1, first cut)

    users            id, apple_sub, created_at, display_name?
    sessions         token_hash, user_id, expires_at
    stations         id, call_letters, city, state, format, first_seen, notes
    station_weeks    station_id, week_date, survey_source (arsa|billboard), survey_key, current_pack_id?
    packs            id (hash), station_id, week_date, manifest_key (R2), generator_version, created_at
    elements         id (hash), kind, scope, script_key (R2), audio_key (R2), duration_ms, voice_id, tts_model, created_at
    pack_elements    pack_id, position, element_id            -- denormalised from manifest for queries
    jobs             id, station_id, week_date, status (queued|running|done|failed), requested_by?, worker, started_at, finished_at, error?
    user_state       user_id, station_id, week_date, pack_id, position_ms, updated_at
    favourites       user_id, station_id

R2 layout:

    elements/<id>.m4a      elements/<id>.txt (script)
    packs/<id>.json
    sources/arsa/<station>/<week>.html      sources/billboard/<week>.json
    sources/headlines/<date>.json

## API (v1, sketch)

    POST /auth/apple                identity token -> session token
    GET  /stations?format=&decade=  catalogue with coverage
    GET  /stations/:id/weeks        which weeks exist / are pending
    GET  /packs/:id                 manifest
    GET  /elements/:id              302 to R2 (signed if we ever need it)
    POST /jobs                      request a station-week (rate-limited per user)
    GET  /me/state  PUT /me/state   resume position, favourites

Fleet-only (service token, not user auth):

    GET  /jobs/next                 AI box claims a job
    PUT  /jobs/:id                  status, result pack id
    PUT  /elements/:id  /packs/:id  register after R2 upload

## What stays off the server

- **MusicKit.** Authorization and playback are on-device only; the server
  never sees an Apple Music token. It stores catalog ids, nothing more.
- **Generation.** No LLM or TTS in Workers. The server hands out jobs and
  stores results.
- **Anything we would regret leaking.** No email addresses unless Sign in
  with Apple hands us a relay address we actually need. `apple_sub` is enough.

## Build order

1. R2 bucket + the element/pack hashing scheme, used by the generator CLI
   before there is any API. Uploads go straight to R2 with wrangler or an
   S3 client. This unblocks generation work with zero server code.
2. Worker with the read-only catalogue endpoints; the app fetches manifests
   and elements. Still no auth.
3. Jobs table and the fleet poller on the AI box.
4. Sign in with Apple and user state. Last, because nothing above needs it.

## Open questions

- ~~Sign in with Apple only, or anonymous first?~~ **Decided (user,
  2026-09-04): anonymous first, but limited.** The app mints a device
  identity on first launch and works with it, within limits; Sign in with
  Apple links that identity to an account and lifts them, and state then
  follows the user across devices. First-cut limits (tune later):
  anonymous can play packs that already exist, but a small number of
  station-weeks per day and no generation requests; no cross-device state;
  favourites and resume live on the device only. Signed-in users can
  request generation (rate-limited) and sync state. Enforced in the Worker
  by the session type, not in the app. `users` gets
  a nullable `apple_sub`, and `devices (id, user_id, created_at)` joins
  device identities to users.
- Push (APNs) when a requested pack is ready, or just poll on foreground?
- Who may request generation, and how many per day, given each job costs
  AI-box minutes.
- Whether user-generated station profiles (invented stations) are a v1
  feature or a later one; they change the catalogue model.
