// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// `PlatformLink<Data>` — a typed link to an entity on one external platform: a
/// streaming service (Spotify, Bandcamp), a social network (X, Instagram), or
/// any other site.
///
/// A protocol-agnostic primitive: it knows nothing about any specific platform,
/// nor about any consumer object (a `Party`, a `Release`, …). It is a generic
/// wrapper around a `Data` payload plus the machinery to store exactly one such
/// link, by type, as a dynamic field on any object's `UID`.
///
/// `Data` is the platform-specific native identifier(s) — an Instagram handle, a
/// Spotify artist id, a Bandcamp subdomain, etc. Each platform defines its own
/// `Data` type in its own small package, so adding a platform is a new type,
/// never a change here. URLs are never stored: a client rebuilds the public URL
/// from the `Data` it reads back, so a platform reshaping its URLs needs no
/// on-chain change.
///
/// Storage is keyed by `PlatformLinkKey<Data>`, whose `phantom Data` makes
/// `PlatformLinkKey<InstagramData>` and `PlatformLinkKey<SpotifyData>` distinct
/// keys — so each platform occupies its own independent field on the same `UID`,
/// and a new platform can be added to a record without touching the others.
module platform_link::platform_link;

use std::type_name;
use sui::bcs;
use sui::dynamic_field as df;
use sui::event::emit;
use sui::hash::blake2b256;

// === Errors ===

/// No `PlatformLink<Data>` is stored under this `UID`.
const ENoLink: u64 = 0;

// === Shared limits ===
//
// Owned here so every payload package backstops storage by the same numbers
// and they can never drift. Both are generous storage-hygiene backstops, not
// format validation — real identifiers and URLs are far shorter, and format
// rules change over time and belong in the app layer. (Functions, not
// constants: this toolchain has no `public const`.)

/// Maximum length of a platform identifier — a handle, username, id, or
/// subdomain — in bytes.
public fun max_identifier_length(): u64 { 256 }

/// Maximum length of a stored URL in bytes, for payloads whose URL is the
/// identity (no reconstructable handle).
public fun max_url_length(): u64 { 2000 }

// === Types ===

/// A link to an entity on one platform. `Data` carries that platform's native
/// identifier(s); the public URL is rebuilt from it client-side.
public struct PlatformLink<Data: copy + drop + store> has copy, drop, store {
    data: Data,
}

/// Dynamic-field key for the single `PlatformLink<Data>` on a `UID`. The
/// `phantom Data` gives each platform its own field.
public struct PlatformLinkKey<phantom Data>() has copy, drop, store;

/// Emitted when a platform link is inserted or replaced. The payload is kept
/// bounded: only the BCS length and Blake2b-256 digest of `Data` are included.
/// `data_type` is the raw bytes of the defining-ID-qualified type name.
public struct PlatformLinkSetEvent<phantom Data> has copy, drop {
    parent_id: address,
    data_type: vector<u8>,
    existed_before: bool,
    exists_after: bool,
    previous_bcs_length: u64,
    previous_bcs_hash: vector<u8>,
    data_bcs_length: u64,
    data_bcs_hash: vector<u8>,
}

/// Emitted when a platform link is removed. The removed payload is represented
/// by its BCS length and Blake2b-256 digest, never by unbounded payload bytes.
/// `data_type` is the raw bytes of the defining-ID-qualified type name.
public struct PlatformLinkRemovedEvent<phantom Data> has copy, drop {
    parent_id: address,
    data_type: vector<u8>,
    existed_before: bool,
    exists_after: bool,
    removed_bcs_length: u64,
    removed_bcs_hash: vector<u8>,
}

// === Event helpers ===

/// Returns a bounded summary of `data`'s canonical BCS representation.
fun summarize<Data: copy + drop + store>(data: &Data): (u64, vector<u8>) {
    let bytes = bcs::to_bytes(data);
    let length = bytes.length();
    let hash = blake2b256(&bytes);
    (length, hash)
}

