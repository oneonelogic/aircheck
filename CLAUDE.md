# Aircheck — project context

iOS-first SwiftUI + MusicKit app that fabricates a listening session on a
radio station from the 1970s–1990s: jingles, station IDs, sweepers, PSAs,
ads, DJ patter, and a top-of-hour newscast, with 3–4 song slots per break
filled from what that station (city, format, specific date) was actually
playing. Songs come from Apple Music; everything else is generated. Named for
the radio term: an *aircheck* is a recording of a station's real output with
all the non-music elements intact, which is exactly what this app fakes.

Sibling project: `../casey` (macOS, Billboard → Apple Music playlists). Reuse
its MusicKit authorization and catalog-matching code (token-overlap scoring,
retry with backoff on catalog search) rather than reinventing it.

## Decisions (user, 2026-09-04)

| Question | Decision |
|---|---|
| Platform | **iOS first, macOS 14+ secondary** from the same SwiftUI multiplatform target. iPhone/iPad are the real devices; the Mac build is a bonus. |
| Song data | **ARSA station surveys first, Billboard format charts as fallback** when no survey exists for that station and week. |
| Station audio (jingles, IDs, sweepers, PSAs, ads) | **Synthesized from scripts**: LLM writes period-style copy, TTS reads it, generated or royalty-free music beds underneath. No real jingle packages (PAMS/JAM etc. are copyrighted). |
| Voice scope (v1) | **DJ patter plus news**: intros, back-announces, time/temp/weather, and a newscast with period-accurate headlines for the chosen date. |
| Generation compute | **Local first, on the AI box** (RTX 4090, 24 GB, Ollama), to avoid API spend during development. Cloud models are a later upgrade path, not the default. Mind model licenses: the app ships commercially under the LLC. |

## Why iOS, not Mac

- MusicKit is native on iOS 15+: authorization, catalog search, and in-app
  playback via `ApplicationMusicPlayer` are all first-class.
- In-app catalog playback only arrived on macOS 14, and Casey already hit
  the `MusicLibrary` mutation APIs being `@available(macOS, unavailable)`.
  Nothing here needs the Mac; the Mac target is free from the shared code.

## The hard constraint: DRM handoff

Apple Music catalog audio is DRM-protected and plays **only** through
MusicKit's own player. It cannot be routed through `AVAudioEngine`, so there
is no mixing, ducking, or crossfading between catalog songs and our audio.

Architecture follows from this: the app is a **sequencer that hands off
between two players**.

- Local elements (jingle, ID, ad, news, DJ bit) play through our own player
  (`AVAudioPlayer` / `AVAudioEngine`). These *can* be mixed with each other,
  so a DJ voice over a music bed, or a jingle sting into a sweeper, is fine.
- Songs play through `ApplicationMusicPlayer`. The app watches playback
  state, and when the song ends, starts the next local element.
- Transitions can be tight but never overlap. No DJ talking over a song
  intro, no jingle over the outro. Structure the hour so all talk happens
  between songs (which is how most 80s/90s formats sounded anyway).
- iOS: needs the `audio` background mode, and the song→element handoff must
  fire while backgrounded. Known fiddly area; prove it early with a spike
  before building anything on top.

## Data sources

- **ARSA** (Airheads Radio Survey Archive, las-solanas.com): real weekly
  surveys by call letters, city, and date, 1950s onward. Coverage is uneven
  by market and year. Scraping terms and a caching strategy are unresolved;
  check the site's terms before writing a client, and cache aggressively
  (one survey per station-week, immutable).
