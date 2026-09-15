// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Musical-genre tags for a party, piggybacking the Miso genre vocabulary.
///
/// Stores a set of `genre::Genre` object ids — the same canonical, name-derived
/// genres the shared vocabulary primitive mints, so a party's genres reference
/// exactly the ids releases (and anything else) use. Adding a genre takes a
/// `&Genre`, proving the id is a real vocabulary entry; removal is by id. Genre
/// is presentation, not protocol-verifiable state, so a party's genres are a
/// lightweight display tag list — no primary/secondary ranking, no anti-churn
/// locks. The set mechanics — storage, duplicate and capacity checks, field
/// reclamation — live in the shared `typed_set` primitive; this package keeps
/// the vocabulary proof, the capacity, and the typed events. Duplicate /
/// not-present / over-max aborts come from `typed_set` with its own error
/// codes. All writes are gated by the `PartyAdminCap`; views are
/// permissionless.
module party_genre::party_genre;

use genre::genre::Genre;
use partyos::party::{Party, PartyAdminCap};
use sui::event::emit;
use typed_set::typed_set as set;

// === Constants ===

/// Maximum number of genres a party may carry.
const MAX_GENRES: u64 = 20;

// === Keys ===

/// Dynamic-field key for a party's genre set, stored as a `VecSet<ID>` and
/// managed through `typed_set`.
public struct GenresKey() has copy, drop, store;

// === Events ===

/// Emitted when a genre is added to a party.
public struct GenreAddedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    genre_id: address,
    genre_name: vector<u8>,
    genre_count_before: u64,
    genre_count_after: u64,
    max_genres: u64,
}

/// Emitted when a genre is removed from a party.
public struct GenreRemovedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    genre_id: address,
    genre_count_before: u64,
    genre_count_after: u64,
}

/// Emitted when a party's entire genre set is removed.
public struct GenresClearedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    genre_count_before: u64,
    genre_count_after: u64,
    genre_ids_before: vector<address>,
}

// === Write API ===

/// Adds a genre to the party. Takes `&Genre` so only a real vocabulary entry
/// can be tagged. Aborts in `typed_set` if already present or the max is
/// reached.
public fun add_genre(self: &mut Party, cap: &PartyAdminCap, genre: &Genre) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let genre_id = object::id(genre);
    let genre_id_address = genre_id.to_address();
    let uid = self.uid_mut(cap);
    let genre_count_before = set::keys<GenresKey, ID>(uid, GenresKey()).length();
    set::add(uid, GenresKey(), genre_id, MAX_GENRES);
    let genre_count_after = set::keys<GenresKey, ID>(uid, GenresKey()).length();
    let genre_name = *genre.name().as_bytes();
    emit(GenreAddedEvent {
        party_id,
        admin_cap_id,
        genre_id: genre_id_address,
        genre_name,
        genre_count_before,
        genre_count_after,
        max_genres: MAX_GENRES,
    });
}

/// Removes a genre from the party. Aborts in `typed_set` if not present. The
/// whole field is dropped when the last genre leaves.
public fun remove_genre(self: &mut Party, cap: &PartyAdminCap, genre_id: ID) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let genre_id_address = genre_id.to_address();
    let uid = self.uid_mut(cap);
    let genre_count_before = set::keys<GenresKey, ID>(uid, GenresKey()).length();
    set::remove(uid, GenresKey(), genre_id);
    let genre_count_after = set::keys<GenresKey, ID>(uid, GenresKey()).length();
    emit(GenreRemovedEvent {
        party_id,
        admin_cap_id,
        genre_id: genre_id_address,
        genre_count_before,
        genre_count_after,
    });
}

/// Removes the party's entire genre set. No-op if none is set.
public fun clear_genres(self: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let uid = self.uid_mut(cap);
    if (set::exists(uid, GenresKey())) {
        let genre_count_before = set::keys<GenresKey, ID>(uid, GenresKey()).length();
        let genre_ids_before = set::keys<GenresKey, ID>(uid, GenresKey()).map!(|id: ID| id.to_address());
        set::clear<GenresKey, ID>(uid, GenresKey());
        let genre_count_after = set::keys<GenresKey, ID>(uid, GenresKey()).length();
        emit(GenresClearedEvent {
            genre_ids_before,
            party_id,
            admin_cap_id,
            genre_count_before,
            genre_count_after,
        });
    }
}

// === Views ===

/// Whether the party carries any genres.
public fun has_genres(self: &Party): bool {
    set::exists(self.uid(), GenresKey())
}

/// Whether the party carries the given genre.
public fun has_genre(self: &Party, genre_id: ID): bool {
    set::contains(self.uid(), GenresKey(), &genre_id)
}

/// The party's genre ids.
public fun genres(self: &Party): vector<ID> {
    set::keys(self.uid(), GenresKey())
}

// === Test Functions ===

/// Test-only accessor for every `GenreAddedEvent` field, in declaration order.
#[test_only]
public fun added_event_fields(
    event: &GenreAddedEvent,
): (address, address, address, vector<u8>, u64, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.genre_id,
        event.genre_name,
        event.genre_count_before,
        event.genre_count_after,
        event.max_genres,
    )
}

/// Test-only descriptive alias for `added_event_fields`.
#[test_only]
public fun genre_added_event_fields(
    event: &GenreAddedEvent,
): (address, address, address, vector<u8>, u64, u64, u64) {
    added_event_fields(event)
}

/// Test-only accessor for every `GenreRemovedEvent` field, in declaration order.
#[test_only]
public fun removed_event_fields(
    event: &GenreRemovedEvent,
): (address, address, address, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.genre_id,
        event.genre_count_before,
        event.genre_count_after,
    )
}

/// Test-only descriptive alias for `removed_event_fields`.
#[test_only]
public fun genre_removed_event_fields(
    event: &GenreRemovedEvent,
): (address, address, address, u64, u64) {
    removed_event_fields(event)
}

/// Test-only accessor for every `GenresClearedEvent` field, in declaration order.
#[test_only]
public fun cleared_event_fields(
    event: &GenresClearedEvent,
): (address, address, u64, u64, vector<address>) {
    (
        event.party_id,
        event.admin_cap_id,
        event.genre_count_before,
        event.genre_count_after,
        event.genre_ids_before,
    )
}

/// Test-only descriptive alias for `cleared_event_fields`.
#[test_only]
public fun genres_cleared_event_fields(
    event: &GenresClearedEvent,
): (address, address, u64, u64, vector<address>) {
    cleared_event_fields(event)
}
