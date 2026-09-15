// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_cta::party_cta_tests;

use partyos::party;
use party_cta::party_cta as cta;
use std::unit_test::{assert_eq, destroy};
use sui::event;
use sui::test_scenario::{Self as ts};

// Mirrors `party::EUnauthorized` (party.move) for the wrong-cap abort test.
const EUnauthorized: u64 = 0;
const OWNER: address = @0xA;

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    {
        let clock = sui::clock::create_for_testing(ctx);
        let (p, cap) = party::new(party::new_individual_kind(), b"Test Artist".to_string(), &clock, ctx);
        clock.destroy_for_testing();
        (p, cap)
    }
}

#[test]
fun set_read_replace_clear() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();

    assert!(!cta::has_ctas(&p));
    assert!(cta::ctas(&p).is_empty());

    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Tickets".to_string(), b"https://dice.fm/artist".to_string()),
        cta::new_cta(b"Merch".to_string(), b"https://shop.example/artist".to_string()),
    ]);

    let set_events = event::events_by_type<cta::CtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (
        event_party_id,
        event_cap_id,
        existed_before,
        previous_count,
        count,
        previous_labels,
        previous_urls,
        labels,
        urls,
    ) = cta::set_event_fields(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert!(!existed_before);
    assert_eq!(previous_count, 0);
    assert_eq!(count, 2);
    assert_eq!(previous_labels, vector[]);
    assert_eq!(previous_urls, vector[]);
    assert_eq!(labels, vector[b"Tickets", b"Merch"]);
    assert_eq!(urls, vector[b"https://dice.fm/artist", b"https://shop.example/artist"]);

    assert!(cta::has_ctas(&p));
    let list = cta::ctas(&p);
    assert_eq!(list.length(), 2);
    // Position is priority — order is preserved.
    assert_eq!(list[0].label(), b"Tickets".to_string());
    assert_eq!(list[0].url(), b"https://dice.fm/artist".to_string());
    assert_eq!(list[1].label(), b"Merch".to_string());

    // Replace the whole list.
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Newsletter".to_string(), b"https://substack.com/artist".to_string()),
    ]);
    let set_events = event::events_by_type<cta::CtasSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (
        event_party_id,
        event_cap_id,
        existed_before,
        previous_count,
        count,
        previous_labels,
        previous_urls,
        labels,
        urls,
    ) = cta::set_event_fields(&set_events[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert!(existed_before);
    assert_eq!(previous_count, 2);
    assert_eq!(count, 1);
    assert_eq!(previous_labels, vector[b"Tickets", b"Merch"]);
    assert_eq!(previous_urls, vector[b"https://dice.fm/artist", b"https://shop.example/artist"]);
    assert_eq!(labels, vector[b"Newsletter"]);
    assert_eq!(urls, vector[b"https://substack.com/artist"]);
    assert_eq!(cta::ctas(&p).length(), 1);
    assert_eq!(cta::ctas(&p)[0].label(), b"Newsletter".to_string());

    cta::clear_ctas(&mut p, &cap);
    let cleared_events = event::events_by_type<cta::CtasClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    let (event_party_id, event_cap_id, previous_count, previous_labels, previous_urls) =
        cta::cleared_event_fields(&cleared_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(previous_count, 1);
    assert_eq!(previous_labels, vector[b"Newsletter"]);
    assert_eq!(previous_urls, vector[b"https://substack.com/artist"]);
    assert!(!cta::has_ctas(&p));
    cta::clear_ctas(&mut p, &cap); // no-op
    assert_eq!(event::events_by_type<cta::CtasClearedEvent>().length(), 1);

    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_cta_workflow() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    party::share(p, &cap);
    transfer::public_transfer(cap, OWNER);

    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Tickets".to_string(), b"https://tickets.example".to_string()),
    ]);
    ts::return_shared(p);
    scenario.return_to_sender(cap);

    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert_eq!(cta::ctas(&p)[0].label(), b"Tickets".to_string());
    ts::return_shared(p);
    scenario.end();
}

