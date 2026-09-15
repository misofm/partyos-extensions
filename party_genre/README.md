# party_genre

A party's musical-genre tags: a small set of `genre::Genre` object ids drawn
from the shared Miso genre vocabulary, so a party's genres are exactly the ids
releases (and anything else) use. Adding a genre takes a `&Genre`, proving at
write time that the id is a real vocabulary entry; removal is by id. Genre is
presentation, not protocol-verifiable state, so the set is a lightweight
display tag list — no primary/secondary ranking, no anti-churn locks. The set
mechanics — storage, duplicate and capacity checks, field reclamation — live
in the shared `typed_set` primitive; this package keeps only the vocabulary
proof, the capacity, and the typed events.

## What it stores

- Key: `GenresKey()` — a unit struct local to this package, so no other
  consumer's set collides with it on the party's `UID`.
- Value: a bare `VecSet<ID>` of `genre::Genre` object ids under that key — no
  wrapper struct.
- Capacity: `MAX_GENRES` = 20 genres per party.
- Reclamation: removing the last genre drops the whole dynamic field (an empty
  set is indistinguishable from none, and the storage rebate goes back to the
  payer); `clear_genres` removes the field outright and is a no-op when absent.

## API

All writes require `&PartyAdminCap` for the exact party and go through
`party::uid_mut(cap)`; a wrong cap aborts with `EUnauthorized` at
`partyos::party`. Views are permissionless.

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `add_genre(party, cap, &Genre)` | Tag a genre — the `&Genre` reference proves vocabulary membership | wrong cap; `EDuplicateItem` (0) if already tagged, `EMaxItemsExceeded` (2) at 20 genres — both at `typed_set::typed_set` |
| `remove_genre(party, cap, genre_id)` | Remove a genre by id; reclaims the field when the last one leaves | wrong cap; `EItemNotPresent` (1) at `typed_set::typed_set` when not tagged (or no set stored) |
| `clear_genres(party, cap)` | Remove the party's entire genre set | wrong cap; no-op when none is set |

### Views

| Function | Returns |
|---|---|
| `has_genres(party)` | Whether the party carries any genres |
| `has_genre(party, genre_id)` | Whether the party carries the given genre |
| `genres(party)` | The party's genre ids, in insertion order (empty when none) |

## Events

| Event | When | Payload |
|---|---|---|
| `GenreAddedEvent` | A genre is tagged (`add_genre`) | `party_id`, `admin_cap_id`, `genre_id`, `genre_name`, `genre_count_before`, `genre_count_after`, `max_genres` |
| `GenreRemovedEvent` | A genre is removed (`remove_genre`) | `party_id`, `admin_cap_id`, `genre_id`, `genre_count_before`, `genre_count_after` |
| `GenresClearedEvent` | The whole set is removed (`clear_genres` on an existing set) | `party_id`, `admin_cap_id`, `genre_count_before`, `genre_count_after`, `genre_ids_before` |

## Errors

This package declares no error constants of its own — every validation abort
surfaces from a dependency:

| Code | Constant | Location | Condition |
|---|---|---|---|
| 0 | `EDuplicateItem` | `typed_set::typed_set` | `add_genre` with a genre already in the set |
| 1 | `EItemNotPresent` | `typed_set::typed_set` | `remove_genre` with an id not in the set (or no set stored) |
| 2 | `EMaxItemsExceeded` | `typed_set::typed_set` | `add_genre` when the set already holds `MAX_GENRES` (20) genres |
| 0 | `EUnauthorized` | `partyos::party` | any write with a cap for a different party |

## Dependencies

- [`partyos`](https://github.com/misofm/partyos) at
  `c23df9018e15a76395c65bc8dfca4b365140aa12` — `Party` authorization.
- [`typed_set`](https://github.com/unconfirmedlabs/typed_set) at
  `b37474cbde166b7ddf8a3b615cd89f90182ace6f` — bounded-set storage,
  duplicate/capacity checks, and field reclamation.
- [`genre`](https://github.com/misofm/genre) at
  `09f6882b57b19498f36fa15840cd7ed61094dc41` — the canonical shared genre
  vocabulary.

All are exact Git pins; this manifest has no local-path dependencies.

## Integrator notes

- **The set stores ids, never names.** Resolve display names client-side from
  the `Genre` objects — they are frozen, so globally readable by reference.
- **Ids are name-derived.** `genre::derive_address(registry, name)` computes
  the address a genre name would have without creating it, so clients can
  resolve or check a genre id offline.
- **Every stored id is proven.** Adds require the `&Genre` object, so nothing
  outside the vocabulary can ever enter the set — readers can trust that each
  id resolves to a real entry. The ids are the vocabulary's own, the same ones
  `release_genre` tags releases with, so party genres join cleanly against
  release metadata.
- **Events are change signals.** Add/remove carry the changed genre ID and
  counts; add also carries its short display name. Clear retains the removed
  relationship IDs (at most 20). Re-read `genres()` for current state.
- **No ranking.** `genres()` returns insertion order (a `typed_set`
  guarantee); any notion of a "primary genre" — e.g. first element — is a
  client convention, not protocol state.
