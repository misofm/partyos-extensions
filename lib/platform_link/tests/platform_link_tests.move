// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module platform_link::platform_link_tests;

// Aliased so the bare `platform_link` name stays free for `location = …` below.
use platform_link::platform_link as pl;
use std::bcs;
use std::unit_test::assert_eq;
use sui::event;

/// Stand-in payloads for exercising generic storage and typed event streams.
public struct FooData has copy, drop, store { v: u64 }
public struct BarData has copy, drop, store { v: u64 }
public struct BlobData has copy, drop, store { bytes: vector<u8> }

#[test]
fun wraps_reads_and_limits_are_silent() {
    let link = pl::new(FooData { v: 42 });
    assert_eq!(link.data().v, 42);
    assert_eq!(pl::max_identifier_length(), 256);
    assert_eq!(pl::max_url_length(), 2000);
    assert_eq!(event::num_events(), 0);
}

#[test]
fun set_get_borrow_remove_events_and_reads() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    let parent_id = uid.to_address();
    let first = FooData { v: 1 };
    let second = FooData { v: 2 };

    assert!(!pl::exists_<FooData>(&uid));
    assert!(pl::get<FooData>(&uid).is_none());
    assert_eq!(event::num_events(), 0);

    pl::set(&mut uid, pl::new(first));
    assert!(pl::exists_<FooData>(&uid));
    assert_eq!(pl::borrow<FooData>(&uid).data().v, 1);
    assert_eq!(pl::get<FooData>(&uid).destroy_some().data().v, 1);
    assert_eq!(event::num_events(), 1);

    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<FooData>>();
    let inserted = &set_events[0];
    assert_eq!(pl::set_event_parent_id(inserted), parent_id);
    assert!(!pl::set_event_existed_before(inserted));
    assert!(pl::set_event_exists_after(inserted));

    // Setting again replaces the existing link in place and emits a second
    // event identifying the replacement.
    pl::set(&mut uid, pl::new(second));
    assert_eq!(pl::borrow<FooData>(&uid).data().v, 2);
    assert_eq!(pl::get<FooData>(&uid).destroy_some().data().v, 2);
    assert_eq!(event::num_events(), 2);
    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<FooData>>();
    let replaced = &set_events[1];
    assert_eq!(pl::set_event_parent_id(replaced), parent_id);
    assert!(pl::set_event_existed_before(replaced));
    assert!(pl::set_event_exists_after(replaced));

    let removed = pl::remove<FooData>(&mut uid);
    assert_eq!(removed.data().v, 2);
    assert!(!pl::exists_<FooData>(&uid));
    assert_eq!(event::num_events(), 3);
    let removed_events = event::events_by_type<pl::PlatformLinkRemovedEvent<FooData>>();
    let removed_event = &removed_events[0];
    assert_eq!(pl::removed_event_parent_id(removed_event), parent_id);
    assert!(pl::removed_event_existed_before(removed_event));
    assert!(!pl::removed_event_exists_after(removed_event));

    // Views are read-only and do not add events.
    assert!(pl::get<FooData>(&uid).is_none());
    assert!(!pl::exists_<FooData>(&uid));
    assert_eq!(event::num_events(), 3);
    uid.delete();
}

#[test]
fun clear_absent_repeated_is_silent_and_present_emits() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    let parent_id = uid.to_address();

    pl::clear<FooData>(&mut uid);
    pl::clear<FooData>(&mut uid);
    assert_eq!(event::num_events(), 0);

    let data = FooData { v: 7 };
    pl::set(&mut uid, pl::new(data));
    assert_eq!(event::num_events(), 1);
    pl::clear<FooData>(&mut uid);
    assert!(!pl::exists_<FooData>(&uid));
    assert_eq!(event::num_events(), 2);

    let removed_events = event::events_by_type<pl::PlatformLinkRemovedEvent<FooData>>();
    let removed_event = &removed_events[0];
    assert_eq!(pl::removed_event_parent_id(removed_event), parent_id);
    assert!(pl::removed_event_existed_before(removed_event));
    assert!(!pl::removed_event_exists_after(removed_event));

    pl::clear<FooData>(&mut uid);
    assert_eq!(event::num_events(), 2);
    uid.delete();
}

