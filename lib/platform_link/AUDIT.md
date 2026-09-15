# Release Audit — `platform_link`

**Repository:** `https://github.com/misofm/partyos-extensions`
**Audit target:** pending working-tree source on `codex/rich-events`
**Date:** 2026-09-11
**Toolchain:** `sui 1.79.0`

## Verdict

Release-ready. No security or correctness findings remain.

## Implementation reviewed

`platform_link` is a protocol-agnostic primitive. It wraps a payload as
`PlatformLink<Data>` and stores at most one value per `Data` type under any
caller-supplied `UID`, using the phantom-typed `PlatformLinkKey<Data>`. It
implements set/replace, optional read, borrow, remove, and idempotent clear.
Changed set, remove, and present clear operations emit typed events with parent
and defining-ID-qualified type bytes plus bounded BCS length/Blake2b-256
summaries; equal set replacements still write silently, and full payloads are
never copied into events. It contains no Party, capability,
Vault, Action, plugin, or fund logic; authorization belongs to its caller.
Identifier and URL backstops are exactly 256 and 2000 bytes.

## Dependency provenance

The manifest has no explicit dependency. `Move.lock` resolves the Sui
framework for both Testnet and Mainnet at exact revision
`2a0becb2fcc6989e492981104af67f62f2c9511a`. There are no local-path, branch,
or floating Git dependencies.

## Verification

- Package tests: **9/9**, including **2** expected-failure paths (`borrow` and
  `remove` when absent), exact set/replace/remove and clear event assertions,
  typed parent/type streams, empty payload handling, and a 131072-byte payload
  bounded-summary check.
- Production instruction coverage: **100.00%**.
- Shared-Party workflow: not applicable; this primitive accepts a `UID` and
  owns no host object.
- Repository aggregate: **77/77 tests on Testnet and 77/77 on Mainnet**, strict
  lint with warnings as errors; all 11 production modules are at **100.00%**.
- Fresh copies without `Published.toml` or `Move.lock` build strictly for both
  networks.

## Published metadata

The retained `Published.toml` is the sole record of the prior immutable Testnet package id;
it is not repeated here.
It is historical deployment metadata and does not attest to pending source.
Fresh immutable publication uses the admin CLI with `--allow-republish`; only
after confirmed success may it replace the target network block.
