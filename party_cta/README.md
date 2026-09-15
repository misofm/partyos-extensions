# party_cta

Off-Miso call-to-action links for a party — the "what do you want people to
do" row: Tickets, Merch, Newsletter, an external Listen. A CTA is deliberately
just a `{ label, url }`: on-Miso actions (collect / listen-on-Miso / pin) are
a different, interactive concern and live in `party_featured`, which
references object ids and can render live state — so this package stays a
plain, dependency-light external link hub.

The CTAs are an ordered list: **position is priority**. The whole list is
written at once (`set_ctas`) — the natural fit for a drag-to-reorder editor
that saves on submit — so there are no per-entry ids to track. Writes are
gated by the `PartyAdminCap` through `party::uid_mut(cap)`; views are
permissionless.

## What it stores

- Key: `CtasKey()` — a unit struct, so exactly one CTA-list field per party.
- Value: `vector<Cta>`, where `Cta { label: String, url: String }`. Order is
  preserved on-chain; position is priority.
- `set_ctas` replaces the whole list in place; `clear_ctas` removes the field
  entirely.

Limits, enforced in `new_cta` and `set_ctas`:

| Constant | Value | Applies to |
|---|---|---|
| `MAX_LABEL_LENGTH` | 60 bytes | a CTA's label |
| `MAX_URL_LENGTH` | 2000 bytes | a CTA's url |
| `MAX_CTAS` | 20 | the list as a whole |

## API

All writes require `&PartyAdminCap` for the exact party; a wrong cap aborts
with `EUnauthorized` at `partyos::party`.

### Constructor / accessors

| Function | Description | Aborts |
|---|---|---|
| `new_cta(label, url)` | Build a validated `Cta`; callers assemble the ordered `vector<Cta>` client-side and submit it with `set_ctas` | `EEmptyLabel` (0), `ELabelTooLong` (1), `EEmptyUrl` (2), `EUrlTooLong` (3) |
| `label(&cta)` | The CTA's display label | — |
| `url(&cta)` | The CTA's destination url | — |

### Writes (cap-gated)

| Function | Description | Aborts |
|---|---|---|
| `set_ctas(party, cap, ctas)` | Set or replace the party's ordered CTA list; changed values emit counts and provenance, equal replacements still write silently | `ETooManyCtas` (4) when the list exceeds 20 |
| `clear_ctas(party, cap)` | Remove the party's CTA list | — (no-op when none is set) |

### Views

| Function | Returns |
|---|---|
| `has_ctas(party)` | Whether a CTA list is stored |
| `ctas(party)` | The party's ordered CTA list (empty when unset) |

## Events

Events carry primitive addresses and raw UTF-8 bytes, preserving list order and
duplicates. They are emitted once per changed state mutation; equal
replacements still write the list but are silent, and an absent clear is silent.

| Event | When | Payload |
|---|---|---|
| `CtasSetEvent` | `set_ctas` changes the list (set, replace, or empty initial attachment) | `party_id`, `admin_cap_id`, `existed_before`, `previous_count`, `count` |
| `CtasClearedEvent` | `clear_ctas` removes an existing list — not emitted on a no-op clear | `party_id`, `admin_cap_id`, `previous_count` |

## Errors

| Code | Constant | Condition |
|---|---|---|
| 0 | `EEmptyLabel` | CTA label is empty |
| 1 | `ELabelTooLong` | CTA label exceeds 60 bytes |
| 2 | `EEmptyUrl` | CTA url is empty |
| 3 | `EUrlTooLong` | CTA url exceeds 2000 bytes |
| 4 | `ETooManyCtas` | List exceeds 20 CTAs |

A wrong `PartyAdminCap` aborts with `EUnauthorized` (0) at
`partyos::party`, before any mutation or event.

## Dependencies

- [`partyos`](https://github.com/misofm/partyos) at exact revision
  `c23df9018e15a76395c65bc8dfca4b365140aa12` — the `Party` /
  `PartyAdminCap` authorization core.
- Nothing else beyond the Sui framework (`sui::dynamic_field`, `sui::event`,
  `std::string`) — no primitive or protocol dependencies, by design. The
  manifest has no local-path or floating dependencies.

## Integrator notes

- **Full URLs, stored verbatim.** Unlike `platform_link` payloads (handles
  rebuilt into platform URLs client-side), a CTA's destination is arbitrary,
  so the URL itself is stored. There is no scheme or host validation on-chain:
  treat labels and URLs as untrusted input — sanitize before rendering, and
  decide which schemes (e.g. `https:`) you are willing to link to.
- **Order is the payload.** Render in stored order; do not re-sort. There are
  no per-entry ids, so entry identity does not survive a rewrite — diff by
  position, not by id.
- **Events are compact change signals.** Set events are 81 BCS bytes and
  clear events are 72 bytes regardless of content length. Read `ctas()` when
  labels and URLs are needed. Both events retain party and authorizing cap IDs.
- **Empty vs. absent.** `set_ctas` with an empty vector stores an empty list
  (`CtasSetEvent` with `existed_before = false` and `count = 0` on first set);
  replacing that stored empty list performs the write silently because the
  complete value is unchanged;
  `clear_ctas` removes the field and reports the removed count (including
  zero). `ctas()` returns an empty vector in both absent and stored-empty
  states — use `has_ctas` or event `existed_before` when the distinction
  matters.