#[test]
fun stored_empty_and_identical_replacement_have_complete_events() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();

    // An empty vector is still an attached list and emits a set event.
    cta::set_ctas(&mut p, &cap, vector[]);
    assert!(cta::has_ctas(&p));
    let set_events = event::events_by_type<cta::CtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, event_cap_id, existed_before, previous_count, count,
        previous_labels, previous_urls, labels, urls) =
        cta::set_event_fields(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert!(!existed_before);
    assert_eq!(previous_count, 0);
    assert_eq!(count, 0);
    assert_eq!(previous_labels, vector[]);
    assert_eq!(previous_urls, vector[]);
    assert_eq!(labels, vector[]);
    assert_eq!(urls, vector[]);

    // Replacing an attached empty list with an identical empty list still
    // performs the write but emits no redundant replacement event.
    cta::set_ctas(&mut p, &cap, vector[]);
    let set_events = event::events_by_type<cta::CtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    assert!(cta::has_ctas(&p));

    // Clearing the stored empty list emits a clear event with count zero.
    cta::clear_ctas(&mut p, &cap);
    assert!(!cta::has_ctas(&p));
    let cleared_events = event::events_by_type<cta::CtasClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    let (event_party_id, event_cap_id, previous_count, previous_labels, previous_urls) =
        cta::cleared_event_fields(&cleared_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(previous_count, 0);
    assert_eq!(previous_labels, vector[]);
    assert_eq!(previous_urls, vector[]);

    // A second clear is absent-state no-op: it must not emit.
    cta::clear_ctas(&mut p, &cap);
    assert_eq!(event::events_by_type<cta::CtasClearedEvent>().length(), 1);
    destroy(p);
    destroy(cap);
}

#[test]
fun event_bytes_preserve_order_duplicates_and_multibyte_values() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    let first_label = vector[0xC3u8, 0xA9u8].to_string(); // é
    let first_url = vector[0x68u8, 0x74u8, 0x74u8, 0x70u8, 0x73u8, 0x3Au8,
        0x2Fu8, 0x2Fu8, 0xE2u8, 0x98u8, 0x83u8].to_string(); // https://☃
    let duplicate_label = first_label;
    let duplicate_url = first_url;
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(first_label, first_url),
        cta::new_cta(duplicate_label, duplicate_url),
        cta::new_cta(b"Last".to_string(), b"https://last.example".to_string()),
    ]);

    let set_events = event::events_by_type<cta::CtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, event_cap_id, existed_before, previous_count, count,
        previous_labels, previous_urls, labels, urls) =
        cta::set_event_fields(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert!(!existed_before);
    assert_eq!(previous_count, 0);
    assert_eq!(count, 3);
    assert_eq!(previous_labels, vector[]);
    assert_eq!(previous_urls, vector[]);
    assert_eq!(labels, vector[
        vector[0xC3u8, 0xA9u8],
        vector[0xC3u8, 0xA9u8],
        b"Last",
    ]);
    assert_eq!(urls, vector[
        vector[0x68u8, 0x74u8, 0x74u8, 0x70u8, 0x73u8, 0x3Au8, 0x2Fu8, 0x2Fu8,
            0xE2u8, 0x98u8, 0x83u8],
        vector[0x68u8, 0x74u8, 0x74u8, 0x70u8, 0x73u8, 0x3Au8, 0x2Fu8, 0x2Fu8,
            0xE2u8, 0x98u8, 0x83u8],
        b"https://last.example",
    ]);
    let list = cta::ctas(&p);
    assert_eq!(list.length(), 3);
    assert_eq!(list[0].label(), vector[0xC3u8, 0xA9u8].to_string());
    assert_eq!(list[1].label(), vector[0xC3u8, 0xA9u8].to_string());
    assert_eq!(list[2].url(), b"https://last.example".to_string());
    destroy(p);
    destroy(cap);
}

fun max_ctas(): vector<cta::Cta> {
    vector::tabulate!(20, |_| cta::new_cta(
        vector::tabulate!(60, |_| 0x61u8).to_string(),
        vector::tabulate!(2000, |_| 0x62u8).to_string(),
    ))
}

fun max_bytes(): (vector<vector<u8>>, vector<vector<u8>>) {
    (
        vector::tabulate!(20, |_| vector::tabulate!(60, |_| 0x61u8)),
        vector::tabulate!(20, |_| vector::tabulate!(2000, |_| 0x62u8)),
    )
}

#[test]
fun maximum_payload_is_complete_on_set_replace_and_clear() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    let (expected_labels, expected_urls) = max_bytes();

    cta::set_ctas(&mut p, &cap, max_ctas());
    let set_events = event::events_by_type<cta::CtasSetEvent>();
    assert_eq!(set_events.length(), 1);
    let (event_party_id, event_cap_id, existed_before, previous_count, count,
        previous_labels, previous_urls, labels, urls) =
        cta::set_event_fields(&set_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert!(!existed_before);
    assert_eq!(previous_count, 0);
    assert_eq!(count, 20);
    assert_eq!(previous_labels, vector[]);
    assert_eq!(previous_urls, vector[]);
    assert_eq!(labels, expected_labels);
    assert_eq!(urls, expected_urls);

    // Replacing with an identical maximum list keeps the complete value but
    // does not emit a redundant replacement event.
    cta::set_ctas(&mut p, &cap, max_ctas());
    let set_events = event::events_by_type<cta::CtasSetEvent>();
    assert_eq!(set_events.length(), 1);

    cta::clear_ctas(&mut p, &cap);
    let cleared_events = event::events_by_type<cta::CtasClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    let (event_party_id, event_cap_id, previous_count, previous_labels, previous_urls) =
        cta::cleared_event_fields(&cleared_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(previous_count, 20);
    assert_eq!(previous_labels, expected_labels);
    assert_eq!(previous_urls, expected_urls);
    destroy(p);
    destroy(cap);
}

#[test]
fun equal_cta_list_is_silent_but_component_change_emits() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Listen".to_string(), b"https://one.example".to_string()),
    ]);
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Listen".to_string(), b"https://one.example".to_string()),
    ]);
    assert_eq!(event::events_by_type<cta::CtasSetEvent>().length(), 1);

    // The label and count stay equal, but the URL is a real value change.
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Listen".to_string(), b"https://two.example".to_string()),
    ]);
    assert_eq!(event::events_by_type<cta::CtasSetEvent>().length(), 2);
    assert_eq!(cta::ctas(&p)[0].url(), b"https://two.example".to_string());
    destroy(p);
    destroy(cap);
}

