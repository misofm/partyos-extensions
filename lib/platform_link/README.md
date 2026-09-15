# platform_link

`PlatformLink<Data>` — a typed link to an entity on one external platform (a
streaming service, a social network, any site), stored as a dynamic field on
any object's `UID`. Protocol-agnostic by design: it knows nothing about
platforms or consumers, so anything in the ecosystem can depend on it.
Consumers never re-implement link storage — they define a `Data` payload type
and get one independent link field per platform, keyed by type. Every mutation
emits a typed, bounded change event: payloads are represented only by their
canonical BCS length and Blake2b-256 digest, while the defining-ID-qualified
data type is included as raw bytes.

URLs are never stored: the client rebuilds the public URL from the `Data` it
reads back, so a platform reshaping its URLs needs no on-chain change.

## What it stores

- Key: `PlatformLinkKey<Data>` (phantom-typed — each platform gets its own
  field on the same `UID`, so adding a platform never touches another's).
- Value: `PlatformLink<Data> { data }` where `Data: copy + drop + store` is
  the platform's native identifier(s) — a handle, id, or subdomain.
- Exactly one link per `Data` type per `UID`; `set` replaces in place.
- `set` emits `PlatformLinkSetEvent<Data>` for inserts and changed replacements;
  equal replacements still write silently. `remove` and `clear` emit
  `PlatformLinkRemovedEvent<Data>` only when a link was present. Events carry no
  full payload bytes.

The module also owns the shared storage backstops so every payload package
uses the same numbers:

| Function | Value | Applies to |
|---|---|---|
| `max_identifier_length()` | 256 bytes | handles, usernames, ids, subdomains |
| `max_url_length()` | 2000 bytes | payloads whose URL is the identity |

## API

All functions take the host object's `UID` directly; authorization is the
consumer's concern (e.g. `party_platform_link` gates with `PartyAdminCap`).

### Constructor / accessor

| Function | Description |
|---|---|
| `new<Data>(data)` | Wrap a platform payload into a link |
| `data<Data>(&link)` | Read the wrapped payload |

### UID storage

| Function | Description | Aborts |
|---|---|---|
| `set<Data>(&mut uid, link)` | Store, replacing any existing link; emits a bounded set event | — |
| `clear<Data>(&mut uid)` | Remove if present and emit a bounded removed event | — (no-op when absent) |
| `remove<Data>(&mut uid)` | Remove and return the link; emits a bounded removed event | `ENoLink` (0) when absent |
| `exists_<Data>(&uid)` | Whether a link is stored | — |
| `get<Data>(&uid)` | `Option<PlatformLink<Data>>` | — |
| `borrow<Data>(&uid)` | `&PlatformLink<Data>` | `ENoLink` (0) when absent |

## Events

| Event | When | Payload |
|---|---|---|
| `PlatformLinkSetEvent<Data>` | `set` on insert or a changed replacement | `parent_id`, raw defining-ID-qualified `data_type`, existence transition, and previous/new `Data` BCS length plus Blake2b-256 hash; equal replacements emit no event |
| `PlatformLinkRemovedEvent<Data>` | present `remove` or `clear` | `parent_id`, raw defining-ID-qualified `data_type`, `true`/`false` existence transition, and removed `Data` BCS length plus Blake2b-256 hash |

Absent `clear` is silent. The event's `data_type` is not BCS-wrapped; it is the
raw bytes of `type_name::with_defining_ids<Data>().into_string()`.

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `ENoLink` | `borrow` / `remove` with no link stored |

## Dependencies

No explicit manifest dependency. The Sui framework is resolved automatically;
`Move.lock` pins both Testnet and Mainnet framework sources to
`2a0becb2fcc6989e492981104af67f62f2c9511a`. The manifest has no local-path
or floating dependencies.

## Integrator notes

- Define one `…Data` struct per platform in the appropriate payload package
  (`party_social`, `party_music`, `party_pro_link`), validate non-empty plus
  the shared length backstops in its constructor, and wrap with
  `platform_link::new`.
- Rebuild public URLs client-side from the payload (e.g.
  `x.com/{handle}`) — and treat stored strings as untrusted input when
  rendering.
- `PlatformLinkKey<Data>` types are namespaced by the defining package, so
  identically-named payloads in different packages never collide.
- Index events by their phantom-typed event streams. Re-read the dynamic field
  when the full payload is needed; event summaries are bounded integrity
  signals, not a copy of `Data`.
