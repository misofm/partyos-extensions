// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_social::party_social_tests;

use party_social::party_social as social;
use std::unit_test::assert_eq;
use sui::event;

#[test]
fun added_platform_constructors() {
    let events_before = event::num_events();
    assert_eq!(social::discord(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::telegram(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::reddit(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::twitch(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::facebook(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
}

#[test]
fun constructors_wrap_handles() {
    let events_before = event::num_events();
    assert_eq!(social::x(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::instagram(b"miso.fm".to_string()).data().handle(), b"miso.fm".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::threads(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::tiktok(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), events_before);
    assert_eq!(social::youtube(b"@miso".to_string()).data().handle(), b"@miso".to_string());
    assert_eq!(event::num_events(), events_before);
}

#[test, expected_failure(abort_code = 0, location = party_social::party_social)] // EEmptyHandle
fun rejects_empty_x_handle() {
    let _ = social::x(b"".to_string());
    abort
}

#[test, expected_failure(abort_code = 0, location = party_social::party_social)] // EEmptyHandle
fun rejects_empty_instagram_handle() {
    let _ = social::instagram(b"".to_string());
    abort
}

#[test, expected_failure(abort_code = 1, location = party_social::party_social)] // EHandleTooLong
fun rejects_overlong_handle() {
    // 257 bytes — one over the shared backstop (platform_link::max_identifier_length(), 256).
    let long = vector::tabulate!(257, |_| 97u8).to_string();
    let _ = social::x(long);
    abort
}
