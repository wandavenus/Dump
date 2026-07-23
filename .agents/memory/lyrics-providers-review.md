---
name: Lyrics providers review notes
description: Findings from reviewing lyrics_service/providers — Musixmatch removal reason and Apple Music lyrics API infeasibility.
---

## Musixmatch provider removed
`MusixmatchProvider` was deleted (2026-07-10). It required a `userToken` that
was never supplied anywhere in the app (no settings UI, no config path), so
`fetch()` always returned `null` immediately — dead code that ran on every
lyrics request for no benefit.

**Why:** app never had a way to obtain/store a Musixmatch user token.
**How to apply:** if Musixmatch support is wanted again, it needs a token
input in settings before re-adding the provider — otherwise it's dead weight.

## Apple Music lyrics API is not actually free/anonymous
Investigated unofficial Apple Music lyrics endpoints (e.g. the pattern used
by `ibratabian17/lyricsplus`): fetching lyrics requires calling
`amp-api.music.apple.com/v1/catalog/{storefront}/songs/{id}/syllable-lyrics`,
which needs a valid Apple Music **auth token tied to a real subscriber
account** (obtained via cookie scraping music.apple.com or an "Android auth
token" hack from an account manager). There is no public/anonymous endpoint
for lyrics like LRCLIB's — every known free implementation online still
depends on someone's real Apple Music account credentials behind the scenes.

**Why:** unlike catalog search (which works with an app-level dev token),
lyrics specifically require account-level auth Apple doesn't expose publicly.
**How to apply:** don't attempt an "Apple Music lyrics provider" without the
user explicitly supplying their own Apple Music account token — treat it as
credential-gated, same category as Musixmatch, not as a free anonymous API.

## Apple Music lyrics via lyrics.paxsenix.org proxy (added)
Found a working free/anonymous path after all: `lyrics.paxsenix.org` is a
public proxy that already holds its own Apple Music auth server-side and
exposes `GET /apple-music/lyrics?id={appleMusicTrackId}` with no key needed.
The trackId itself comes from the official free iTunes Search API
(`itunes.apple.com/search?term=...&entity=song`), also keyless. Implemented
as `AppleMusicProvider` (search iTunes → get trackId → call paxsenix →
convert "Syllable" JSON to inline `<mm:ss.xxx>` Enhanced-LRC text → parse
with existing `LrcParser`).

**Why:** this is a third-party proxy, not an Apple-sanctioned API — it can
go down or change shape without notice, same risk class as the other
unofficial providers (NetEase/Kugou/Kuwo/QQ).
**How to apply:** if lyrics.paxsenix.org lyrics start failing broadly, check
whether the proxy is still alive / response shape changed before assuming
a bug in `AppleMusicProvider`.
