// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Off-Miso call-to-action links for a party — the "what do you want people to
/// do" row (Tickets, Merch, Newsletter, external Listen, …).
///
/// Deliberately slim: a CTA is just a `{ label, url }`. On-Miso actions
/// (collect / listen-on-Miso / pin) are a different, interactive concern and
/// live in `party_featured`, which references object ids and can render live
/// state — so this package stays a plain, dependency-light external link hub.
///
/// The CTAs are an ordered list: **position is priority**. The whole list is
/// written at once (`set_ctas`) — the natural fit for a drag-to-reorder editor
/// that saves on submit — so there are no per-entry ids to track. Gated by the
/// `PartyAdminCap`; views are permissionless. Each changed write emits one
/// compact event with the authorizing cap address and prior/resulting counts;
/// an absent clear is silent. Equal replacements still perform the write but
/// do not emit a change event.
module party_cta::party_cta;

use partyos::party::{Party, PartyAdminCap};
use std::string::String;
use sui::dynamic_field as df;
use sui::event::emit;

// === Errors ===

/// A CTA label must not be empty.
const EEmptyLabel: u64 = 0;
/// A CTA label exceeds the maximum length.
const ELabelTooLong: u64 = 1;
/// A CTA url must not be empty.
const EEmptyUrl: u64 = 2;
/// A CTA url exceeds the maximum length.
const EUrlTooLong: u64 = 3;
/// The list exceeds the maximum number of CTAs.
const ETooManyCtas: u64 = 4;

// === Constants ===

/// Maximum length of a CTA label in bytes.
const MAX_LABEL_LENGTH: u64 = 60;
/// Maximum length of a CTA url in bytes.
const MAX_URL_LENGTH: u64 = 2000;
/// Maximum number of CTAs on a party.
const MAX_CTAS: u64 = 20;

// === Keys ===

/// Dynamic-field key for a party's ordered CTA list.
public struct CtasKey() has copy, drop, store;

// === Types ===

/// A single call-to-action: a labeled external link.
public struct Cta has copy, drop, store {
    label: String,
    url: String,
}

// === Events ===

/// Emitted when a party's CTA list is set or replaced. Counts describe the
/// change; consumers read the field for ordered labels and URLs.
public struct CtasSetEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    existed_before: bool,
    previous_count: u64,
    count: u64,
}

/// Emitted when a party's CTA list is cleared, carrying the removed count.
/// No event is emitted when the list was absent.
public struct CtasClearedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    previous_count: u64,
}

// === Constructor / accessors ===

/// Builds a CTA. Aborts if the label or url is empty or too long. Callers build
/// the ordered `vector<Cta>` client-side and submit it with `set_ctas`.
public fun new_cta(label: String, url: String): Cta {
    assert!(!label.is_empty(), EEmptyLabel);
    assert!(label.length() <= MAX_LABEL_LENGTH, ELabelTooLong);
    assert!(!url.is_empty(), EEmptyUrl);
    assert!(url.length() <= MAX_URL_LENGTH, EUrlTooLong);
    Cta { label, url }
}

/// The CTA's display label.
public fun label(self: &Cta): String {
    self.label
}

/// The CTA's destination url.
public fun url(self: &Cta): String {
    self.url
}

// === Write API ===

/// Sets (or replaces) the party's ordered CTA list. Position is priority.
/// Length is checked before authorization. Every successful call performs the
/// requested insert or replacement. An event is emitted only when the complete
/// ordered CTA value changes; an empty first attachment remains a meaningful
/// insert and emits.
public fun set_ctas(self: &mut Party, cap: &PartyAdminCap, ctas: vector<Cta>) {
    assert!(ctas.length() <= MAX_CTAS, ETooManyCtas);
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let count = ctas.length();
    let uid = self.uid_mut(cap);

    let existed_before = df::exists(uid, CtasKey());
    let previous_count = if (existed_before) {
        df::borrow<CtasKey, vector<Cta>>(uid, CtasKey()).length()
    } else { 0 };
    let value_changed = if (existed_before) {
        *df::borrow(uid, CtasKey()) != ctas
    } else {
        true
    };

    if (existed_before) {
        *df::borrow_mut(uid, CtasKey()) = ctas;
    } else {
        df::add(uid, CtasKey(), ctas);
    };
    if (value_changed) {
        emit(CtasSetEvent {
            party_id,
            admin_cap_id,
            existed_before,
            previous_count,
            count,
        });
    };
}

/// Removes the party's CTA list. Authorization happens before checking
/// existence; an absent list is a silent no-op, while an existing list emits
/// exactly one event containing the removed count.
public fun clear_ctas(self: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let uid = self.uid_mut(cap);
    if (df::exists(uid, CtasKey())) {
        let previous: vector<Cta> = df::remove(uid, CtasKey());
        let previous_count = previous.length();
        emit(CtasClearedEvent {
            party_id,
            admin_cap_id,
            previous_count,
        });
    }
}

// === Views ===

/// Whether the party has a CTA list.
public fun has_ctas(self: &Party): bool {
    df::exists(self.uid(), CtasKey())
}

/// The party's ordered CTA list (empty if unset).
public fun ctas(self: &Party): vector<Cta> {
    if (!df::exists(self.uid(), CtasKey())) return vector[];
    *df::borrow<CtasKey, vector<Cta>>(self.uid(), CtasKey())
}

// === Test Functions ===

/// Test-only accessor for every `CtasSetEvent` field, in declaration order.
#[test_only]
public fun set_event_fields(
    event: &CtasSetEvent,
): (address, address, bool, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.existed_before,
        event.previous_count,
        event.count,
    )
}

/// Test-only accessor for every `CtasClearedEvent` field, in declaration order.
#[test_only]
public fun cleared_event_fields(
    event: &CtasClearedEvent,
): (address, address, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.previous_count,
    )
}
