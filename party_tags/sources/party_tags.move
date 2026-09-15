// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Free-form tags for a party — moods, scenes, and descriptors (e.g. "ambient",
/// "deconstructed club", "leftfield pop").
///
/// The uncurated sibling to `party_genre`: genres reference a canonical, shared
/// vocabulary; tags are whatever the artist types. The set mechanics — storage,
/// duplicate and capacity checks, field reclamation — live in the shared
/// `typed_set` primitive; this package keeps only what is tag-specific: length
/// validation, the capacity, and the typed events. Duplicate / not-present /
/// over-max aborts come from `typed_set` with its own error codes. Tags are
/// stored as given (exact dedupe); normalization for search/display is a client
/// concern. Gated by the `PartyAdminCap`; views are permissionless. Mutation
/// events carry the party and cap addresses, the raw tag bytes, and before/after
/// counts; a populated clear carries counts only.
module party_tags::party_tags;

use partyos::party::{Party, PartyAdminCap};
use std::string::String;
use sui::event::emit;
use typed_set::typed_set as set;

// === Errors ===

/// A tag must not be empty.
const EEmptyTag: u64 = 0;
/// A tag exceeds the maximum length.
const ETagTooLong: u64 = 1;

// === Constants ===

/// Maximum length of a tag in bytes.
const MAX_TAG_LENGTH: u64 = 50;
/// Maximum number of tags a party may carry.
const MAX_TAGS: u64 = 30;

// === Keys ===

/// Dynamic-field key for a party's tag set, stored as a `VecSet<String>` and
/// managed through `typed_set`.
public struct TagsKey() has copy, drop, store;

// === Events ===

/// Emitted when a tag is added to a party.
public struct TagAddedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    tag: vector<u8>,
    tag_count_before: u64,
    tag_count_after: u64,
}

/// Emitted when a tag is removed from a party.
public struct TagRemovedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    tag: vector<u8>,
    tag_count_before: u64,
    tag_count_after: u64,
}

/// Emitted when a party's entire tag set is removed.
public struct TagsClearedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    tag_count_before: u64,
    tag_count_after: u64,
}

// === Write API ===

/// Adds a tag to the party. Aborts if empty or too long here, and in
/// `typed_set` if already present or the max is reached.
public fun add_tag(self: &mut Party, cap: &PartyAdminCap, tag: String) {
    assert!(!tag.is_empty(), EEmptyTag);
    assert!(tag.length() <= MAX_TAG_LENGTH, ETagTooLong);
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let tag_bytes = *tag.as_bytes();
    set::add(self.uid_mut(cap), TagsKey(), tag, MAX_TAGS);
    let tag_count_after = set::keys<TagsKey, String>(self.uid(), TagsKey()).length();
    let tag_count_before = tag_count_after - 1;
    emit(TagAddedEvent {
        party_id,
        admin_cap_id,
        tag: tag_bytes,
        tag_count_before,
        tag_count_after,
    });
}

/// Removes a tag from the party. Aborts in `typed_set` if not present. The
/// whole field is dropped when the last tag leaves, so `has_tags` tracks
/// "carries tags", not "has ever tagged".
public fun remove_tag(self: &mut Party, cap: &PartyAdminCap, tag: String) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let tag_bytes = *tag.as_bytes();
    set::remove(self.uid_mut(cap), TagsKey(), tag);
    let tag_count_after = set::keys<TagsKey, String>(self.uid(), TagsKey()).length();
    let tag_count_before = tag_count_after + 1;
    emit(TagRemovedEvent {
        party_id,
        admin_cap_id,
        tag: tag_bytes,
        tag_count_before,
        tag_count_after,
    });
}

/// Removes the party's entire tag set. No-op if none is set.
public fun clear_tags(self: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let uid = self.uid_mut(cap);
    if (set::exists(uid, TagsKey())) {
        let tags = set::keys<TagsKey, String>(uid, TagsKey());
        let tag_count_before = tags.length();
        set::clear<TagsKey, String>(uid, TagsKey());
        let tag_count_after = set::keys<TagsKey, String>(uid, TagsKey()).length();
        emit(TagsClearedEvent {
            party_id,
            admin_cap_id,
            tag_count_before,
            tag_count_after,
        });
    }
}

// === Views ===

/// Whether the party carries any tags.
public fun has_tags(self: &Party): bool {
    set::exists(self.uid(), TagsKey())
}

/// Whether the party carries the given tag.
public fun has_tag(self: &Party, tag: String): bool {
    set::contains(self.uid(), TagsKey(), &tag)
}

/// The party's tags.
public fun tags(self: &Party): vector<String> {
    set::keys(self.uid(), TagsKey())
}

// === Test accessors ===

/// Test-only accessor for every `TagAddedEvent` field, in declaration order.
#[test_only]
public fun added_event_fields(
    event: &TagAddedEvent,
): (address, address, vector<u8>, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.tag,
        event.tag_count_before,
        event.tag_count_after,
    )
}

/// Test-only descriptive alias for `added_event_fields`.
#[test_only]
public fun tag_added_event_fields(
    event: &TagAddedEvent,
): (address, address, vector<u8>, u64, u64) {
    added_event_fields(event)
}

/// Test-only accessor for every `TagRemovedEvent` field, in declaration order.
#[test_only]
public fun removed_event_fields(
    event: &TagRemovedEvent,
): (address, address, vector<u8>, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.tag,
        event.tag_count_before,
        event.tag_count_after,
    )
}

/// Test-only descriptive alias for `removed_event_fields`.
#[test_only]
public fun tag_removed_event_fields(
    event: &TagRemovedEvent,
): (address, address, vector<u8>, u64, u64) {
    removed_event_fields(event)
}

/// Test-only accessor for every `TagsClearedEvent` field, in declaration order.
#[test_only]
public fun cleared_event_fields(
    event: &TagsClearedEvent,
): (address, address, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.tag_count_before,
        event.tag_count_after,
    )
}

/// Test-only descriptive alias for `cleared_event_fields`.
#[test_only]
public fun tags_cleared_event_fields(
    event: &TagsClearedEvent,
): (address, address, u64, u64) {
    cleared_event_fields(event)
}
