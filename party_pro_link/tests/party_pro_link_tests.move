// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module party_pro_link::party_pro_link_tests;

use party_pro_link::party_pro_link as pro;
use std::unit_test::assert_eq;
use sui::event;

#[test]
fun url_based_constructors() {
    assert_eq!(pro::website(b"https://miso.fm".to_string()).data().url(), b"https://miso.fm".to_string());
    assert_eq!(pro::booking_page(b"https://book.example".to_string()).data().url(), b"https://book.example".to_string());
    assert_eq!(pro::management_page(b"https://management.example".to_string()).data().url(), b"https://management.example".to_string());
    assert_eq!(pro::publisher_page(b"https://publisher.example".to_string()).data().url(), b"https://publisher.example".to_string());
    assert_eq!(pro::epk(b"https://epk.example".to_string()).data().url(), b"https://epk.example".to_string());
    assert_eq!(pro::label_page(b"https://label.example".to_string()).data().url(), b"https://label.example".to_string());
    assert_eq!(event::num_events(), 0);
}

#[test]
fun handle_based_constructors() {
    assert_eq!(pro::patreon(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(pro::substack(b"miso".to_string()).data().subdomain(), b"miso".to_string());
    assert_eq!(pro::kofi(b"miso".to_string()).data().handle(), b"miso".to_string());
    assert_eq!(event::num_events(), 0);
}

#[test, expected_failure(abort_code = 0, location = party_pro_link::party_pro_link)] // EEmptyValue
fun rejects_empty_website() {
    let _ = pro::website(b"".to_string());
    abort
}

#[test, expected_failure(abort_code = 0, location = party_pro_link::party_pro_link)] // EEmptyValue
fun rejects_empty_patreon() {
    let _ = pro::patreon(b"".to_string());
    abort
}

#[test, expected_failure(abort_code = 1, location = party_pro_link::party_pro_link)] // EUrlTooLong
fun rejects_overlong_url() {
    // 2001 bytes — one over the shared backstop (platform_link::max_url_length(), 2000).
    let long = vector::tabulate!(2001, |_| 97u8).to_string();
    let _ = pro::website(long);
    abort
}

#[test, expected_failure(abort_code = 2, location = party_pro_link::party_pro_link)] // EHandleTooLong
fun rejects_overlong_handle() {
    // 257 bytes — one over the shared backstop (platform_link::max_identifier_length(), 256).
    let long = vector::tabulate!(257, |_| 97u8).to_string();
    let _ = pro::patreon(long);
    abort
}
