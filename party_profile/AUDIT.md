# Release Audit — `party_profile`

**Repository:** `https://github.com/misofm/partyos-extensions`
**Audit target:** pending working-tree source on `codex/rich-events`
**Date:** 2026-09-11
**Toolchain:** `sui 1.79.0`

## Verdict

Release-ready. No security or correctness findings remain.

## Implementation reviewed

`party_profile` is a state-attaching extension. It stores one replace-whole
Profile dynamic field: required short bio (1–300 bytes), optional long bio
(1–8192 bytes), optional validated country code, and up to 10 distinct
validated language codes. Optional long-bio validation uses `Option::do_ref!`
with direct named numeric error constants; no caller-selected abort code remains.
Set and clear require the matching `PartyAdminCap`; views are permissionless.
Changed set events carry address-based party/cap ids plus complete
previous/current profile snapshots as raw UTF-8 bytes; equal replacements still
write but are silent. Clear events carry the complete removed snapshot and
absent clears are silent. Initial previous values use empty/none sentinels.

## Exact manifest pins

| Dependency | Repository | Revision |
|---|---|---|
| `partyos` | `https://github.com/misofm/partyos.git` | `c23df9018e15a76395c65bc8dfca4b365140aa12` |
| `country_code` | `https://github.com/unconfirmedlabs/country_code.git` | `b4c92cb7f772879335344d7b6499b5fa4eafef56` |
| `language_code` | `https://github.com/unconfirmedlabs/language_code.git` | `61542357f3d2ff989d120185046def7cf6c8bdcb` |

The manifest has no local-path or floating dependencies.

## Verification

- Package tests: **23/23**, including the retained validation and shared-party
  coverage plus complete initial/replacement/clear snapshots, equal-write
  silence, absent-clear silence, multibyte/order preservation, maximum BCS
  sizes, view silence, validation precedence, and wrong-cap set/clear paths.
- Production instruction coverage: **100.00%**.
- End-to-end scenario covers Party share, cap transfer, later profile write,
  and permissionless read from the shared Party.
- Strict fresh-copy lint builds with warnings as errors pass for both Testnet
  and Mainnet. Production instruction coverage is **100.00%** on both
  environments.

## Published metadata

The retained `Published.toml` is the sole record of the prior immutable Testnet package id;
it is not repeated here.
Its bytecode predates the pending rich-event source changes. Fresh immutable
publication uses the admin CLI with `--allow-republish`; only after confirmed
success may it replace the target network block.
