// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_genre::party_genre_tests;

use genre::genre as g;
use genre::genre::{GenreRegistry, Genre};
use partyos::party;
// Aliased so the bare `party_genre` name stays free for `location = …`.
use party_genre::party_genre as pg;
use std::unit_test::{assert_eq, destroy};
use sui::event;
use sui::test_scenario::{Self as ts, Scenario};

const CREATOR: address = @0xC0;
const MAX_GENRES: u64 = 20;

// Mirrors `party::EUnauthorized` (party.move) for the wrong-cap abort test.
const EUnauthorized: u64 = 0;

// === Helpers ===

/// Creates a genre in the permissionless registry and returns its derived id.
fun create_genre(scenario: &Scenario, name: vector<u8>): ID {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let id = g::derive_address(&registry, name.to_string()).to_id();
    g::new(&mut registry, name.to_string());
    ts::return_shared(registry);
    id
}

/// Mints `count` distinct single-letter vocabulary entries for capacity tests.
fun create_letter_genres(scenario: &Scenario, count: u64): vector<ID> {
    let mut registry = scenario.take_shared<GenreRegistry>();
    let mut ids = vector[];
    count.do!(|i| {
        let name = std::string::utf8(vector[((65 + i) as u8)]);
        ids.push_back(g::derive_address(&registry, name).to_id());
        g::new(&mut registry, name);
    });
    ts::return_shared(registry);
    ids
}

fun fill_genres_from(
    scenario: &Scenario,
    p: &mut party::Party,
    cap: &party::PartyAdminCap,
    ids: &vector<ID>,
    start: u64,
    count: u64,
) {
    count.do!(|offset| {
        let i = start + offset;
        let genre = scenario.take_immutable_by_id<Genre>(*ids.borrow(i));
        pg::add_genre(p, cap, &genre);
        ts::return_immutable(genre);
    });
}

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    {
        let clock = sui::clock::create_for_testing(ctx);
        let (p, cap) = party::new(party::new_individual_kind(), b"Test Artist".to_string(), &clock, ctx);
        clock.destroy_for_testing();
        (p, cap)
    }
}

/// A fresh, unique id that is NOT a real genre (for negative cases).
fun fresh_id(ctx: &mut TxContext): ID {
    let uid = object::new(ctx);
    let id = uid.to_inner();
    uid.delete();
    id
}

