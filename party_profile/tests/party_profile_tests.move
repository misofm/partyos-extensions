// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_profile::party_profile_tests;

use country_code::country_code as cc;
use language_code::language_code as lc;
use partyos::party;
use party_profile::party_profile as profile;
use std::unit_test::{assert_eq, destroy};
use sui::bcs;
use sui::event;
use sui::test_scenario::{Self as ts};

// Mirrors `party::EUnauthorized` (party.move) for the wrong-cap abort test.
const EUnauthorized: u64 = 0;
const OWNER: address = @0xA;

/// A string of `len` 'A' bytes, for exercising the length bounds.
fun long_string(len: u64): std::string::String {
    let mut s = vector<u8>[];
    len.do!(|_| s.push_back(65));
    s.to_string()
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
fun set_and_read_full_profile() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();

    assert!(!profile::has_profile(&p));
    profile::set_profile(
        &mut p,
        &cap,
        b"Short bio.".to_string(),
        option::some(b"A much longer biography.".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string()), lc::new(b"ja".to_string())],
    );

    let events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(events.length(), 1);
    let (
        event_party_id,
        event_cap_id,
        had_profile,
        previous_bio_short,
        previous_bio_long,
        previous_country,
        previous_languages,
        bio_short,
        bio_long,
        country,
        languages,
    ) = profile::set_event_fields(&events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert!(!had_profile);
    assert_eq!(previous_bio_short, vector[]);
    assert_eq!(previous_bio_long, option::none());
    assert_eq!(previous_country, option::none());
    assert_eq!(previous_languages, vector[]);
    assert_eq!(bio_short, b"Short bio.");
    assert_eq!(bio_long, option::some(b"A much longer biography."));
    assert_eq!(country, option::some(b"JP"));
    assert_eq!(languages, vector[b"en", b"ja"]);

    assert!(profile::has_profile(&p));
    let card = profile::profile(&p);
    assert_eq!(card.bio_short(), b"Short bio.".to_string());
    assert_eq!(card.bio_long(), option::some(b"A much longer biography.".to_string()));
    assert_eq!(card.country().destroy_some().code(), b"JP".to_string());
    assert_eq!(card.languages().length(), 2);

    destroy(p);
    destroy(cap);
}

#[test]
fun replace_profile_in_place() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();

    // Start with every optional field populated, then replace with the
    // minimal valid card. The whole card is replaced, not stacked.
    profile::set_profile(
        &mut p,
        &cap,
        b"first".to_string(),
        option::some(b"long".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string()), lc::new(b"ja".to_string())],
    );
    profile::set_profile(
        &mut p,
        &cap,
        b"second".to_string(),
        option::none(),
        option::none(),
        vector[],
    );

    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(set_events.length(), 2);
    let (
        event_party_id,
        event_cap_id,
        had_profile,
        previous_bio_short,
        previous_bio_long,
        previous_country,
        previous_languages,
        bio_short,
        bio_long,
        country,
        languages,
    ) = profile::set_event_fields(&set_events[1]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert!(had_profile);
    assert_eq!(previous_bio_short, b"first");
    assert_eq!(previous_bio_long, option::some(b"long"));
    assert_eq!(previous_country, option::some(b"JP"));
    assert_eq!(previous_languages, vector[b"en", b"ja"]);
    assert_eq!(bio_short, b"second");
    assert_eq!(bio_long, option::none());
    assert_eq!(country, option::none());
    assert_eq!(languages, vector[]);

    let card = profile::profile(&p);
    assert_eq!(card.bio_short(), b"second".to_string());
    assert_eq!(card.bio_long(), option::none());
    assert!(card.country().is_none());
    assert_eq!(card.languages().length(), 0);

    // An identical replacement is still a write but emits no redundant event.
    profile::set_profile(&mut p, &cap, b"second".to_string(), option::none(), option::none(), vector[]);
    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(set_events.length(), 2);
    assert_eq!(profile::profile(&p).bio_short(), b"second".to_string());

    destroy(p);
    destroy(cap);
}