- **Billboard fallback**: [mhollingshead/billboard-hot-100](https://github.com/mhollingshead/billboard-hot-100)
  (free JSON, no key, Saturday-dated, 1958-08-02 → present; see Casey's
  CLAUDE.md for the URL scheme). Format charts beyond the Hot 100 (Country,
  R&B, AC, Rock) still need a source.
- **News**: period-accurate headlines for the chosen date. Source TBD
  (options: LLM from its own knowledge with a date anchor, Wikipedia
  "on this day"/year pages, newspaper archive APIs). Weather is fabricated
  as plausible for the city and month unless a historical source is cheap.

## Content generation pipeline (planned)

Generation is offline/asynchronous and happens on the MBP (and the local
Qwen minion / AI box, per the fleet rules), not on the phone:

1. **Station profile**: call letters, city, format, date, slogan, DJ name,
   sponsor list appropriate to era and market. Either derived from the ARSA
   survey (real call letters) or invented for the market.
2. **Scripts**: LLM writes the elements for a station profile: legal ID,
   sweepers, liners, PSAs, local ads, DJ intros/back-announces per song,
   newscast, weather. Style rules per decade matter more than the model.
3. **Voices**: TTS render per element. Voice choice per role (DJ, news
   reader, ad announcer). Provider undecided; on-device
   `AVSpeechSynthesizer` is the zero-cost fallback but sounds like it.
4. **Beds and stings**: generated or royalty-free instrumental beds, mixed
   under voice at render time so the phone gets finished element files.
5. **Package**: a "station pack" (JSON manifest + audio files + song list
   with catalog IDs) that the app plays back as a hot clock.

The app itself is a **player of station packs**; keep the generator a
separate tool (CLI, probably Swift or Python) so packs can be inspected and
regenerated without touching the app.

## Business identity

Ships under **OneOneLogic LLC** (same as Casey).

- Bundle ID: reserve `com.oneonelogic.aircheck` for the LLC release. Dev
  builds use `com.oneonelogic.aircheck.dev` under the personal Apple account
  with the MusicKit app service enabled. Fresh App IDs can 401 for ~15 min
  after registration.
- GitHub: private repo under the `oneonelogic` org, to be created when the
  user asks (never on Claude's initiative).

## Requirements

- Xcode (MusicKit). iOS 17+ / macOS 14+ deployment targets.
- Apple Developer Program membership, MusicKit-enabled App ID.
- Apple Music subscription on the account that authorizes the app.

## Build

Follow Casey's convention: project generated by **xcodegen** from
`project.yml`; edit the spec, run `xcodegen generate`, never hand-edit the
`.xcodeproj`. Pin `DEVELOPMENT_TEAM` in `project.yml` from the start (Casey
loses the Xcode-side team selection on every regenerate).

Keep MusicKit imports isolated in one service layer so the sequencer,
survey clients, and pack manifest code compile and test with the plain
`swiftc` toolchain, as Casey's `BillboardClient` does.

## Status / next steps

- [x] Name chosen, directory created (2026-09-04)
- [x] Platform and data decisions recorded above
- [x] Scaffold `project.yml` (one target, `supportedDestinations: [iOS, macOS]`), `xcodegen generate`; iOS-sim and macOS builds pass (2026-09-04). `DEVELOPMENT_TEAM` pinned to `92777459RZ`.
- [ ] Spike 1: iOS handoff proof. **Code written** (`Aircheck/Spike/`, 2026-09-04): `HandoffSequencer` plays `intro.aiff` → catalog song → `outro.aiff`, with two end-of-song detectors (Combine observer + 0.5 s poll) and a persistent log in `Documents/spike.log`. **Not yet run on a device** — needs the App ID registered and an iPhone attached. Nothing else matters if this is unreliable.
- [ ] Check ARSA terms of use; write a survey fetcher + cache
- [ ] Define the station-pack manifest format
- [ ] Generator CLI: station profile → scripts → TTS → element files
- [ ] Hot-clock sequencer in the app, playing a pack
- [ ] Register `com.oneonelogic.aircheck.dev` App ID with MusicKit (developer portal, user does this)

## Open questions

- TTS provider and cost (cloud vs on-device); whether voices per decade are
  worth separate treatment.
- Headline source for the newscast, and how to keep an LLM from inventing
  events for a specific date.
- Billboard format charts for non-Top-40 formats.
- Whether song slots respect the survey's chart positions (heavy rotation
  for the top of the survey) or draw uniformly.
- Music beds: generated (which model), royalty-free library, or composed.

## Local build notes

- `xcode-select` on the MBP points at CommandLineTools, so CLI builds need
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ...`
  (or `sudo xcode-select -s /Applications/Xcode.app` once). Xcode 26.6.
- The MBP keychain had **zero code-signing identities** on 2026-09-04. Xcode
  creates an Apple Development cert on the first signed device build if the
  Apple ID is signed in under Settings → Accounts.
- Spike clips were made with `say -v Samantha -o file.aiff "..."`; regenerate
  the same way if they need to change.

## Notes

Longer-form notes will live in the Obsidian vault alongside Casey's
(`~/Docs/personal/aircheck/`); keep a Log section there for milestones.