#[test]
fun constructors_and_views_emit_no_events() {
    let before_set = event::events_by_type<cta::CtasSetEvent>().length();
    let before_clear = event::events_by_type<cta::CtasClearedEvent>().length();
    let value = cta::new_cta(b"Label".to_string(), b"https://example.com".to_string());
    assert_eq!(value.label(), b"Label".to_string());
    assert_eq!(value.url(), b"https://example.com".to_string());
    let ctx = &mut tx_context::dummy();
    let (p, cap) = new_party(ctx);
    assert!(!cta::has_ctas(&p));
    assert!(cta::ctas(&p).is_empty());
    assert_eq!(event::events_by_type<cta::CtasSetEvent>().length(), before_set);
    assert_eq!(event::events_by_type<cta::CtasClearedEvent>().length(), before_clear);
    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = 0, location = party_cta::party_cta)] // EEmptyLabel
fun rejects_empty_label() {
    let _ = cta::new_cta(b"".to_string(), b"https://x.com".to_string());
    abort
}

#[test, expected_failure(abort_code = 2, location = party_cta::party_cta)] // EEmptyUrl
fun rejects_empty_url() {
    let _ = cta::new_cta(b"Listen".to_string(), b"".to_string());
    abort
}

#[test, expected_failure(abort_code = 1, location = party_cta::party_cta)] // ELabelTooLong
fun rejects_overlong_label() {
    let label = vector::tabulate!(61, |_| 97u8).to_string();
    let _ = cta::new_cta(label, b"https://x.com".to_string());
    abort
}

#[test, expected_failure(abort_code = 3, location = party_cta::party_cta)] // EUrlTooLong
fun rejects_overlong_url() {
    let url = vector::tabulate!(2001, |_| 97u8).to_string();
    let _ = cta::new_cta(b"Listen".to_string(), url);
    abort
}

#[test, expected_failure(abort_code = 4, location = party_cta::party_cta)] // ETooManyCtas
fun rejects_over_max() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let mut list = vector[];
    21u64.do!(|_| list.push_back(cta::new_cta(b"L".to_string(), b"https://x.com".to_string())));
    cta::set_ctas(&mut p, &cap, list);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun set_ctas_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);

    // A cap for a different party must not authorize writes to `p`.
    cta::set_ctas(&mut p, &other_cap, vector[
        cta::new_cta(b"Tickets".to_string(), b"https://dice.fm/artist".to_string()),
    ]);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun set_ctas_replace_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Initial".to_string(), b"https://initial.example".to_string()),
    ]);

    // Replacement must authorize before reading or mutating the existing list.
    cta::set_ctas(&mut p, &other_cap, vector[
        cta::new_cta(b"Replacement".to_string(), b"https://replacement.example".to_string()),
    ]);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun set_ctas_equal_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Initial".to_string(), b"https://initial.example".to_string()),
    ]);

    // Equality must not bypass the existing PartyAdminCap authorization.
    cta::set_ctas(&mut p, &other_cap, vector[
        cta::new_cta(b"Initial".to_string(), b"https://initial.example".to_string()),
    ]);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_ctas_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    cta::set_ctas(&mut p, &cap, vector[
        cta::new_cta(b"Initial".to_string(), b"https://initial.example".to_string()),
    ]);
    cta::clear_ctas(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_absent_ctas_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    // Even an absent clear must reach uid_mut, so a foreign cap cannot turn
    // the idempotent branch into an authorization bypass.
    cta::clear_ctas(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = 4, location = party_cta::party_cta)]
fun over_max_precedes_wrong_cap_authorization() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    let mut list = vector[];
    21u64.do!(|_| list.push_back(cta::new_cta(
        b"L".to_string(),
        b"https://x.com".to_string(),
    )));
    // ETooManyCtas is checked before uid_mut's EUnauthorized check.
    cta::set_ctas(&mut p, &other_cap, list);
    abort
}