/// Returns the defining-ID-qualified type name as raw bytes for event payloads.
fun data_type<Data>(): vector<u8> {
    type_name::with_defining_ids<Data>().into_string().into_bytes()
}

// === Constructor / accessor ===

/// Wraps a platform-specific payload into a link.
public fun new<Data: copy + drop + store>(data: Data): PlatformLink<Data> {
    PlatformLink { data }
}

/// The wrapped platform-specific payload.
public fun data<Data: copy + drop + store>(self: &PlatformLink<Data>): Data {
    self.data
}

// === UID storage ===
//
// Exactly one `PlatformLink<Data>` per `Data` type per `UID`, keyed by
// `PlatformLinkKey<Data>`. Callers pass the object's `UID` (e.g. a party's, via
// its admin cap), keeping this module free of any object-specific dependency.

/// Whether a `PlatformLink<Data>` is stored under `uid`.
public fun exists_<Data: copy + drop + store>(uid: &UID): bool {
    df::exists(uid, PlatformLinkKey<Data>())
}

/// Sets the `PlatformLink<Data>` under `uid`, replacing any existing one.
/// Emits `PlatformLinkSetEvent<Data>` with bounded summaries of the previous
/// and new payloads only when the complete `Data` value changes. Equal
/// replacements still write the new value but do not emit.
public fun set<Data: copy + drop + store>(uid: &mut UID, link: PlatformLink<Data>) {
    if (df::exists(uid, PlatformLinkKey<Data>())) {
        let (previous_bcs_length, previous_bcs_hash) =
            summarize(&df::borrow<PlatformLinkKey<Data>, PlatformLink<Data>>(
                uid,
                PlatformLinkKey<Data>(),
            ).data);
        let (data_bcs_length, data_bcs_hash) = summarize(&link.data);
        let previous: &PlatformLink<Data> = df::borrow(uid, PlatformLinkKey<Data>());
        let value_changed = previous.data != link.data;
        *df::borrow_mut(uid, PlatformLinkKey<Data>()) = link;
        if (value_changed) {
            emit(PlatformLinkSetEvent<Data> {
                parent_id: uid.to_address(),
                data_type: data_type<Data>(),
                existed_before: true,
                exists_after: true,
                previous_bcs_length,
                previous_bcs_hash,
                data_bcs_length,
                data_bcs_hash,
            });
        };
    } else {
        let (data_bcs_length, data_bcs_hash) = summarize(&link.data);
        df::add(uid, PlatformLinkKey<Data>(), link);
        emit(PlatformLinkSetEvent<Data> {
            parent_id: uid.to_address(),
            data_type: data_type<Data>(),
            existed_before: false,
            exists_after: true,
            previous_bcs_length: 0,
            previous_bcs_hash: vector[],
            data_bcs_length,
            data_bcs_hash,
        });
    }
}

/// The stored `PlatformLink<Data>`, or `none` if absent.
public fun get<Data: copy + drop + store>(uid: &UID): Option<PlatformLink<Data>> {
    if (df::exists(uid, PlatformLinkKey<Data>())) {
        option::some(*df::borrow(uid, PlatformLinkKey<Data>()))
    } else {
        option::none()
    }
}

/// Borrows the stored link. Aborts if none is stored.
public fun borrow<Data: copy + drop + store>(uid: &UID): &PlatformLink<Data> {
    assert!(df::exists(uid, PlatformLinkKey<Data>()), ENoLink);
    df::borrow(uid, PlatformLinkKey<Data>())
}

/// Removes and returns the stored link. Aborts if none is stored. Emits
/// `PlatformLinkRemovedEvent<Data>` for the removed payload.
public fun remove<Data: copy + drop + store>(uid: &mut UID): PlatformLink<Data> {
    assert!(df::exists(uid, PlatformLinkKey<Data>()), ENoLink);
    let link: PlatformLink<Data> = df::remove(uid, PlatformLinkKey<Data>());
    let (removed_bcs_length, removed_bcs_hash) = summarize(&link.data);
    emit(PlatformLinkRemovedEvent<Data> {
        parent_id: uid.to_address(),
        data_type: data_type<Data>(),
        existed_before: true,
        exists_after: false,
        removed_bcs_length,
        removed_bcs_hash,
    });
    link
}

