# Release Audit — `party_tags`

**Repository:** `https://github.com/misofm/partyos-extensions`
**Audit target:** pending working-tree source on `main` (matches the repository's current `HEAD`)
**Date:** 2026-09-11
**Toolchain:** `sui 1.79.0-46f18562f1f5`

## Verdict

Release-ready. No security or correctness findings remain.

## Implementation reviewed

`party_tags` is a state-attaching extension. It stores up to 30 exact-match
free-form strings through `typed_set`, with each tag constrained to 1–50 bytes.
All mutations require the matching `PartyAdminCap`; final removal reclaims the
field, clear is idempotent, and views are permissionless. Mutation events carry
party/cap addresses, raw tag bytes, and before/after counts; populated clear
events carry the ordered raw tag snapshot. Normalization and rendering safety
remain client concerns.

## Exact manifest pins

| Dependency | Repository | Revision |
|---|---|---|
| `partyos` | `https://github.com/misofm/partyos.git` | `c23df9018e15a76395c65bc8dfca4b365140aa12` |
| `typed_set` | `https://github.com/unconfirmedlabs/typed_set.git` | `b37474cbde166b7ddf8a3b615cd89f90182ace6f` |

The manifest has no local-path or floating dependencies.

## Verification

- Package tests: **23/23**, preserving the original 9 and adding event
  field/count/snapshot, BCS-size, silence, identity, ordering, and
  authorization-order coverage.
- Production instruction coverage: **100.00%**.
- End-to-end scenario covers Party share, cap transfer, later tag write, and
  permissionless read from the shared Party.
- Strict Testnet and Mainnet builds passed with lint warnings as errors; package
  tests passed 23/23 on each network; production instruction coverage was
  100.00%.

## Published metadata

The retained `Published.toml` is the sole record of the prior immutable Testnet package id;
it is not repeated here.
It is prior-generation metadata wherever pending inputs differ. Fresh immutable
publication uses the admin CLI with `--allow-republish`; only after confirmed
success may it replace the target network block.
