# party_music

Music-platform payloads for the `platform_link` primitive — a party's links
to its own artist pages on streaming and music sites. The package defines
eight `Data` types (Spotify, Bandcamp, SoundCloud, Apple Music, Deezer,
Tidal, Amazon Music, Audiomack) and nothing else: no storage, no party
wiring, no events. Attaching a link to a `Party` is `party_platform_link`'s
job, so a new platform here is a new payload type and zero new mechanism.

These are *artist-level* identifiers (an artist's Spotify id, a Bandcamp
subdomain), distinct from the release-level (album/track) payloads the
protocol's DSP-link extension uses. Only the native id is stored; the
public URL is rebuilt client-side, so a platform reshaping its URLs needs
no on-chain change. Validation is intentionally minimal — non-empty plus
the shared `platform_link::max_identifier_length()` backstop.

## What it stores

Nothing itself. Storage is the primitive's: one dynamic field per `Data`
type on the party's `UID`, keyed by `PlatformLinkKey<Data>`, value
`PlatformLink<Data> { data }`; `set` replaces in place, `clear` reclaims
the field. Each payload below is a single `String`, guaranteed non-empty
and at most 256 bytes:

| Payload | Field | Public URL the client rebuilds |
|---|---|---|
| `SpotifyData` | `artist_id` | `open.spotify.com/artist/{artist_id}` |
| `BandcampData` | `subdomain` | `{subdomain}.bandcamp.com` |
| `SoundCloudData` | `username` | `soundcloud.com/{username}` |
| `AppleMusicData` | `artist_id` | `music.apple.com/artist/{artist_id}` (numeric id) |
| `DeezerData` | `artist_id` | `deezer.com/artist/{artist_id}` |
| `TidalData` | `artist_id` | `tidal.com/artist/{artist_id}` |
| `AmazonMusicData` | `artist_id` | `music.amazon.com/artists/{artist_id}` |
| `AudiomackData` | `username` | `audiomack.com/{username}` |

## API

No cap-gated writes live here — the package never sees a `Party` (it does
not even depend on `partyos`). The gated writes are
`party_platform_link::set_link(party, cap, link)` and
`clear_link<Data>(party, cap)`; the constructors below only build the
`PlatformLink<Data>` value those calls consume.

### Constructors

Each takes one `String` and aborts `EEmptyId` (0) on an empty identifier or
`EIdTooLong` (1) past `platform_link::max_identifier_length()` (256 bytes):

| Function | Returns |
|---|---|
| `spotify(artist_id)` | `PlatformLink<SpotifyData>` |
| `bandcamp(subdomain)` | `PlatformLink<BandcampData>` |
| `soundcloud(username)` | `PlatformLink<SoundCloudData>` |
| `apple_music(artist_id)` | `PlatformLink<AppleMusicData>` |
| `deezer(artist_id)` | `PlatformLink<DeezerData>` |
| `tidal(artist_id)` | `PlatformLink<TidalData>` |
| `amazon_music(artist_id)` | `PlatformLink<AmazonMusicData>` |
| `audiomack(username)` | `PlatformLink<AudiomackData>` |

### Accessors

Declared with `public use fun`, so they read as methods —
`link.data().artist_id()`:

| Method | Returns |
|---|---|
| `SpotifyData.artist_id()` | The stored artist id |
| `BandcampData.subdomain()` | The stored subdomain |
| `SoundCloudData.username()` | The stored username |
| `AppleMusicData.artist_id()` | The stored artist id |
| `DeezerData.artist_id()` | The stored artist id |
| `TidalData.artist_id()` | The stored artist id |
| `AmazonMusicData.artist_id()` | The stored artist id |
| `AudiomackData.username()` | The stored username |

## Events

None — payload types only. Setting or clearing one of these links on a
party is a `party_platform_link` write delegated to `platform_link`, which emits
`PlatformLinkSetEvent<Data>` / `PlatformLinkRemovedEvent<Data>` (carrying `parent_id`
and existence flags): an indexer sees which platform changed and re-reads the field.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EEmptyId` | Constructor called with an empty identifier |
| 1 | `EIdTooLong` | Identifier longer than 256 bytes |

Both abort at `party_music::party_music`. No primitive aborts surface —
validation runs before `platform_link::new` is called.

## Dependencies

- [`platform_link`](../lib/platform_link) — a local-path sibling package
  in this repository (`platform_link = { local = "../lib/platform_link" }`).
  `platform_link::new` wraps each payload, and
  `platform_link::max_identifier_length()` supplies the shared length
  backstop.
- No `partyos` dependency, by design: this package defines values, and
  cap-gating is entirely `party_platform_link`'s concern.

The manifest's only dependency is the local-path `platform_link` sibling
above.

## Integrator notes

- Attach with
  `party_platform_link::set_link(party, cap, party_music::spotify(id))` —
  one link per platform per party, replaced in place on re-set.
- Rebuild public URLs from the payload per the table above, and treat
  stored strings as untrusted input: sanitize before rendering.
  Constructors guarantee only non-empty and ≤ 256 bytes — not that the id
  exists on the platform, nor any character set (Apple Music ids are
  numeric by convention; that is not enforced on-chain).
- Artist-level only: track, album, and release links belong to the
  protocol's DSP-link extension, not to these payloads.
- Index on `PlatformLinkSetEvent<SpotifyData>` / `PlatformLinkRemovedEvent<SpotifyData>`
  and the like, and re-read the field — events carry only identity and existence context.