/// Removes the stored link if present, discarding it. No-op if absent.
public fun clear<Data: copy + drop + store>(uid: &mut UID) {
    if (df::exists(uid, PlatformLinkKey<Data>())) {
        let link: PlatformLink<Data> = df::remove(uid, PlatformLinkKey<Data>());
        let (removed_bcs_length, removed_bcs_hash) = summarize(&link.data);
        emit(PlatformLinkRemovedEvent<Data> {
            parent_id: uid.to_address(),
            data_type: data_type<Data>(),
            existed_before: true,
            exists_after: false,
            removed_bcs_length,
            removed_bcs_hash,
        });
    }
}

// === Test-only event accessors ===

/// Reads `parent_id` from a set event in tests.
#[test_only]
public fun set_event_parent_id<Data>(event: &PlatformLinkSetEvent<Data>): address {
    event.parent_id
}

/// Reads `data_type` from a set event in tests.
#[test_only]
public fun set_event_data_type<Data>(event: &PlatformLinkSetEvent<Data>): vector<u8> {
    event.data_type
}

/// Reads `existed_before` from a set event in tests.
#[test_only]
public fun set_event_existed_before<Data>(event: &PlatformLinkSetEvent<Data>): bool {
    event.existed_before
}

/// Reads `exists_after` from a set event in tests.
#[test_only]
public fun set_event_exists_after<Data>(event: &PlatformLinkSetEvent<Data>): bool {
    event.exists_after
}

/// Reads `previous_bcs_length` from a set event in tests.
#[test_only]
public fun set_event_previous_bcs_length<Data>(event: &PlatformLinkSetEvent<Data>): u64 {
    event.previous_bcs_length
}

/// Reads `previous_bcs_hash` from a set event in tests.
#[test_only]
public fun set_event_previous_bcs_hash<Data>(event: &PlatformLinkSetEvent<Data>): vector<u8> {
    event.previous_bcs_hash
}

/// Reads `data_bcs_length` from a set event in tests.
#[test_only]
public fun set_event_data_bcs_length<Data>(event: &PlatformLinkSetEvent<Data>): u64 {
    event.data_bcs_length
}

/// Reads `data_bcs_hash` from a set event in tests.
#[test_only]
public fun set_event_data_bcs_hash<Data>(event: &PlatformLinkSetEvent<Data>): vector<u8> {
    event.data_bcs_hash
}

/// Reads `parent_id` from a removed event in tests.
#[test_only]
public fun removed_event_parent_id<Data>(event: &PlatformLinkRemovedEvent<Data>): address {
    event.parent_id
}

/// Reads `data_type` from a removed event in tests.
#[test_only]
public fun removed_event_data_type<Data>(event: &PlatformLinkRemovedEvent<Data>): vector<u8> {
    event.data_type
}

/// Reads `existed_before` from a removed event in tests.
#[test_only]
public fun removed_event_existed_before<Data>(event: &PlatformLinkRemovedEvent<Data>): bool {
    event.existed_before
}

/// Reads `exists_after` from a removed event in tests.
#[test_only]
public fun removed_event_exists_after<Data>(event: &PlatformLinkRemovedEvent<Data>): bool {
    event.exists_after
}

/// Reads `removed_bcs_length` from a removed event in tests.
#[test_only]
public fun removed_event_removed_bcs_length<Data>(event: &PlatformLinkRemovedEvent<Data>): u64 {
    event.removed_bcs_length
}

/// Reads `removed_bcs_hash` from a removed event in tests.
#[test_only]
public fun removed_event_removed_bcs_hash<Data>(event: &PlatformLinkRemovedEvent<Data>): vector<u8> {
    event.removed_bcs_hash
}
