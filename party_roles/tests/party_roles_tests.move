// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_roles::party_roles_tests;

use partyos::party;
use party_roles::party_roles as roles;
use std::unit_test::{assert_eq, destroy};
use sui::bcs;
use sui::event;
use sui::test_scenario::{Self as ts};

// Mirrors `party::EUnauthorized` (party.move) for the wrong-cap abort test.
const EUnauthorized: u64 = 0;
const OWNER: address = @0xA;

fun bytes_of_len(len: u64, seed: u8): vector<u8> {
    let mut bytes = vector[];
    if (len > 0) {
        bytes.push_back(seed);
        (len - 1).do!(|_| bytes.push_back(65));
    };
    bytes
}

fun multibyte_bytes(): vector<u8> {
    let mut bytes = vector[];
    30u64.do!(|_| {
        bytes.push_back(0xc3);
        bytes.push_back(0xa9);
    });
    bytes
}

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    {
        let clock = sui::clock::create_for_testing(ctx);
        let (p, cap) = party::new(party::new_individual_kind(), b"Test Artist".to_string(), &clock, ctx);
        clock.destroy_for_testing();
        (p, cap)
    }
}

#[test]
fun add_remove_and_query() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);

    assert!(!roles::has_roles(&p));
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::custom(b"Visual Artist".to_string()));

    assert!(roles::has_roles(&p));
    assert!(roles::has_role(&p, roles::artist()));
    assert!(roles::has_role(&p, roles::producer()));
    assert!(!roles::has_role(&p, roles::dj()));
    assert_eq!(roles::roles(&p).length(), 3);
    // The canonical name maps to a stable token; DJ is uppercased.
    assert_eq!(roles::dj().name(), b"DJ".to_string());
    assert_eq!(roles::custom(b"Visual Artist".to_string()).name(), b"Visual Artist".to_string());

    roles::remove_role(&mut p, &cap, roles::producer());
    assert!(!roles::has_role(&p, roles::producer()));
    assert_eq!(roles::roles(&p).length(), 2);

    // Removing the last roles reclaims the field — no empty set lingers.
    roles::remove_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &cap, roles::custom(b"Visual Artist".to_string()));
    assert!(!roles::has_roles(&p));

    roles::add_role(&mut p, &cap, roles::band());
    roles::clear_roles(&mut p, &cap);
    assert!(!roles::has_roles(&p));
    roles::clear_roles(&mut p, &cap); // no-op when absent

    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_roles_workflow() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    party::share(p, &cap, scenario.ctx());
    transfer::public_transfer(cap, OWNER);

    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    roles::add_role(&mut p, &cap, roles::composer());
    ts::return_shared(p);
    scenario.return_to_sender(cap);

    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert!(roles::has_role(&p, roles::composer()));
    ts::return_shared(p);
    scenario.end();
}

#[test, expected_failure(abort_code = 0, location = party_roles::party_roles)] // EEmptyCustomName
fun rejects_empty_custom() {
    let _ = roles::custom(b"".to_string());
    abort
}

#[test, expected_failure(abort_code = 1, location = party_roles::party_roles)] // ECustomNameTooLong
fun rejects_overlong_custom() {
    let name = vector::tabulate!(61, |_| 97u8).to_string();
    let _ = roles::custom(name);
    abort
}

#[test, expected_failure(abort_code = 0, location = typed_set::typed_set)] // EDuplicateItem
fun rejects_duplicate() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = 1, location = typed_set::typed_set)] // EItemNotPresent
fun remove_absent_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &cap, roles::dj()); // not held
    abort
}

