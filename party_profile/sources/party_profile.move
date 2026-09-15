// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A party's editable profile card — the free-form identity fields a profile
/// page renders.
///
/// Stored as a single `Profile` dynamic field on the party's UID, gated by the
/// `PartyAdminCap`; views are permissionless. Deliberately holds only cohesive
/// identity fields — typed or collection-shaped concerns (roles, tags, genres,
/// media, links) each live in their own extension. `country` and `languages` use
/// validated code primitives (`country_code`, `language_code`), so a stored value
/// is always a real code. The party's `name` is NOT duplicated here — it lives on
/// the core `Party` (`party::set_name`) — and the join date comes from the party's
/// creation event (the indexer has it for free). Each changed set emits a
/// compact country/language context and the authorizing cap address; equal
/// replacements still write but do not emit. A clear emits only when a profile
/// exists. Bios remain in storage and are read on demand. All writes are
/// cap-gated through `party::uid_mut`, and views are permissionless.
module party_profile::party_profile;

use country_code::country_code::CountryCode;
use language_code::language_code::LanguageCode;
use partyos::party::{Party, PartyAdminCap};
use std::string::String;
use sui::dynamic_field as df;
use sui::event::emit;
use sui::vec_set;

// === Errors ===

/// Short bio must not be empty.
const EEmptyBioShort: u64 = 0;
/// Short bio exceeds the maximum length.
const EBioShortTooLong: u64 = 1;
/// Long bio must not be empty when provided.
const EEmptyBioLong: u64 = 2;
/// Long bio exceeds the maximum length.
const EBioLongTooLong: u64 = 3;
/// Too many language tags.
const ETooManyLanguages: u64 = 4;
/// No profile is set on this party.
const ENoProfile: u64 = 5;
/// A language tag appears more than once.
const EDuplicateLanguage: u64 = 6;

// === Constants ===

/// Maximum length of the short bio in bytes.
const MAX_BIO_SHORT_LENGTH: u64 = 300;
/// Maximum length of the long bio in bytes — 8 KB, matching
/// `release_description`. A storage backstop, not an editorial limit: it sits
/// well above any bio anyone is expected to write, because this package
/// publishes immutable and a ceiling that turns out to be too low can never be
/// raised, while one that is too high costs only the gas of the writer who
/// fills it.
const MAX_BIO_LONG_LENGTH: u64 = 8192;
/// Maximum number of language tags.
const MAX_LANGUAGES: u64 = 10;

// === Keys ===

/// Dynamic-field key for a party's profile.
public struct ProfileKey() has copy, drop, store;

// === Types ===

/// A party's profile card. Held as a dynamic-field value, not a standalone
/// object.
public struct Profile has store, drop {
    bio_short: String,
    bio_long: Option<String>,
    country: Option<CountryCode>,
    languages: vector<LanguageCode>,
}

// === Events ===

/// Emitted when a party's profile is set or updated. Retains compact validated
/// country and ordered language codes; bios are read from the dynamic field.
public struct PartyProfileSetEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    had_profile: bool,
    previous_country: Option<vector<u8>>,
    previous_languages: vector<vector<u8>>,
    country: Option<vector<u8>>,
    languages: vector<vector<u8>>,
}

/// Emitted when a party's profile is cleared, carrying removed country and
/// language codes. No event is emitted when the field is absent.
public struct PartyProfileClearedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    previous_country: Option<vector<u8>>,
    previous_languages: vector<vector<u8>>,
}

// === Write API ===

/// Sets (creates or replaces) the party's whole profile. Validation and profile
/// construction happen before authorization, preserving validation precedence;
/// authorization happens before any dynamic-field snapshot or mutation. Every
/// successful call performs the requested insert or replacement. An event is
/// emitted only when the complete profile value changes; an initial profile,
/// including one with explicit empty optional fields, always emits.
public fun set_profile(
    self: &mut Party,
    cap: &PartyAdminCap,
    bio_short: String,
    bio_long: Option<String>,
    country: Option<CountryCode>,
    languages: vector<LanguageCode>,
) {
    validate_bio_short(&bio_short);
    bio_long.do_ref!(|bio| {
        assert!(!bio.is_empty(), EEmptyBioLong);
        assert!(bio.length() <= MAX_BIO_LONG_LENGTH, EBioLongTooLong);
    });
    validate_languages(&languages);

    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let profile = Profile { bio_short, bio_long, country, languages };
    let uid = self.uid_mut(cap);

    let had_profile = df::exists(uid, ProfileKey());
    let previous_country = if (had_profile) {
        optional_country_bytes(&df::borrow<ProfileKey, Profile>(uid, ProfileKey()).country)
    } else { option::none() };
    let previous_languages = if (had_profile) {
        language_bytes(&df::borrow<ProfileKey, Profile>(uid, ProfileKey()).languages)
    } else { vector[] };
    let country = optional_country_bytes(&profile.country);
    let languages = language_bytes(&profile.languages);
    let value_changed = !had_profile
        || df::borrow<ProfileKey, Profile>(uid, ProfileKey()) != &profile;

    if (had_profile) {
        *df::borrow_mut(uid, ProfileKey()) = profile;
    } else {
        df::add(uid, ProfileKey(), profile);
    };
    if (value_changed) {
        emit(PartyProfileSetEvent {
            party_id,
            admin_cap_id,
            had_profile,
            previous_country,
            previous_languages,
            country,
            languages,
        });
    };
}