#[test]
fun each_profile_component_change_emits() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"long".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string())],
    );

    // Keep the earlier fields equal so each later component of the complete
    // comparison is exercised independently.
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"changed long".to_string()),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"en".to_string())],
    );
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"changed long".to_string()),
        option::some(cc::new(b"US".to_string())),
        vector[lc::new(b"en".to_string())],
    );
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"changed long".to_string()),
        option::some(cc::new(b"US".to_string())),
        vector[lc::new(b"ja".to_string())],
    );
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), 4);
    assert_eq!(profile::profile(&p).languages()[0].code(), b"ja".to_string());
    destroy(p);
    destroy(cap);
}

#[test]
fun clear_profile_removes_it() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let party_id = object::id(&p).to_address();
    let admin_cap_id = object::id(&cap).to_address();
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"long".to_string()),
        option::some(cc::new(b"DE".to_string())),
        vector[lc::new(b"de".to_string())],
    );
    profile::clear_profile(&mut p, &cap);
    assert!(!profile::has_profile(&p));

    let cleared_events = event::events_by_type<profile::PartyProfileClearedEvent>();
    assert_eq!(cleared_events.length(), 1);
    let (event_party_id, event_cap_id, previous_bio_short, previous_bio_long,
        previous_country, previous_languages) =
        profile::cleared_event_fields(&cleared_events[0]);
    assert_eq!(event_party_id, party_id);
    assert_eq!(event_cap_id, admin_cap_id);
    assert_eq!(previous_bio_short, b"bio");
    assert_eq!(previous_bio_long, option::some(b"long"));
    assert_eq!(previous_country, option::some(b"DE"));
    assert_eq!(previous_languages, vector[b"de"]);

    // A minimal profile is also a real attached field and its clear carries
    // the exact minimal snapshot.
    profile::set_profile(&mut p, &cap, b"minimal".to_string(), option::none(), option::none(), vector[]);
    profile::clear_profile(&mut p, &cap);
    let cleared_events = event::events_by_type<profile::PartyProfileClearedEvent>();
    assert_eq!(cleared_events.length(), 2);
    let (_, _, previous_bio_short, previous_bio_long, previous_country, previous_languages) =
        profile::cleared_event_fields(&cleared_events[1]);
    assert_eq!(previous_bio_short, b"minimal");
    assert_eq!(previous_bio_long, option::none());
    assert_eq!(previous_country, option::none());
    assert_eq!(previous_languages, vector[]);

    profile::clear_profile(&mut p, &cap); // no-op
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), 2);
    destroy(p);
    destroy(cap);
}

#[test]
fun shared_party_profile_workflow() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    party::share(p, &cap, scenario.ctx());
    transfer::public_transfer(cap, OWNER);

    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    profile::set_profile(
        &mut p,
        &cap,
        b"Shared profile".to_string(),
        option::none(),
        option::none(),
        vector[],
    );
    ts::return_shared(p);
    scenario.return_to_sender(cap);

    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    assert_eq!(profile::profile(&p).bio_short(), b"Shared profile".to_string());
    ts::return_shared(p);
    scenario.end();
}

#[test]
fun event_bytes_preserve_multibyte_values_and_language_order() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let short = vector[0xC3u8, 0xA9u8].to_string(); // é
    let long = vector[0xE2u8, 0x98u8, 0x83u8].to_string(); // ☃
    profile::set_profile(
        &mut p,
        &cap,
        short,
        option::some(long),
        option::some(cc::new(b"JP".to_string())),
        vector[lc::new(b"ja".to_string()), lc::new(b"en".to_string())],
    );

    let events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(events.length(), 1);
    let (_, _, had_profile, previous_bio_short, previous_bio_long, previous_country,
        previous_languages, bio_short, bio_long, country, languages) =
        profile::set_event_fields(&events[0]);
    assert!(!had_profile);
    assert_eq!(previous_bio_short, vector[]);
    assert_eq!(previous_bio_long, option::none());
    assert_eq!(previous_country, option::none());
    assert_eq!(previous_languages, vector[]);
    assert_eq!(bio_short, vector[0xC3u8, 0xA9u8]);
    assert_eq!(bio_long, option::some(vector[0xE2u8, 0x98u8, 0x83u8]));
    assert_eq!(country, option::some(b"JP"));
    assert_eq!(languages, vector[b"ja", b"en"]);

    destroy(p);
    destroy(cap);
}