fun assert_added_events(id1: ID, id2: ID, id3: ID, party_id: address, admin_cap_id: address) {
    let added = event::events_by_type<pg::GenreAddedEvent>();
    assert_eq!(added.length(), 3);
    let (event_party_id, event_cap_id, event_genre_id, event_name, before, after, max) =
        pg::added_event_fields(&added[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(event_genre_id, id1.to_address());
    assert_eq!(event_name, b"HIP_HOP");
    assert_eq!(before, vector[]);
    assert_eq!(after, vector[id1.to_address()]);
    assert_eq!(max, MAX_GENRES);

    let (event_party_id, event_cap_id, event_genre_id, event_name, before, after, max) =
        pg::added_event_fields(&added[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(event_genre_id, id2.to_address());
    assert_eq!(event_name, b"AMBIENT");
    assert_eq!(before, vector[id1.to_address()]);
    assert_eq!(after, vector[id1.to_address(), id2.to_address()]);
    assert_eq!(max, MAX_GENRES);

    let (event_party_id, event_cap_id, event_genre_id, event_name, before, after, max) =
        pg::added_event_fields(&added[2]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(event_genre_id, id3.to_address());
    assert_eq!(event_name, b"TECHNO");
    assert_eq!(before, vector[id1.to_address(), id2.to_address()]);
    assert_eq!(after, vector[id1.to_address(), id2.to_address(), id3.to_address()]);
    assert_eq!(max, MAX_GENRES);
}

fun assert_middle_removed_event(id1: ID, id2: ID, id3: ID, party_id: address, admin_cap_id: address) {
    let removed = event::events_by_type<pg::GenreRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_party_id, event_cap_id, event_genre_id, before, after) =
        pg::removed_event_fields(&removed[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(event_genre_id, id2.to_address());
    assert_eq!(before, vector[id1.to_address(), id2.to_address(), id3.to_address()]);
    assert_eq!(after, vector[id1.to_address(), id3.to_address()]);
}

fun assert_final_removed_event(id3: ID, party_id: address, admin_cap_id: address) {
    let removed = event::events_by_type<pg::GenreRemovedEvent>();
    assert_eq!(removed.length(), 3);
    let (event_party_id, event_cap_id, event_genre_id, before, after) =
        pg::removed_event_fields(&removed[2]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(event_genre_id, id3.to_address());
    assert_eq!(before, vector[id3.to_address()]);
    assert_eq!(after, vector[]);
}

fun assert_added_event_at(
    event_index: u64,
    expected_count: u64,
    genre_id: ID,
    genre_name: vector<u8>,
    expected_before: vector<address>,
    expected_after: vector<address>,
    party_id: address,
    admin_cap_id: address,
) {
    let added = event::events_by_type<pg::GenreAddedEvent>();
    assert_eq!(added.length(), expected_count);
    let (event_party_id, event_cap_id, event_genre_id, event_name, before, after, max) =
        pg::added_event_fields(&added[event_index]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(event_genre_id, genre_id.to_address());
    assert_eq!(event_name, genre_name);
    assert_eq!(before, expected_before);
    assert_eq!(after, expected_after);
    assert_eq!(max, MAX_GENRES);
}

fun assert_cleared_event_at(
    event_index: u64,
    expected_count: u64,
    expected_before: vector<address>,
    party_id: address,
    admin_cap_id: address,
) {
    let cleared = event::events_by_type<pg::GenresClearedEvent>();
    assert_eq!(cleared.length(), expected_count);
    let (event_party_id, event_cap_id, before, after) =
        pg::cleared_event_fields(&cleared[event_index]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(before, expected_before);
    assert_eq!(after, vector[]);
}

fun assert_full_add_events(ids: &vector<ID>, party_id: address, admin_cap_id: address) {
    let added = event::events_by_type<pg::GenreAddedEvent>();
    assert_eq!(added.length(), MAX_GENRES);
    let mut expected_before = vector[];
    MAX_GENRES.do!(|i| {
        let genre_id = *ids.borrow(i);
        let expected_name = vector[((65 + i) as u8)];
        let expected_after = {
            let mut after = expected_before;
            after.push_back(genre_id.to_address());
            after
        };
        let (event_party_id, event_cap_id, event_genre_id, event_name, before, after, max) =
            pg::added_event_fields(&added[i]);
        assert_eq!(event_party_id, party_id);
        assert_eq!(event_cap_id, admin_cap_id);
        assert_eq!(event_genre_id, genre_id.to_address());
        assert_eq!(event_name, expected_name);
        assert_eq!(before, expected_before);
        assert_eq!(after, expected_after);
        assert_eq!(max, MAX_GENRES);
        expected_before.push_back(genre_id.to_address());
    });
}

fun assert_populated_views_silent(p: &party::Party, expected: vector<ID>) {
    let events_before = event::num_events();
    assert!(pg::has_genres(p));
    assert!(pg::has_genre(p, expected[0]));
    assert_eq!(pg::genres(p), expected);
    assert_eq!(event::num_events(), events_before);
}

// === Tests ===

#[test]
fun add_remove_and_query() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    let id1 = create_genre(&scenario, b"HIP_HOP");
    scenario.next_tx(CREATOR);
    let id2 = create_genre(&scenario, b"AMBIENT");
    scenario.next_tx(CREATOR);
    let id3 = create_genre(&scenario, b"TECHNO");

    scenario.next_tx(CREATOR);
    let genre1 = scenario.take_immutable_by_id<Genre>(id1);
    let genre2 = scenario.take_immutable_by_id<Genre>(id2);
    let genre3 = scenario.take_immutable_by_id<Genre>(id3);
    let (mut p, cap) = new_party(scenario.ctx());
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();

    assert!(!pg::has_genres(&p));
    pg::add_genre(&mut p, &cap, &genre1);
    pg::add_genre(&mut p, &cap, &genre2);
    pg::add_genre(&mut p, &cap, &genre3);

    assert_added_events(id1, id2, id3, party_id, admin_cap_id);

    assert!(pg::has_genres(&p));
    assert!(pg::has_genre(&p, id1));
    assert!(pg::has_genre(&p, id2));
    assert_eq!(pg::genres(&p).length(), 3);

    // Removing a middle entry preserves the insertion order around it.
    pg::remove_genre(&mut p, &cap, id2);
    assert!(pg::has_genre(&p, id1));
    assert!(!pg::has_genre(&p, id2));
    assert_eq!(pg::genres(&p).length(), 2);

    assert_middle_removed_event(id1, id2, id3, party_id, admin_cap_id);

    // Removing the remaining entries eventually reclaims the field — no empty
    // set lingers, and the final removal snapshot is empty afterwards.
    pg::remove_genre(&mut p, &cap, id1);
    pg::remove_genre(&mut p, &cap, id3);
    assert!(!pg::has_genres(&p));
    assert_final_removed_event(id3, party_id, admin_cap_id);

    // Re-adding after field deletion starts a fresh ordered snapshot.
    pg::add_genre(&mut p, &cap, &genre1);
    assert_added_event_at(
        3,
        4,
        id1,
        b"HIP_HOP",
        vector[],
        vector[id1.to_address()],
        party_id,
        admin_cap_id,
    );
    pg::add_genre(&mut p, &cap, &genre2);
    assert_added_event_at(
        4,
        5,
        id2,
        b"AMBIENT",
        vector[id1.to_address()],
        vector[id1.to_address(), id2.to_address()],
        party_id,
        admin_cap_id,
    );
    pg::add_genre(&mut p, &cap, &genre3);
    assert_added_event_at(
        5,
        6,
        id3,
        b"TECHNO",
        vector[id1.to_address(), id2.to_address()],
        vector[id1.to_address(), id2.to_address(), id3.to_address()],
        party_id,
        admin_cap_id,
    );

    // Views over a populated set are silent and preserve complete order.
    assert_populated_views_silent(&p, vector[id1, id2, id3]);

    // A populated clear emits exactly one event with the complete prior order.
    pg::clear_genres(&mut p, &cap);
    assert!(!pg::has_genres(&p));
    assert_cleared_event_at(
        0,
        1,
        vector[id1.to_address(), id2.to_address(), id3.to_address()],
        party_id,
        admin_cap_id,
    );

    // Re-adding after clear emits one complete add event from an empty set.
    pg::add_genre(&mut p, &cap, &genre1);
    assert_added_event_at(
        6,
        7,
        id1,
        b"HIP_HOP",
        vector[],
        vector[id1.to_address()],
        party_id,
        admin_cap_id,
    );
    pg::clear_genres(&mut p, &cap);
    assert_cleared_event_at(1, 2, vector[id1.to_address()], party_id, admin_cap_id);

    // Clearing an absent set (including repeatedly) is authorized but silent.
    let events_before = event::num_events();
    pg::clear_genres(&mut p, &cap);
    pg::clear_genres(&mut p, &cap);
    assert_eq!(event::events_by_type<pg::GenresClearedEvent>().length(), 2);
    assert_eq!(event::num_events(), events_before);

    // Read-only views do not emit events.
    let events_before = event::num_events();
    assert!(!pg::has_genres(&p));
    assert!(!pg::has_genre(&p, id1));
    assert!(pg::genres(&p).is_empty());
    assert_eq!(event::num_events(), events_before);

    ts::return_immutable(genre1);
    ts::return_immutable(genre2);
    ts::return_immutable(genre3);
    destroy(p);
    destroy(cap);
    scenario.end();
}

#[test]
fun shared_party_genre_workflow() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());

    scenario.next_tx(CREATOR);
    let genre_id = create_genre(&scenario, b"HOUSE");

    scenario.next_tx(CREATOR);
    let (p, cap) = new_party(scenario.ctx());
    party::share(p, &cap, scenario.ctx());
    transfer::public_transfer(cap, CREATOR);

    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(genre_id);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    pg::add_genre(&mut p, &cap, &genre);
    let events = event::events_by_type<pg::GenreAddedEvent>();
    assert_eq!(events.length(), 1);
    let (event_party_id, event_cap_id, event_genre_id, event_name, before, after, max) =
        pg::added_event_fields(&events[0]);
    assert_eq!(event_party_id, object::id(&p).to_address());
    assert_eq!(event_cap_id, object::id(&cap).to_address());
    assert_eq!(event_genre_id, genre_id.to_address());
    assert_eq!(event_name, b"HOUSE");
    assert_eq!(before, vector[]);
    assert_eq!(after, vector[genre_id.to_address()]);
    assert_eq!(max, MAX_GENRES);
    ts::return_immutable(genre);
    ts::return_shared(p);
    scenario.return_to_sender(cap);

    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert!(pg::has_genre(&p, genre_id));
    ts::return_shared(p);
    scenario.end();
}

#[test, expected_failure(abort_code = 0, location = typed_set::typed_set)] // EDuplicateItem
fun rejects_duplicate() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");

    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::add_genre(&mut p, &cap, &genre); // duplicate
    abort
}

#[test, expected_failure(abort_code = 0, location = typed_set::typed_set)] // EDuplicateItem takes precedence
fun authorized_duplicate_on_full_set_aborts_as_duplicate() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let ids = create_letter_genres(&scenario, MAX_GENRES + 1);

    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let duplicate = scenario.take_immutable_by_id<Genre>(*ids.borrow(0));
    pg::add_genre(&mut p, &cap, &duplicate);
    fill_genres_from(&scenario, &mut p, &cap, &ids, 1, MAX_GENRES - 1);
    pg::add_genre(&mut p, &cap, &duplicate); // duplicate must beat capacity
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun wrong_cap_duplicate_on_full_set_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let ids = create_letter_genres(&scenario, MAX_GENRES);

    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    let duplicate = scenario.take_immutable_by_id<Genre>(*ids.borrow(0));
    pg::add_genre(&mut p, &cap, &duplicate);
    fill_genres_from(&scenario, &mut p, &cap, &ids, 1, MAX_GENRES - 1);
    pg::add_genre(&mut p, &other_cap, &duplicate); // auth must beat duplicate/capacity
    abort
}

#[test, expected_failure(abort_code = 1, location = typed_set::typed_set)] // EItemNotPresent
fun remove_absent_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");

    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::remove_genre(&mut p, &cap, fresh_id(scenario.ctx())); // a real id, but not tagged
    abort
}

#[test, expected_failure(abort_code = 2, location = typed_set::typed_set)] // EMaxItemsExceeded
fun rejects_over_max() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());

    // Mint MAX_GENRES + 1 distinct genres (single-letter names A, B, …).
    scenario.next_tx(CREATOR);
    let mut ids = vector[];
    {
        let mut registry = scenario.take_shared<GenreRegistry>();
        (MAX_GENRES + 1).do!(|i| {
            let name = std::string::utf8(vector[((65 + i) as u8)]);
            ids.push_back(g::derive_address(&registry, name).to_id());
            g::new(&mut registry, name);
        });
        ts::return_shared(registry);
    };

    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    MAX_GENRES.do!(|i| {
        let genre = scenario.take_immutable_by_id<Genre>(*ids.borrow(i));
        pg::add_genre(&mut p, &cap, &genre);
        ts::return_immutable(genre);
    });
    assert_eq!(pg::genres(&p).length(), MAX_GENRES);
    assert_full_add_events(&ids, party_id, admin_cap_id);
    let last = scenario.take_immutable_by_id<Genre>(*ids.borrow(MAX_GENRES));
    pg::add_genre(&mut p, &cap, &last); // the (MAX_GENRES + 1)-th aborts
    abort
}

#[test, expected_failure(abort_code = 1, location = typed_set::typed_set)] // EItemNotPresent
fun remove_from_missing_field_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    pg::remove_genre(&mut p, &cap, fresh_id(scenario.ctx()));
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun remove_with_wrong_cap_and_present_member_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");

    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::remove_genre(&mut p, &other_cap, id);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun remove_with_wrong_cap_and_missing_member_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");

    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::remove_genre(&mut p, &other_cap, fresh_id(scenario.ctx()));
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun remove_with_wrong_cap_and_missing_field_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let (mut p, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::remove_genre(&mut p, &other_cap, fresh_id(scenario.ctx()));
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_with_wrong_cap_and_populated_set_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");

    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::add_genre(&mut p, &cap, &genre);
    pg::clear_genres(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_with_wrong_cap_and_absent_set_aborts_as_unauthorized() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let (mut p, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());
    pg::clear_genres(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun add_genre_with_wrong_cap_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());
    scenario.next_tx(CREATOR);
    let id = create_genre(&scenario, b"HIP_HOP");

    scenario.next_tx(CREATOR);
    let genre = scenario.take_immutable_by_id<Genre>(id);
    let (mut p, _cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());

    // A cap for a different party must not authorize writes to `p`.
    pg::add_genre(&mut p, &other_cap, &genre);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun add_genre_with_wrong_cap_on_full_set_aborts() {
    let mut scenario = ts::begin(CREATOR);
    g::init_for_testing(scenario.ctx());

    // Mint MAX_GENRES + 1 distinct genres (single-letter names A, B, …).
    scenario.next_tx(CREATOR);
    let mut ids = vector[];
    {
        let mut registry = scenario.take_shared<GenreRegistry>();
        (MAX_GENRES + 1).do!(|i| {
            let name = std::string::utf8(vector[((65 + i) as u8)]);
            ids.push_back(g::derive_address(&registry, name).to_id());
            g::new(&mut registry, name);
        });
        ts::return_shared(registry);
    };

    scenario.next_tx(CREATOR);
    let (mut p, cap) = new_party(scenario.ctx());
    let (_other, other_cap) = new_party(scenario.ctx());

    // Fill `p`'s genre set to MAX_GENRES so a capacity check, if it ran
    // before authorization, would also abort here — proving the cap-gate
    // really does run first, not just when there's room to add.
    MAX_GENRES.do!(|i| {
        let genre = scenario.take_immutable_by_id<Genre>(*ids.borrow(i));
        pg::add_genre(&mut p, &cap, &genre);
        ts::return_immutable(genre);
    });

    // A cap for a different party must abort on authorization, not capacity.
    let last = scenario.take_immutable_by_id<Genre>(*ids.borrow(MAX_GENRES));
    pg::add_genre(&mut p, &other_cap, &last);
    abort
}
