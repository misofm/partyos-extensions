// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_platform_link::party_platform_link_tests;

use partyos::party;
use party_platform_link::party_platform_link as links;
use party_social::party_social::{Self as social, XData, InstagramData};
use platform_link::platform_link as primitive;
use std::unit_test::{assert_eq, destroy};
use sui::event;
use sui::test_scenario::{Self as ts};

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
fun x_and_instagram_events_keep_distinct_parties_and_types() {
    let ctx = &mut tx_context::dummy();
    let (mut x_party, x_cap) = new_party(ctx);
    let (mut instagram_party, instagram_cap) = new_party(ctx);
    let x_parent_id = object::id(&x_party).to_address();
    let instagram_parent_id = object::id(&instagram_party).to_address();
    assert!(x_parent_id != instagram_parent_id);

    let x_link = social::x(b"miso".to_string());
    let instagram_link = social::instagram(b"miso.fm".to_string());

    links::set_link(&mut x_party, &x_cap, x_link);
    links::set_link(&mut instagram_party, &instagram_cap, instagram_link);

    let x_events = event::events_by_type<primitive::PlatformLinkSetEvent<XData>>();
    let instagram_events = event::events_by_type<primitive::PlatformLinkSetEvent<InstagramData>>();
    assert_eq!(x_events.length(), 1);
    assert_eq!(instagram_events.length(), 1);
    assert_eq!(primitive::set_event_parent_id(&x_events[0]), x_parent_id);
    assert_eq!(primitive::set_event_parent_id(&instagram_events[0]), instagram_parent_id);
    assert!(!primitive::set_event_existed_before(&x_events[0]));
    assert!(!primitive::set_event_existed_before(&instagram_events[0]));
    assert!(primitive::set_event_exists_after(&x_events[0]));
    assert!(primitive::set_event_exists_after(&instagram_events[0]));

    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkSetEvent<InstagramData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<InstagramData>>().length(), 0);

    links::clear_link<XData>(&mut x_party, &x_cap);
    links::clear_link<InstagramData>(&mut instagram_party, &instagram_cap);
    let x_removed = event::events_by_type<primitive::PlatformLinkRemovedEvent<XData>>();
    let instagram_removed = event::events_by_type<primitive::PlatformLinkRemovedEvent<InstagramData>>();
    assert_eq!(x_removed.length(), 1);
    assert_eq!(instagram_removed.length(), 1);
    assert_eq!(primitive::removed_event_parent_id(&x_removed[0]), x_parent_id);
    assert_eq!(primitive::removed_event_parent_id(&instagram_removed[0]), instagram_parent_id);
    assert!(primitive::removed_event_existed_before(&x_removed[0]));
    assert!(primitive::removed_event_existed_before(&instagram_removed[0]));
    assert!(!primitive::removed_event_exists_after(&x_removed[0]));
    assert!(!primitive::removed_event_exists_after(&instagram_removed[0]));
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);

    destroy(x_party);
    destroy(x_cap);
    destroy(instagram_party);
    destroy(instagram_cap);
}

#[test]
fun shared_party_cap_holder_and_reader() {
    let mut scenario = ts::begin(OWNER);
    let (p, cap) = new_party(scenario.ctx());
    let parent_id = object::id(&p).to_address();
    party::share(p, &cap, scenario.ctx());
    transfer::public_transfer(cap, OWNER);

    scenario.next_tx(OWNER);
    let mut p = scenario.take_shared<party::Party>();
    let cap = scenario.take_from_sender<party::PartyAdminCap>();
    links::set_link(&mut p, &cap, social::x(b"miso".to_string()));
    let set_events = event::events_by_type<primitive::PlatformLinkSetEvent<XData>>();
    assert_eq!(set_events.length(), 1);
    assert_eq!(primitive::set_event_parent_id(&set_events[0]), parent_id);
    assert!(!primitive::set_event_existed_before(&set_events[0]));
    assert!(primitive::set_event_exists_after(&set_events[0]));
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    ts::return_shared(p);
    scenario.return_to_sender(cap);

    scenario.next_tx(@0xB);
    let p = scenario.take_shared<party::Party>();
    let before = event::num_events();
    assert!(links::has_link<XData>(&p));
    assert_eq!(links::link<XData>(&p).destroy_some().data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), before);
    assert_eq!(event::events_by_type<primitive::PlatformLinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<primitive::PlatformLinkRemovedEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkSetEvent<XData>>().length(), 0);
    assert_eq!(event::events_by_type<links::LinkClearedEvent<XData>>().length(), 0);
    ts::return_shared(p);
    scenario.end();
}