#[test]
fun maximum_profile_event_sizes_are_stable() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let languages = vector[
        lc::new(b"aa".to_string()), lc::new(b"ab".to_string()),
        lc::new(b"ae".to_string()), lc::new(b"af".to_string()),
        lc::new(b"ak".to_string()), lc::new(b"am".to_string()),
        lc::new(b"an".to_string()), lc::new(b"ar".to_string()),
        lc::new(b"as".to_string()), lc::new(b"av".to_string()),
    ];
    let short = long_string(300);
    let long = long_string(8192);
    profile::set_profile(
        &mut p,
        &cap,
        short,
        option::some(long),
        option::some(cc::new(b"JP".to_string())),
        languages,
    );
    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(bcs::to_bytes(&set_events[0]).length(), 8601);

    let languages = vector[
        lc::new(b"aa".to_string()), lc::new(b"ab".to_string()),
        lc::new(b"ae".to_string()), lc::new(b"af".to_string()),
        lc::new(b"ak".to_string()), lc::new(b"am".to_string()),
        lc::new(b"an".to_string()), lc::new(b"ar".to_string()),
        lc::new(b"as".to_string()), lc::new(b"av".to_string()),
    ];
    profile::set_profile(
        &mut p,
        &cap,
        long_string(300),
        option::some(long_string(8192)),
        option::some(cc::new(b"US".to_string())),
        languages,
    );
    let set_events = event::events_by_type<profile::PartyProfileSetEvent>();
    assert_eq!(bcs::to_bytes(&set_events[1]).length(), 17129);

    profile::clear_profile(&mut p, &cap);
    let cleared_events = event::events_by_type<profile::PartyProfileClearedEvent>();
    assert_eq!(bcs::to_bytes(&cleared_events[0]).length(), 8596);

    destroy(p);
    destroy(cap);
}

#[test]
fun views_are_silent() {
    let before_set = event::events_by_type<profile::PartyProfileSetEvent>().length();
    let before_clear = event::events_by_type<profile::PartyProfileClearedEvent>().length();
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);

    assert!(!profile::has_profile(&p));
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), before_set);
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), before_clear);

    profile::set_profile(&mut p, &cap, b"bio".to_string(), option::none(), option::none(), vector[]);
    let set_count = event::events_by_type<profile::PartyProfileSetEvent>().length();
    let clear_count = event::events_by_type<profile::PartyProfileClearedEvent>().length();
    assert!(profile::has_profile(&p));
    assert_eq!(profile::profile(&p).bio_short(), b"bio".to_string());
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), set_count);
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), clear_count);

    profile::clear_profile(&mut p, &cap);
    let set_count = event::events_by_type<profile::PartyProfileSetEvent>().length();
    let clear_count = event::events_by_type<profile::PartyProfileClearedEvent>().length();
    assert!(!profile::has_profile(&p));
    assert_eq!(event::events_by_type<profile::PartyProfileSetEvent>().length(), set_count);
    assert_eq!(event::events_by_type<profile::PartyProfileClearedEvent>().length(), clear_count);

    destroy(p);
    destroy(cap);
}

/// The bound is inclusive, and it is on bytes rather than characters — 8 KB of
/// bio is stored intact.
#[test]
fun bio_long_at_max_length_is_accepted() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);

    let bio = long_string(8192);
    profile::set_profile(&mut p, &cap, b"bio".to_string(), option::some(bio), option::none(), vector[]);
    assert_eq!(profile::profile(&p).bio_long().destroy_some().as_bytes().length(), 8192);

    destroy(p);
    destroy(cap);
}

