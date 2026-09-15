# party_social

Social-platform payloads for the `platform_link` primitive: ten networks,
each with its own `…Data` type — a thin wrapper around the account's native
handle — so a party can carry one independent `PlatformLink<…Data>` per
network. There is no mechanism here: storage, cap-gating, and events live in
`platform_link` and `party_platform_link`; this package only defines the
payload types and their constructors, so adding a network is a new type here
and nothing elsewhere. Only the handle is stored — the public profile URL is
rebuilt client-side, so a platform reshaping its URLs needs no on-chain
change. Validation is intentionally minimal (non-empty plus the shared
length backstop): handle *format* rules change over time and belong in the
app layer.

## What it stores

Nothing itself — the module holds no storage code. Each constructor returns
a `PlatformLink<…Data>` that `party_platform_link::set_link` stores as a
dynamic field on the party's `UID`, keyed by `PlatformLinkKey<Data>`: one
link per network per party, replaced in place on re-set.

Every payload is `…Data has copy, drop, store { handle: String }`. What the
`handle` holds per network:

| Type | `handle` holds |
|---|---|
| `XData` | X (formerly Twitter) handle, without the leading `@` |
| `InstagramData` | Instagram handle |
| `ThreadsData` | Threads handle, without the leading `@` |
| `TikTokData` | TikTok handle, without the leading `@` |
| `YouTubeData` | Handle or channel identifier |
| `DiscordData` | Server-invite code (the `{code}` in `discord.gg/{code}`) |
| `TelegramData` | Username or channel (the `{name}` in `t.me/{name}`) |
| `RedditData` | Username (the `{name}` in `reddit.com/user/{name}`) |
| `TwitchData` | Channel name |
| `FacebookData` | Page username or id |

Limits on `handle`: non-empty, at most 256 bytes
(`platform_link::max_identifier_length()`).

## API

All constructors are pure and permissionless — they validate and wrap, and
touch no party state. The cap-gated write path is
`party_platform_link::set_link<Data>` / `clear_link<Data>`, gated by
`PartyAdminCap` through `party::uid_mut(cap)`.

### Writes (cap-gated)

None in this package — see above.

### Constructors

Each takes `handle: String`, aborts `EEmptyHandle` (0) when empty and
`EHandleTooLong` (1) over 256 bytes, and wraps via `platform_link::new`.

| Function | Returns |
|---|---|
| `x(handle)` | `PlatformLink<XData>` |
| `instagram(handle)` | `PlatformLink<InstagramData>` |
| `threads(handle)` | `PlatformLink<ThreadsData>` |
| `tiktok(handle)` | `PlatformLink<TikTokData>` |
| `youtube(handle)` | `PlatformLink<YouTubeData>` |
| `discord(handle)` | `PlatformLink<DiscordData>` |
| `telegram(handle)` | `PlatformLink<TelegramData>` |
| `reddit(handle)` | `PlatformLink<RedditData>` |
| `twitch(handle)` | `PlatformLink<TwitchData>` |
| `facebook(handle)` | `PlatformLink<FacebookData>` |

### Accessors

| Function | Returns |
|---|---|
| `x_handle(&XData)` … `facebook_handle(&FacebookData)` | The stored `handle`; one accessor per type, each aliased as `.handle()` on its type via `public use fun` |

Read a payload back with `platform_link::data` — `link.data().handle()`.

## Events

None — payloads are inert. `party_platform_link` delegates to `platform_link`,
which emits the phantom-typed
`PlatformLinkSetEvent<Data>` / `PlatformLinkRemovedEvent<Data>` (carrying `parent_id` and existence flags)
when a link is set or cleared; indexers re-read the field.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EEmptyHandle` | Constructor called with an empty handle |
| 1 | `EHandleTooLong` | Handle longer than 256 bytes (`platform_link::max_identifier_length()`) |

## Dependencies

- [`platform_link`](../lib/platform_link) — a local-path sibling package
  (`platform_link = { local = "../lib/platform_link" }`) —
  `platform_link::new` wrapping plus the shared
  `max_identifier_length()` backstop.

Notably absent: `partyos`. This package never sees a `Party` or a
`PartyAdminCap`; authorization is entirely `party_platform_link`'s concern.
The manifest's only dependency is the local-path `platform_link` sibling
above.

## Integrator notes

- Rebuild public URLs client-side from the handle — `x.com/{handle}`,
  `discord.gg/{code}`, `t.me/{name}`, `reddit.com/user/{name}` — so a
  platform reshaping its URLs needs no on-chain change.
- Stored handles are untrusted input: validation stops at non-empty plus a
  length backstop. Sanitize before rendering, and apply current per-platform
  format rules in the app layer.
- The no-`@` convention on X, Threads, and TikTok handles is documented, not
  enforced — clients writing handles should strip the leading `@` themselves.
- One link per network per party: re-setting a network replaces in place.
  Adding a network is a new `…Data` type here and nothing elsewhere —
  `PlatformLinkKey<Data>` types are namespaced by this package, so its keys
  never collide with payloads from `party_music` or `party_pro_link`.
