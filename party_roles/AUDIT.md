# Release Audit — `party_roles`

**Repository:** `https://github.com/misofm/partyos-extensions`
**Audit target:** pending working-tree source on `main` (matches the repository's current `HEAD`)
**Date:** 2026-09-11
**Toolchain:** `sui 1.79.0`

## Verdict

Release-ready. No security or correctness findings remain.

## Implementation reviewed

`party_roles` is a state-attaching extension. It stores up to 12
`ArtistRole` values through `typed_set`: eight closed canonical variants plus a
validated `Custom` name of 1–60 bytes. All mutations require the matching
`PartyAdminCap`; final removal reclaims the field, clear is idempotent, and
views are permissionless. Typed events include the party and cap addresses,
stable role kind/name pairs, and before/after counts; clear snapshots all
removed roles. Exact enum equality deliberately distinguishes a canonical role
from a same-spelled custom role.

## Exact manifest pins

| Dependency | Repository | Revision |
|---|---|---|
| `partyos` | `https://github.com/misofm/partyos.git` | `c23df9018e15a76395c65bc8dfca4b365140aa12` |
| `typed_set` | `https://github.com/unconfirmedlabs/typed_set.git` | `b37474cbde166b7ddf8a3b615cd89f90182ace6f` |

The manifest has no local-path or floating dependencies.

## Verification

- Package tests: **22/22**, including **14** expected-failure paths covering
  both custom-name validators, duplicate/full precedence, missing item,
  capacity, and wrong-cap remove/clear authorization.
- Production instruction coverage: **100.00%**.
- End-to-end scenario covers Party share, cap transfer, later role write, and
  permissionless read from the shared Party.
- Strict Testnet build/test: **22/22** package tests and **100.00%** production
  instruction coverage.
- Strict Mainnet build/test: **22/22** package tests and **100.00%** production
  instruction coverage.

## Published metadata

The retained `Published.toml` is the sole record of the prior immutable Testnet package id;
it is not repeated here.
It is prior-generation metadata wherever pending inputs differ. Fresh immutable
publication uses the admin CLI with `--allow-republish`; only after confirmed
success may it replace the target network block.