#[test, expected_failure(abort_code = 2, location = typed_set::typed_set)] // EMaxItemsExceeded
fun rejects_over_max() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    // 8 canonical roles + customs until the 13th trips MAX_ROLES (12).
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::dj());
    roles::add_role(&mut p, &cap, roles::composer());
    roles::add_role(&mut p, &cap, roles::songwriter());
    roles::add_role(&mut p, &cap, roles::band());
    roles::add_role(&mut p, &cap, roles::label());
    roles::add_role(&mut p, &cap, roles::collective());
    5u64.do!(|i| roles::add_role(&mut p, &cap, roles::custom(std::string::utf8(vector[((65 + i) as u8)]))));
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun add_role_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);

    // A cap for a different party must not authorize writes to `p`.
    roles::add_role(&mut p, &other_cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun add_role_with_wrong_cap_on_full_set_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);

    // Fill `p`'s role set to MAX_ROLES (12): the 8 canonical roles + 4
    // customs. A capacity check, if it ran before authorization, would also
    // abort here — proving the cap-gate really does run first, not just
    // when there's room to add.
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::dj());
    roles::add_role(&mut p, &cap, roles::composer());
    roles::add_role(&mut p, &cap, roles::songwriter());
    roles::add_role(&mut p, &cap, roles::band());
    roles::add_role(&mut p, &cap, roles::label());
    roles::add_role(&mut p, &cap, roles::collective());
    4u64.do!(|i| roles::add_role(&mut p, &cap, roles::custom(std::string::utf8(vector[((65 + i) as u8)]))));

    // A cap for a different party must abort on authorization, not capacity.
    roles::add_role(&mut p, &other_cap, roles::custom(std::string::utf8(vector[((65 + 4u64) as u8)])));
    abort
}

#[test]
fun event_role_kind_name_mapping_and_custom_identity() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    let role_values = vector[
        roles::artist(),
        roles::producer(),
        roles::dj(),
        roles::composer(),
        roles::songwriter(),
        roles::band(),
        roles::label(),
        roles::collective(),
        roles::custom(b"Artist".to_string()),
    ];
    let expected_kinds = vector[0u8, 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8];
    let expected_names = vector[
        b"Artist",
        b"Producer",
        b"DJ",
        b"Composer",
        b"Songwriter",
        b"Band",
        b"Label",
        b"Collective",
        b"Artist",
    ];
    9u64.do!(|i| roles::add_role(&mut p, &cap, *role_values.borrow(i)));

    assert_eq!(roles::roles(&p).length(), 9);
    assert!(roles::has_role(&p, roles::artist()));
    assert!(roles::has_role(&p, roles::custom(b"Artist".to_string())));

    let added = event::events_by_type<roles::RoleAddedEvent>();
    assert_eq!(added.length(), 9);
    9u64.do!(|i| {
        let (event_party_id, event_cap_id, kind, name, before, after) =
            roles::added_event_fields(&added[i]);
        assert_eq!(event_party_id, party_id);
        assert_eq!(event_cap_id, admin_cap_id);
        assert_eq!(kind, *expected_kinds.borrow(i));
        assert_eq!(name, *expected_names.borrow(i));
        assert_eq!(before, i);
        assert_eq!(after, i + 1);
    });

    destroy(p);
    destroy(cap);
}

#[test]
fun middle_and_final_remove_events_snapshot_counts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    roles::add_role(&mut p, &cap, roles::artist());
    roles::add_role(&mut p, &cap, roles::producer());
    roles::add_role(&mut p, &cap, roles::dj());

    roles::remove_role(&mut p, &cap, roles::producer());
    let removed = event::events_by_type<roles::RoleRemovedEvent>();
    assert_eq!(removed.length(), 1);
    let (event_party_id, event_cap_id, kind, name, before, after) =
        roles::removed_event_fields(&removed[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(kind, 1u8);
    assert_eq!(name, b"Producer");
    assert_eq!(before, 3);
    assert_eq!(after, 2);

    roles::remove_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &cap, roles::dj());
    assert!(!roles::has_roles(&p));
    let removed = event::events_by_type<roles::RoleRemovedEvent>();
    let (_, _, kind, name, before, after) = roles::removed_event_fields(&removed[2]);
    assert_eq!(kind, 2u8);
    assert_eq!(name, b"DJ");
    assert_eq!(before, 1);
    assert_eq!(after, 0);

    destroy(p);
    destroy(cap);
}

