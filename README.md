# Miso Party Extensions

Artist/entity profile pages on Sui, built as small, independent Move packages.
The state-attaching **extensions** each add one coherent slice to a core
[`partyos::party::Party`](https://github.com/misofm/partyos) as a
dynamic field — bio, roles, tags, links, imagery, and CTAs. This repository
also contains pure platform payload packages (`party_music`, `party_social`,
and `party_pro_link`): they construct typed values but never access a `Party`
or a `PartyAdminCap`. Every package publishes immutably and evolves through a
new package when necessary; many small packages beat one mega-struct.

Design principles, the field-placement rules (declare vs. derive vs. reference
vs. off-chain), and the phasing live in [ROADMAP.md](ROADMAP.md). The process
for documenting an extension — required reading before adding one — lives in
[AGENTS.md](AGENTS.md).

## Architecture

- **One slice per state-attaching extension.** Each such package owns its
  dynamic-field key(s) and values on the party's `UID`. Distinct key types
  prevent collisions.
- **Cap-gated state, pure payloads.** Every state-attaching write goes through
  `party::uid_mut(cap)`, and its views are permissionless. The three payload
  packages are pure constructors/accessors; `party_platform_link` performs the
  cap-gated attachment for their values.
- **Shared primitives do the mechanics.** `lib/platform_link` stores one typed
  link per platform on any `UID`; immutable
  [`unconfirmedlabs/typed_set`](https://github.com/unconfirmedlabs/typed_set)
  stores one bounded `VecSet<T>` per key type on any `UID`. Extensions keep
  only their domain types, validation, and events — never re-implement storage.
- **Reference, don't embed.** Media is a Walrus blob id; links store the
  platform's native handle/id (the client rebuilds the URL). Nothing large or
  derivable is copied on-chain.

## Packages

### Primitives (object-agnostic, no Miso dependencies)

| Package | Owns |
|---|---|
| [`lib/platform_link`](lib/platform_link) | `PlatformLink<Data>` — one typed external-platform link per `UID`; shared length backstops |
| [`unconfirmedlabs/typed_set`](https://github.com/unconfirmedlabs/typed_set) | One bounded `VecSet<T>` per key type per `UID` — init-on-add, dup/max checks, field reclamation |

### State-attaching extensions (gated by `PartyAdminCap`)

| Package | Owns |
|---|---|
| [`party_platform_link`](party_platform_link) | Party wiring for `PlatformLink<Data>` — `set_link` / `clear_link` / views + phantom-typed events |
| [`party_profile`](party_profile) | Profile card: `bio_short`, `bio_long`, `country`, `languages` (validated code types) |
| [`party_genre`](party_genre) | Genre-id set, proven at write time against the `genre` vocabulary |
| [`party_roles`](party_roles) | Artist-type set: Artist/Producer/DJ/Composer/Songwriter/Band/Label/Collective + `Custom` |
| [`party_tags`](party_tags) | Free-form tag set (moods, scenes, descriptors) |
| [`party_media`](party_media) | Imagery: one Walrus quilt blob id (avatar/header are quilt patches, a client convention) |
| [`party_cta`](party_cta) | Ordered external call-to-action links (`{ label, url }`, position is priority) |

### Pure payload packages (no `Party` or cap access)

| Package | Owns |
|---|---|
| [`party_social`](party_social) | Social handle payloads: X, Instagram, Threads, TikTok, YouTube, Discord, Telegram, Reddit, Twitch, Facebook |
| [`party_music`](party_music) | Music-platform artist payloads: Spotify, Bandcamp, SoundCloud, Apple Music, Deezer, Tidal, Amazon, Audiomack |
| [`party_pro_link`](party_pro_link) | Pro/industry payloads: website, booking/management/publisher/label pages, EPK; Patreon, Substack, Ko-fi |

Operational Party workflows are not profile extensions. Composable raw-cap
operations live in **Actions** packages; Vault-based, permissionless automation
belongs in separate entry-only plugin packages that call those Actions. The
current custody-agnostic inbox and accumulator Actions live in
[`misofm/partyos-actions/party_wallet`](https://github.com/misofm/partyos-actions/tree/main/party_wallet).

## Conventions

- **Events are change signals.** See [EVENT_PAYLOADS.md](EVENT_PAYLOADS.md) for
  the complete event inventory and serialized payload bounds. Dynamic-field mutations are not observable
  off-chain, so every write emits an event carrying `party_id`. Payloads are
  not re-included — an indexer re-reads the field — except small, stable ones
  (ids and short display strings: `party_media`'s quilt id and role/tag
  strings), which ride in.
- **Validation is split on purpose.** Primitives enforce set mechanics
  (duplicate / not-present / over-max — aborts come from `typed_set` or
  `platform_link` with their codes). Extensions enforce domain rules
  (non-empty, length, vocabulary proofs) before calling in. Format rules for
  handles and URLs are deliberately *not* on-chain — they change over time and
  belong to the app layer.
- **Stored URLs and handles are untrusted input.** Frontends must sanitize
  before rendering (e.g. reject `javascript:` URLs) and rebuild platform URLs
  from handles rather than trusting stored strings.
- **Dependencies are exact.** Every committed Git dependency uses a full
  40-character commit SHA. Committed manifests contain no `main`, `master`, or
  local-path dependency.
- **Packages are immutable.** No extension relies on an upgrade path. A future
  incompatible data model ships as a new package with an explicit migration.
- **State-attaching tests always include the wrong cap.** Every state-attaching
  extension has an `expected_failure` test proving another party's
  `PartyAdminCap` aborts (`EUnauthorized` at `partyos::party`). This does not
  apply to the pure payload packages, which never access a Party or cap.

## Published metadata

Every package's retained `Published.toml` records a prior immutable Testnet
generation. Where the pending source or dependency inputs differ, that block is
historical metadata—not an identity for the pending bytecode. A fresh immutable
stack publication uses the admin CLI with `--allow-republish`; it replaces only
the target network block, and only after the transaction is confirmed
successful.

## Build & test

Each package is independent. From a package directory:

```bash
sui move build
sui move test
```