#[test]
fun equal_replacement_is_silent_but_change_emits() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    let data = FooData { v: 9 };

    pl::set(&mut uid, pl::new(data));
    pl::set(&mut uid, pl::new(data));
    assert_eq!(event::num_events(), 1);
    assert_eq!(pl::borrow<FooData>(&uid).data().v, 9);

    // A complete payload change emits, even when the link type and BCS size
    // remain the same.
    let changed = FooData { v: 10 };
    pl::set(&mut uid, pl::new(changed));
    assert_eq!(event::num_events(), 2);
    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<FooData>>();
    let changed_event = &set_events[1];
    assert!(pl::set_event_existed_before(changed_event));
    assert!(pl::set_event_exists_after(changed_event));

    pl::clear<FooData>(&mut uid);
    uid.delete();
}

#[test]
fun typed_parent_and_type_streams_are_distinct() {
    let ctx = &mut tx_context::dummy();
    let mut foo_uid_a = object::new(ctx);
    let mut foo_uid_b = object::new(ctx);
    let foo_parent_a = foo_uid_a.to_address();
    let foo_parent_b = foo_uid_b.to_address();
    pl::set(&mut foo_uid_a, pl::new(FooData { v: 1 }));
    pl::set(&mut foo_uid_b, pl::new(FooData { v: 2 }));
    pl::set(&mut foo_uid_a, pl::new(BarData { v: 3 }));

    let foo_events = event::events_by_type<pl::PlatformLinkSetEvent<FooData>>();
    let bar_events = event::events_by_type<pl::PlatformLinkSetEvent<BarData>>();
    assert_eq!(foo_events.length(), 2);
    assert_eq!(bar_events.length(), 1);
    assert_eq!(pl::set_event_parent_id(&foo_events[0]), foo_parent_a);
    assert_eq!(pl::set_event_parent_id(&foo_events[1]), foo_parent_b);
    assert_eq!(pl::set_event_parent_id(&bar_events[0]), foo_parent_a);

    pl::clear<FooData>(&mut foo_uid_a);
    pl::clear<FooData>(&mut foo_uid_b);
    pl::clear<BarData>(&mut foo_uid_a);
    foo_uid_a.delete();
    foo_uid_b.delete();
}

#[test]
fun empty_payload_is_not_absence() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    pl::clear<vector<u8>>(&mut uid);
    assert!(!pl::exists_<vector<u8>>(&uid));
    assert_eq!(event::num_events(), 0);

    let empty: vector<u8> = vector[];
    pl::set(&mut uid, pl::new(empty));
    assert!(pl::exists_<vector<u8>>(&uid));
    assert_eq!(event::num_events(), 1);
    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<vector<u8>>>();
    let set_event = &set_events[0];
    assert_eq!(bcs::to_bytes(set_event).length(), 34);

    let _ = pl::remove<vector<u8>>(&mut uid);
    assert!(!pl::exists_<vector<u8>>(&uid));
    assert_eq!(event::num_events(), 2);
    uid.delete();
}

#[test]
fun large_payload_emits_constant_size_signal() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    let data = BlobData { bytes: vector::tabulate!(131072, |_| 7u8) };
    pl::set(&mut uid, pl::new(data));

    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<BlobData>>();
    let set_event = &set_events[0];
    assert_eq!(bcs::to_bytes(set_event).length(), 34);

    pl::set(&mut uid, pl::new(BlobData { bytes: vector[8u8] }));
    let changed = event::events_by_type<pl::PlatformLinkSetEvent<BlobData>>();
    assert_eq!(bcs::to_bytes(&changed[1]).length(), 34);
    assert_eq!(pl::borrow<BlobData>(&uid).data().bytes, vector[8u8]);
    pl::clear<BlobData>(&mut uid);
    let removed = event::events_by_type<pl::PlatformLinkRemovedEvent<BlobData>>();
    assert_eq!(bcs::to_bytes(&removed[0]).length(), 34);
    uid.delete();
}

#[test, expected_failure(abort_code = 0, location = platform_link::platform_link)] // ENoLink
fun borrow_missing_aborts() {
    let ctx = &mut tx_context::dummy();
    let uid = object::new(ctx);
    let _ = pl::borrow<FooData>(&uid);
    abort
}

#[test, expected_failure(abort_code = 0, location = platform_link::platform_link)] // ENoLink
fun remove_missing_aborts() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    let _ = pl::remove<FooData>(&mut uid);
    abort
}