/// Removes the party's profile. Authorization happens before checking
/// existence; an absent field is a silent no-op, while an existing field is
/// removed and emits exactly one compact change event.
public fun clear_profile(self: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let uid = self.uid_mut(cap);
    if (df::exists(uid, ProfileKey())) {
        let previous = df::remove<ProfileKey, Profile>(uid, ProfileKey());
        let previous_country = optional_country_bytes(&previous.country);
        let previous_languages = language_bytes(&previous.languages);
        emit(PartyProfileClearedEvent {
            party_id,
            admin_cap_id,
            previous_country,
            previous_languages,
        });
    }
}

// === Views ===

/// Whether the party has a profile.
public fun has_profile(self: &Party): bool {
    df::exists(self.uid(), ProfileKey())
}

/// Borrows the party's profile. Aborts if none is set.
public fun profile(self: &Party): &Profile {
    assert!(df::exists(self.uid(), ProfileKey()), ENoProfile);
    df::borrow(self.uid(), ProfileKey())
}

public fun bio_short(self: &Profile): String { self.bio_short }
public fun bio_long(self: &Profile): Option<String> { self.bio_long }
public fun country(self: &Profile): Option<CountryCode> { self.country }
public fun languages(self: &Profile): vector<LanguageCode> { self.languages }

// === Private Functions ===

/// Copies an optional validated country code to an optional raw byte vector.
fun optional_country_bytes(value: &Option<CountryCode>): Option<vector<u8>> {
    let mut result = option::none();
    value.do_ref!(|value| {
        let code = country_code::country_code::code(value);
        result.fill(*code.as_bytes());
    });
    result
}

/// Copies validated language codes to raw byte vectors while preserving order.
fun language_bytes(values: &vector<LanguageCode>): vector<vector<u8>> {
    let mut result = vector[];
    values.do_ref!(|value| {
        let code = language_code::language_code::code(value);
        result.push_back(*code.as_bytes());
    });
    result
}

fun validate_bio_short(bio_short: &String) {
    assert!(!bio_short.is_empty(), EEmptyBioShort);
    assert!(bio_short.length() <= MAX_BIO_SHORT_LENGTH, EBioShortTooLong);
}

// Each `LanguageCode` is already a valid ISO 639-1 code by construction, so
// only the count and duplicates are checked here.
fun validate_languages(languages: &vector<LanguageCode>) {
    assert!(languages.length() <= MAX_LANGUAGES, ETooManyLanguages);
    let mut seen = vec_set::empty<LanguageCode>();
    languages.do_ref!(|l| {
        assert!(!seen.contains(l), EDuplicateLanguage);
        seen.insert(*l);
    });
}

// === Test Functions ===

/// Test-only accessor for every `PartyProfileSetEvent` field, in declaration order.
#[test_only]
public fun set_event_fields(
    event: &PartyProfileSetEvent,
): (address, address, bool, Option<vector<u8>>, vector<vector<u8>>, Option<vector<u8>>, vector<vector<u8>>) {
    (
        event.party_id,
        event.admin_cap_id,
        event.had_profile,
        event.previous_country,
        event.previous_languages,
        event.country,
        event.languages,
    )
}

/// Test-only descriptive alias for `set_event_fields`.
#[test_only]
public fun profile_set_event_fields(
    event: &PartyProfileSetEvent,
): (address, address, bool, Option<vector<u8>>, vector<vector<u8>>, Option<vector<u8>>, vector<vector<u8>>) {
    set_event_fields(event)
}

/// Test-only accessor for every `PartyProfileClearedEvent` field, in declaration
/// order.
#[test_only]
public fun cleared_event_fields(
    event: &PartyProfileClearedEvent,
): (address, address, Option<vector<u8>>, vector<vector<u8>>) {
    (
        event.party_id,
        event.admin_cap_id,
        event.previous_country,
        event.previous_languages,
    )
}

/// Test-only descriptive alias for `cleared_event_fields`.
#[test_only]
public fun profile_cleared_event_fields(
    event: &PartyProfileClearedEvent,
): (address, address, Option<vector<u8>>, vector<vector<u8>>) {
    cleared_event_fields(event)
}
