// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module platform_link::platform_link_tests;

// Aliased so the bare `platform_link` name stays free for `location = …` below.
use platform_link::platform_link as pl;
use std::bcs;
use std::type_name;
use std::unit_test::assert_eq;
use sui::event;
use sui::hash::blake2b256;

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
    let first_bcs = bcs::to_bytes(&first);
    let first_bcs_hash = blake2b256(&first_bcs);
    let second = FooData { v: 2 };
    let second_bcs = bcs::to_bytes(&second);
    let second_bcs_hash = blake2b256(&second_bcs);
    let data_type = type_name::with_defining_ids<FooData>().into_string().into_bytes();

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
    assert_eq!(pl::set_event_data_type(inserted), data_type);
    assert!(!pl::set_event_existed_before(inserted));
    assert!(pl::set_event_exists_after(inserted));
    assert_eq!(pl::set_event_previous_bcs_length(inserted), 0);
    assert_eq!(pl::set_event_previous_bcs_hash(inserted), vector[]);
    assert_eq!(pl::set_event_data_bcs_length(inserted), first_bcs.length());
    assert_eq!(pl::set_event_data_bcs_hash(inserted), first_bcs_hash);

    // Setting again replaces the existing link in place and emits a second
    // event carrying both the actual previous and new summaries.
    pl::set(&mut uid, pl::new(second));
    assert_eq!(pl::borrow<FooData>(&uid).data().v, 2);
    assert_eq!(pl::get<FooData>(&uid).destroy_some().data().v, 2);
    assert_eq!(event::num_events(), 2);
    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<FooData>>();
    let replaced = &set_events[1];
    assert_eq!(pl::set_event_parent_id(replaced), parent_id);
    assert_eq!(pl::set_event_data_type(replaced), data_type);
    assert!(pl::set_event_existed_before(replaced));
    assert!(pl::set_event_exists_after(replaced));
    assert_eq!(pl::set_event_previous_bcs_length(replaced), first_bcs.length());
    assert_eq!(pl::set_event_previous_bcs_hash(replaced), first_bcs_hash);
    assert_eq!(pl::set_event_data_bcs_length(replaced), second_bcs.length());
    assert_eq!(pl::set_event_data_bcs_hash(replaced), second_bcs_hash);

    let removed = pl::remove<FooData>(&mut uid);
    assert_eq!(removed.data().v, 2);
    assert!(!pl::exists_<FooData>(&uid));
    assert_eq!(event::num_events(), 3);
    let removed_events = event::events_by_type<pl::PlatformLinkRemovedEvent<FooData>>();
    let removed_event = &removed_events[0];
    assert_eq!(pl::removed_event_parent_id(removed_event), parent_id);
    assert_eq!(pl::removed_event_data_type(removed_event), data_type);
    assert!(pl::removed_event_existed_before(removed_event));
    assert!(!pl::removed_event_exists_after(removed_event));
    assert_eq!(pl::removed_event_removed_bcs_length(removed_event), second_bcs.length());
    assert_eq!(pl::removed_event_removed_bcs_hash(removed_event), second_bcs_hash);

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
    let data_bcs = bcs::to_bytes(&data);
    let data_bcs_hash = blake2b256(&data_bcs);
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
    assert_eq!(pl::removed_event_removed_bcs_length(removed_event), data_bcs.length());
    assert_eq!(pl::removed_event_removed_bcs_hash(removed_event), data_bcs_hash);

    pl::clear<FooData>(&mut uid);
    assert_eq!(event::num_events(), 2);
    uid.delete();
}

#[test]
fun equal_replacement_is_silent_but_change_emits() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    let data = FooData { v: 9 };
    let data_bcs = bcs::to_bytes(&data);
    let data_bcs_hash = blake2b256(&data_bcs);

    pl::set(&mut uid, pl::new(data));
    pl::set(&mut uid, pl::new(data));
    assert_eq!(event::num_events(), 1);
    assert_eq!(pl::borrow<FooData>(&uid).data().v, 9);

    // A complete payload change emits, even when the link type and BCS size
    // remain the same.
    let changed = FooData { v: 10 };
    let changed_bcs = bcs::to_bytes(&changed);
    let changed_bcs_hash = blake2b256(&changed_bcs);
    pl::set(&mut uid, pl::new(changed));
    assert_eq!(event::num_events(), 2);
    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<FooData>>();
    let changed_event = &set_events[1];
    assert!(pl::set_event_existed_before(changed_event));
    assert!(pl::set_event_exists_after(changed_event));
    assert_eq!(pl::set_event_previous_bcs_length(changed_event), data_bcs.length());
    assert_eq!(pl::set_event_previous_bcs_hash(changed_event), data_bcs_hash);
    assert_eq!(pl::set_event_data_bcs_length(changed_event), changed_bcs.length());
    assert_eq!(pl::set_event_data_bcs_hash(changed_event), changed_bcs_hash);

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
    assert!(
        pl::set_event_data_type(&foo_events[0]) !=
            pl::set_event_data_type(&bar_events[0]),
    );

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
    let empty_bcs = bcs::to_bytes(&empty);
    let empty_bcs_hash = blake2b256(&empty_bcs);
    pl::set(&mut uid, pl::new(empty));
    assert!(pl::exists_<vector<u8>>(&uid));
    assert_eq!(event::num_events(), 1);
    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<vector<u8>>>();
    let set_event = &set_events[0];
    assert_eq!(pl::set_event_data_bcs_length(set_event), empty_bcs.length());
    assert_eq!(pl::set_event_data_bcs_hash(set_event), empty_bcs_hash);

    let _ = pl::remove<vector<u8>>(&mut uid);
    assert!(!pl::exists_<vector<u8>>(&uid));
    assert_eq!(event::num_events(), 2);
    uid.delete();
}

#[test]
fun large_payload_emits_bounded_summary() {
    let ctx = &mut tx_context::dummy();
    let mut uid = object::new(ctx);
    let data = BlobData { bytes: vector::tabulate!(131072, |_| 7u8) };
    let data_bcs = bcs::to_bytes(&data);
    let data_bcs_hash = blake2b256(&data_bcs);
    pl::set(&mut uid, pl::new(data));

    let set_events = event::events_by_type<pl::PlatformLinkSetEvent<BlobData>>();
    let set_event = &set_events[0];
    assert_eq!(pl::set_event_data_bcs_length(set_event), data_bcs.length());
    assert_eq!(pl::set_event_data_bcs_hash(set_event), data_bcs_hash);
    assert_eq!(pl::set_event_data_bcs_hash(set_event).length(), 32);

    pl::clear<BlobData>(&mut uid);
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
