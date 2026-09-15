// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_platform_link::party_platform_link_clear_event_tests;

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
fun present_clear_event_and_absent_repeat_are_precise() {
    let ctx = &mut tx_context::dummy();
    let (mut p, cap) = new_party(ctx);
    let parent_id = object::id(&p).to_address();

    let before = event::num_events();
    links::clear_link<XData>(&mut p, &cap);
    assert_eq!(event::num_events(), before);
    assert_eq!(event::events_by_type<primitive::PlatformLinkRemovedEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);

    let link = social::x(b"second".to_string());
    links::set_link(&mut p, &cap, link);
    let set_count = event::events_by_type<primitive::PlatformLinkSetEvent<XData>>().length();
    assert_eq!(set_count, 1);

    let before = event::num_events();
    links::clear_link<XData>(&mut p, &cap);
    assert_eq!(event::num_events(), before + 1);
    assert!(!links::has_link<XData>(&p));
    let removed = event::events_by_type<primitive::PlatformLinkRemovedEvent<XData>>();
    assert_eq!(removed.length(), 1);
    assert_eq!(primitive::removed_event_parent_id(&removed[0]), parent_id);
    assert!(primitive::removed_event_existed_before(&removed[0]));
    assert!(!primitive::removed_event_exists_after(&removed[0]));
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);

    let before = event::num_events();
    links::clear_link<XData>(&mut p, &cap);
    assert_eq!(event::num_events(), before);
    assert!(links::link<XData>(&p).is_none());
    assert_eq!(event::events_by_type<primitive::PlatformLinkSetEvent<XData>>().length(), set_count);
    assert_eq!(event::events_by_type<primitive::PlatformLinkRemovedEvent<XData>>().length(), 1);
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);

    destroy(p);
    destroy(cap);
}
