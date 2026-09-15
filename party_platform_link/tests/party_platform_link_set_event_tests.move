// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_platform_link::party_platform_link_set_event_tests;

use partyos::party;
use party_platform_link::party_platform_link as links;
use party_social::party_social::{Self as social, XData};
use platform_link::platform_link as primitive;
use std::unit_test::{assert_eq, destroy};
use sui::event;

fun new_party(ctx: &mut TxContext): (party::Party, party::PartyAdminCap) {
    {
        let clock = sui::clock::create_for_testing(ctx);
        let (p, cap) = party::new(party::new_individual_kind(), b"Test Artist".to_string(), &clock, ctx);
        clock.destroy_for_testing();
        (p, cap)
    }
}

#[test]
fun insert_different_and_equal_replace_events() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let parent_id = object::id(&p).to_address();
    let first = social::x(b"first".to_string());
    let second = social::x(b"second".to_string());

    // Absent clear, absent view, and all legacy streams are silent.
    let before = event::num_events();
    links::clear_link<XData>(&mut p, &cap);
    assert_eq!(event::num_events(), before);
    assert!(!links::has_link<XData>(&p));
    assert!(links::link<XData>(&p).is_none());
    assert_eq!(event::num_events(), before);
    assert_eq!(event::events_by_type<primitive::PlatformLinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<primitive::PlatformLinkRemovedEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);

    links::set_link(&mut p, &cap, first);
    assert_eq!(event::num_events(), before + 1);
    let sets = event::events_by_type<primitive::PlatformLinkSetEvent<XData>>();
    assert_eq!(sets.length(), 1);
    assert_eq!(primitive::set_event_parent_id(&sets[0]), parent_id);
    assert!(!primitive::set_event_existed_before(&sets[0]));
    assert!(primitive::set_event_exists_after(&sets[0]));
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);

    links::set_link(&mut p, &cap, second);
    assert_eq!(event::num_events(), before + 2);
    let sets = event::events_by_type<primitive::PlatformLinkSetEvent<XData>>();
    assert_eq!(sets.length(), 2);
    assert_eq!(primitive::set_event_parent_id(&sets[1]), parent_id);
    assert!(primitive::set_event_existed_before(&sets[1]));
    assert!(primitive::set_event_exists_after(&sets[1]));

    links::set_link(&mut p, &cap, social::x(b"second".to_string()));
    // Equal replacement still writes the complete value but emits no event.
    assert_eq!(event::num_events(), before + 2);
    let sets = event::events_by_type<primitive::PlatformLinkSetEvent<XData>>();
    assert_eq!(sets.length(), 2);
    assert_eq!(links::link<XData>(&p).destroy_some().data().handle(), b"second".to_string());
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);

    links::clear_link<XData>(&mut p, &cap);
    destroy(p);
    destroy(cap);
}