#[test]
fun clear_twelve_max_custom_names_has_constant_size() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    12u64.do!(|i| {
        let name = bytes_of_len(60, (65 + i) as u8);
        roles::add_role(&mut p, &cap, roles::custom(name.to_string()));
    });
    roles::clear_roles(&mut p, &cap);

    let cleared = event::events_by_type<roles::RolesClearedEvent>();
    assert_eq!(cleared.length(), 1);
    assert_eq!(bcs::to_bytes(&cleared[0]).length(), 80);
    let (event_party_id, event_cap_id, before, after) =
        roles::cleared_event_fields(&cleared[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(before, 12);
    assert_eq!(after, 0);
    assert!(!roles::has_roles(&p));

    destroy(p);
    destroy(cap);
}

#[test]
fun multibyte_sixty_byte_name_is_bounded_and_event_is_142_bytes() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let name = multibyte_bytes();
    roles::add_role(&mut p, &cap, roles::custom(name.to_string()));
    let added = event::events_by_type<roles::RoleAddedEvent>();
    assert_eq!(added.length(), 1);
    assert_eq!(bcs::to_bytes(&added[0]).length(), 142);
    let (_, _, kind, event_name, before, after) = roles::added_event_fields(&added[0]);
    assert_eq!(kind, 8u8);
    assert_eq!(event_name, name);
    assert_eq!(before, 0);
    assert_eq!(after, 1);

    roles::remove_role(&mut p, &cap, roles::custom(name.to_string()));
    let removed = event::events_by_type<roles::RoleRemovedEvent>();
    assert_eq!(bcs::to_bytes(&removed[0]).length(), 142);
    assert!(!roles::has_roles(&p));
    destroy(p);
    destroy(cap);
}

#[test]
fun constructors_and_views_are_silent() {
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    let before = event::num_events();

    let artist = roles::artist();
    let producer = roles::producer();
    let dj = roles::dj();
    let composer = roles::composer();
    let songwriter = roles::songwriter();
    let band = roles::band();
    let label = roles::label();
    let collective = roles::collective();
    let custom = roles::custom(b"Custom".to_string());
    assert_eq!(artist.name(), b"Artist".to_string());
    assert_eq!(producer.name(), b"Producer".to_string());
    assert_eq!(dj.name(), b"DJ".to_string());
    assert_eq!(composer.name(), b"Composer".to_string());
    assert_eq!(songwriter.name(), b"Songwriter".to_string());
    assert_eq!(band.name(), b"Band".to_string());
    assert_eq!(label.name(), b"Label".to_string());
    assert_eq!(collective.name(), b"Collective".to_string());
    assert_eq!(custom.name(), b"Custom".to_string());
    assert_eq!(event::num_events(), before);

    assert!(!roles::has_roles(&p));
    assert!(!roles::has_role(&p, artist));
    assert!(roles::roles(&p).is_empty());
    assert_eq!(event::num_events(), before);
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_repeated_and_readd_events_start_from_zero() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    roles::add_role(&mut p, &cap, roles::artist());
    roles::clear_roles(&mut p, &cap);
    roles::clear_roles(&mut p, &cap);
    roles::add_role(&mut p, &cap, roles::custom(b"Readded".to_string()));
    let added = event::events_by_type<roles::RoleAddedEvent>();
    assert_eq!(added.length(), 2);
    let (_, _, kind, name, before, after) = roles::added_event_fields(&added[1]);
    assert_eq!(kind, 8u8);
    assert_eq!(name, b"Readded");
    assert_eq!(before, 0);
    assert_eq!(after, 1);
    let cleared = event::events_by_type<roles::RolesClearedEvent>();
    assert_eq!(cleared.length(), 1);
    let (event_party_id, event_cap_id, before, after) =
        roles::cleared_event_fields(&cleared[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(before, 1);
    assert_eq!(after, 0);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = 0, location = typed_set::typed_set)] // EDuplicateItem must beat capacity.
fun authorized_duplicate_on_full_set_aborts_as_duplicate() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    12u64.do!(|i| roles::add_role(&mut p, &cap, roles::custom(bytes_of_len(1, (65 + i) as u8).to_string())));
    roles::add_role(&mut p, &cap, roles::custom(b"A".to_string()));
    abort
}

#[test, expected_failure(abort_code = 1, location = typed_set::typed_set)] // EItemNotPresent
fun remove_from_missing_field_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    roles::remove_role(&mut p, &cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun remove_with_wrong_cap_and_present_role_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &other_cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun remove_with_wrong_cap_and_missing_role_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::remove_role(&mut p, &other_cap, roles::dj());
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun remove_with_wrong_cap_and_missing_field_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::remove_role(&mut p, &other_cap, roles::artist());
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_with_wrong_cap_and_populated_set_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::add_role(&mut p, &cap, roles::artist());
    roles::clear_roles(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_with_wrong_cap_and_absent_set_aborts_as_unauthorized() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    roles::clear_roles(&mut p, &other_cap);
    abort
}