#[test, expected_failure(abort_code = profile::EBioLongTooLong)]
fun rejects_bio_long_over_max_length() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    // 8193 bytes — one past the bound.
    let bio = long_string(8193);
    profile::set_profile(&mut p, &cap, b"bio".to_string(), option::some(bio), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = 0, location = party_profile::party_profile)] // EEmptyBioShort
fun rejects_empty_bio_short() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(&mut p, &cap, b"".to_string(), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = 1, location = party_profile::party_profile)] // EBioShortTooLong
fun rejects_bio_short_over_max_length() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(&mut p, &cap, long_string(301), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = 2, location = party_profile::party_profile)] // EEmptyBioLong
fun rejects_empty_bio_long() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &cap,
        b"bio".to_string(),
        option::some(b"".to_string()),
        option::none(),
        vector[],
    );
    abort
}

#[test, expected_failure(abort_code = 5, location = party_profile::party_profile)] // ENoProfile
fun reading_absent_profile_aborts() {
    let ctx = &mut tx_context::dummy();
    let (p, _cap) = new_party(ctx);
    let _ = profile::profile(&p);
    abort
}

#[test, expected_failure(abort_code = 4, location = party_profile::party_profile)] // ETooManyLanguages
fun rejects_too_many_languages() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let langs = vector[
        lc::new(b"en".to_string()), lc::new(b"ja".to_string()), lc::new(b"de".to_string()),
        lc::new(b"fr".to_string()), lc::new(b"es".to_string()), lc::new(b"it".to_string()),
        lc::new(b"pt".to_string()), lc::new(b"ru".to_string()), lc::new(b"zh".to_string()),
        lc::new(b"ko".to_string()), lc::new(b"ar".to_string()),
    ];
    profile::set_profile(&mut p, &cap, b"bio".to_string(), option::none(), option::none(), langs);
    abort
}

#[test, expected_failure(abort_code = 6, location = party_profile::party_profile)] // EDuplicateLanguage
fun rejects_duplicate_languages() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let langs = vector[lc::new(b"en".to_string()), lc::new(b"ja".to_string()), lc::new(b"en".to_string())];
    profile::set_profile(&mut p, &cap, b"bio".to_string(), option::none(), option::none(), langs);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun set_profile_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);

    // A cap for a different party must not authorize writes to `p`.
    profile::set_profile(&mut p, &other_cap, b"bio".to_string(), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun set_profile_replace_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(&mut p, &cap, b"initial".to_string(), option::none(), option::none(), vector[]);
    // Authorization must happen before reading or mutating the existing
    // snapshot.
    profile::set_profile(&mut p, &other_cap, b"replacement".to_string(), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun set_profile_equal_with_wrong_cap_aborts() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(&mut p, &cap, b"initial".to_string(), option::none(), option::none(), vector[]);

    // Equality must not bypass the existing PartyAdminCap authorization.
    profile::set_profile(&mut p, &other_cap, b"initial".to_string(), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_profile_with_wrong_cap_aborts_when_absent() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::clear_profile(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = EUnauthorized, location = partyos::party)]
fun clear_profile_with_wrong_cap_aborts_when_existing() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(&mut p, &cap, b"initial".to_string(), option::none(), option::none(), vector[]);
    profile::clear_profile(&mut p, &other_cap);
    abort
}

#[test, expected_failure(abort_code = profile::EEmptyBioShort)]
fun validation_precedes_wrong_cap_for_empty_short_bio() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    // Validation intentionally remains before `uid_mut`: the caller sees the
    // local validation error even when the cap is unrelated.
    profile::set_profile(&mut p, &other_cap, b"".to_string(), option::none(), option::none(), vector[]);
    abort
}

#[test, expected_failure(abort_code = profile::EEmptyBioLong)]
fun validation_precedes_wrong_cap_for_empty_long_bio() {
    let ctx = &mut tx_context::dummy();
    let (mut p, _cap) = new_party(ctx);
    let (_other, other_cap) = new_party(ctx);
    profile::set_profile(
        &mut p,
        &other_cap,
        b"bio".to_string(),
        option::some(b"".to_string()),
        option::none(),
        vector[],
    );
    abort
}
