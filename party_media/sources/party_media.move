// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Profile imagery for a party, stored as a single Walrus quilt.
///
/// All of a party's images (avatar, header/cover, …) live together in one Walrus
/// quilt — batching them under a single storage reservation is markedly cheaper
/// than one blob each, which matters when the platform sponsors storage. Only the
/// quilt's blob id is held on-chain, as a `Media` dynamic field on the party's
/// UID, gated by the `PartyAdminCap`; views are permissionless.
///
/// The chain is deliberately role-agnostic: which patch is the avatar vs the
/// header is a client convention (quilt patch *identifiers*, e.g. "avatar" /
/// "header"), derived off-chain — never stored here. Updating any image means
/// re-storing the quilt and calling `set_media` with the new id.
/// Each changed set emits the prior/resulting quilt ids and the authorizing cap
/// address; equal replacements still write but do not emit. A clear emits the
/// removed id only when a field existed. All writes are cap-gated through
/// `party::uid_mut`, and views are permissionless.
module party_media::party_media;

use partyos::party::{Party, PartyAdminCap};
use sui::dynamic_field as df;
use sui::event::emit;

// === Keys ===

/// Dynamic-field key for a party's media.
public struct MediaKey() has copy, drop, store;

// === Errors ===

/// The quilt id was zero. Zero is never a real Walrus blob id — almost
/// certainly a caller bug, and indistinguishable from "unset" downstream.
const EZeroQuilt: u64 = 0;

// === Types ===

/// A party's imagery. Held as a dynamic-field value.
public struct Media has store, drop {
    /// Walrus quilt blob id holding all of the party's images. Individual images
    /// are quilt patches addressed by identifier ("avatar", "header", …); those
    /// roles are a client convention, derived off-chain, not stored here.
    quilt: u256,
}

// === Events ===

/// Emitted when a party's media quilt is set or replaced. The event carries
/// the authorizing cap address and both the prior and resulting quilt ids so
/// an indexer can reconcile the mutation without re-reading the field
/// (dynamic-field mutations are not otherwise observable). On an insert,
/// `existed_before` is false and `previous_quilt` is the zero sentinel.
public struct MediaSetEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    existed_before: bool,
    previous_quilt: u256,
    quilt: u256,
}

/// Emitted when a party's media is removed. No event is emitted when the
/// field is absent. The event carries the authorizing cap address and the
/// quilt id that was removed.
public struct MediaClearedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    previous_quilt: u256,
}

// === Write API ===

/// Sets (or replaces) the party's media quilt. Aborts on a zero id before
/// authorization. Every successful call performs the requested insert or
/// replacement. An event is emitted only when the quilt id changes; an initial
/// nonzero attachment always emits.
public fun set_media(self: &mut Party, cap: &PartyAdminCap, quilt: u256) {
    assert!(quilt != 0, EZeroQuilt);
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let uid = self.uid_mut(cap);

    let existed_before = df::exists(uid, MediaKey());
    let mut previous_quilt = 0;
    if (existed_before) {
        previous_quilt = df::borrow<MediaKey, Media>(uid, MediaKey()).quilt;
        df::borrow_mut<MediaKey, Media>(uid, MediaKey()).quilt = quilt;
    } else {
        df::add(uid, MediaKey(), Media { quilt });
    };
    if (!existed_before || previous_quilt != quilt) {
        emit(MediaSetEvent {
            party_id,
            admin_cap_id,
            existed_before,
            previous_quilt,
            quilt,
        });
    };
}

/// Removes the party's media. Authorization happens before checking
/// existence; an absent field is a silent no-op, while an existing field
/// emits exactly one event containing the removed quilt id.
public fun clear_media(self: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let uid = self.uid_mut(cap);
    if (df::exists(uid, MediaKey())) {
        let Media { quilt: previous_quilt } = df::remove(uid, MediaKey());
        emit(MediaClearedEvent {
            party_id,
            admin_cap_id,
            previous_quilt,
        });
    }
}

// === Views ===

/// Whether the party has media set.
public fun has_media(self: &Party): bool {
    df::exists(self.uid(), MediaKey())
}

/// The party's media quilt id, if set.
public fun quilt(self: &Party): Option<u256> {
    if (!df::exists(self.uid(), MediaKey())) return option::none();
    option::some(df::borrow<MediaKey, Media>(self.uid(), MediaKey()).quilt)
}

// === Test Functions ===

/// Test-only accessor for every `MediaSetEvent` field, in declaration order.
#[test_only]
public fun set_event_fields(
    event: &MediaSetEvent,
): (address, address, bool, u256, u256) {
    (
        event.party_id,
        event.admin_cap_id,
        event.existed_before,
        event.previous_quilt,
        event.quilt,
    )
}

/// Test-only accessor for every `MediaClearedEvent` field, in declaration
/// order.
#[test_only]
public fun cleared_event_fields(
    event: &MediaClearedEvent,
): (address, address, u256) {
    (
        event.party_id,
        event.admin_cap_id,
        event.previous_quilt,
    )
}
