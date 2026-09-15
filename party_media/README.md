# party_media

Profile imagery for a party, stored as a single Walrus quilt. All of a
party's images (avatar, header/cover, …) live together in one quilt —
batching them under a single storage reservation is markedly cheaper than
one blob each, which matters when the platform sponsors storage. Only the
quilt's blob id is held on-chain, as a dynamic field on the party's `UID`,
gated by the `PartyAdminCap`; views are permissionless. The chain is
deliberately role-agnostic: which patch is the avatar vs the header is a
client convention, derived off-chain — never stored here. Changed mutations
emit a complete, fixed-size event snapshot; equal replacements still write but
are silent, and an absent clear is silent.

## What it stores

- Key: `MediaKey()` — one dynamic field per party.
- Value: `Media { quilt: u256 }` — the Walrus quilt blob id holding all of
  the party's images. Individual images are quilt patches addressed by
  identifier ("avatar", "header", …); those roles are not stored.
- `set_media` replaces the id in place; an identical replacement is a silent
  write;
  `clear_media` removes the field entirely and is a no-op when none is set.

## API

`set_media` rejects a zero quilt before authorization. For a nonzero set, and
for every `clear_media` call, the cap must match the exact party or the call
aborts with `EUnauthorized` (0) at `partyos::party`.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_media(party, cap, quilt)` | Set or replace the party's media quilt; changed values emit one complete `MediaSetEvent`, equal replacements still write silently | `EZeroQuilt` (0) on a zero quilt id; wrong cap at `partyos::party` |
| `clear_media(party, cap)` | Remove the party's media and emit its prior quilt — no-op (and silent) when unset | wrong cap at `partyos::party` |

### Views

| Function | Returns |
|---|---|
| `has_media(party)` | Whether the party has media set |
| `quilt(party)` | `Option<u256>` — the quilt blob id, if set |

## Events

| Event | When | Payload |
|---|---|---|
| `MediaSetEvent` | Quilt set or replaced with a different id | `party_id`, `admin_cap_id`, `existed_before`, `previous_quilt`, `quilt`; the serialized payload is 129 bytes, and `previous_quilt` is zero only when `existed_before` is false. Equal replacements emit no event |
| `MediaClearedEvent` | Existing media removed; never on an absent clear | `party_id`, `admin_cap_id`, `previous_quilt`; the serialized payload is 96 bytes |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EZeroQuilt` | `set_media` called with a zero quilt id — zero is never a real Walrus blob id and is indistinguishable from "unset" downstream |
| 0 | `EUnauthorized` | `partyos::party`: a nonzero set or any clear uses a cap for a different party; authorization occurs before dynamic-field existence checks |

## Dependencies

- [`partyos`](https://github.com/misofm/partyos) at exact revision
  `c23df9018e15a76395c65bc8dfca4b365140aa12` — the `Party` /
  `PartyAdminCap` authorization core.
- Otherwise only the Sui framework (`sui::dynamic_field`, `sui::event`). The
  manifest has no local-path or floating dependencies.

## Integrator notes

- **Patch roles are a client convention.** Individual images are quilt
  patches addressed by identifier ("avatar", "header", …); those
  identifiers are agreed off-chain and never stored here. The chain stays
  role-agnostic on purpose.
- **Updating any image is a full re-store.** Re-store the quilt on Walrus,
  then call `set_media` with the new blob id — there is no patch-level
  write on-chain.
- **One quilt, not one blob per image.** A single storage reservation is
  markedly cheaper than one blob each, which matters when the platform
  sponsors storage.
- Indexers can reconcile a write from `MediaSetEvent` alone: `existed_before`
  distinguishes insert from replacement, and the event carries both quilt
  ids plus the authorizing cap address. On an insert, `previous_quilt` is a
  zero sentinel; zero is rejected as a new quilt id.
- `MediaClearedEvent` means the field is gone and carries the exact removed
  quilt id. A no-op `clear_media` emits nothing, but still authorizes first,
  so a wrong cap aborts even when no media is stored.
