# Release Audit — `party_cta`

**Repository:** `https://github.com/misofm/partyos-extensions`
**Audit target:** `party_cta` source at implementation commit `5567df3`
**Date:** 2026-09-11
**Toolchain:** `sui 1.79.0-46f18562f1f5`

## Verdict

Release-ready. No security or correctness findings remain.

## Implementation reviewed

`party_cta` is a state-attaching extension. It stores one ordered,
replace-whole `vector<Cta>` dynamic field on a Party. Labels are 1–60 bytes,
URLs are 1–2000 bytes, and the list is capped at 20. `set_ctas` and
`clear_ctas` require the matching `PartyAdminCap`; views are permissionless.
Set and clear events include primitive party/capability addresses plus complete
ordered prior/resulting CTA bytes, and an absent clear is silent. The module
contains no funds or automation entrypoints.

## Exact manifest pins

| Dependency | Repository | Revision |
|---|---|---|
| `partyos` | `https://github.com/misofm/partyos.git` | `c23df9018e15a76395c65bc8dfca4b365140aa12` |

The manifest has no local-path or floating dependencies.

## Verification

- Verified Testnet package tests: **18/18**, including expected-failure paths covering all four
  CTA validators, list capacity ordering, equal-write silence, component
  changes, and wrong-cap set/replace/clear authorization.
- Strict Testnet and Mainnet lint builds passed with warnings as errors.
- Production instruction coverage: **255/255 instructions (100.00%)**.
- End-to-end scenario: Party creation and share, cap transfer, later cap-gated
  write to the shared Party, and permissionless read in another transaction.
- Historical repository aggregate (not this package review): **77/77 tests on
  Testnet and 77/77 on Mainnet**, with all 11 production modules at
  **100.00%**.
- Historical fresh-unpublished-copy strict-build claim (not re-run for this
  review): fresh copies built strictly for both networks.

## Published metadata

The retained `Published.toml` is the sole record of the prior immutable Testnet package id;
it is not repeated here.
It predates pending source wherever inputs differ. Fresh immutable publication
uses the admin CLI with `--allow-republish`; only a confirmed successful
transaction may replace the target network block.
