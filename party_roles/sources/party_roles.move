// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Artist-type roles for a party — what kind of act this is (artist, producer,
/// DJ, band, label, …). A party can hold several.
///
/// `ArtistRole` is a closed enum with a `Custom` escape hatch, mirroring
/// `composition_party_role`: canonical variants give the frontend a fixed,
/// typo-free set to render icons for, while `Custom(name)` covers anything else.
/// The set mechanics — storage, duplicate and capacity checks, field
/// reclamation — live in the shared `typed_set` primitive; this package keeps
/// the role type, name validation, the capacity, and the typed events.
/// Duplicate / not-present / over-max aborts come from `typed_set` with its own
/// error codes. Gated by the `PartyAdminCap`; views are permissionless.
/// Mutation events carry the party and cap addresses, a stable kind/name pair,
/// and before/after counts; a populated clear carries counts only.
module party_roles::party_roles;

use partyos::party::{Party, PartyAdminCap};
use std::string::String;
use sui::event::emit;
use typed_set::typed_set as set;

public use fun role_name as ArtistRole.name;

// === Errors ===

/// A custom role name must not be empty.
const EEmptyCustomName: u64 = 0;
/// A custom role name exceeds the maximum length.
const ECustomNameTooLong: u64 = 1;

// === Constants ===

/// Maximum length of a custom role name in bytes.
const MAX_CUSTOM_NAME_LENGTH: u64 = 60;
/// Maximum number of roles a party may hold.
const MAX_ROLES: u64 = 12;

// === Keys ===

/// Dynamic-field key for a party's role set, stored as a `VecSet<ArtistRole>`
/// and managed through `typed_set`.
public struct RolesKey() has copy, drop, store;

// === Types ===

/// The kind of act a party represents. Closed enum + `Custom` escape hatch.
public enum ArtistRole has copy, drop, store {
    Artist,
    Producer,
    Dj,
    Composer,
    Songwriter,
    Band,
    Label,
    Collective,
    /// A user-defined role not covered by a canonical variant (validated).
    /// Prefer a canonical variant when one fits.
    Custom(String),
}

// === Events ===

/// Emitted when a role is added to a party.
public struct RoleAddedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    role_kind: u8,
    role_name: vector<u8>,
    roles_count_before: u64,
    roles_count_after: u64,
}

/// Emitted when a role is removed from a party.
public struct RoleRemovedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    role_kind: u8,
    role_name: vector<u8>,
    roles_count_before: u64,
    roles_count_after: u64,
}

/// Emitted when a party's entire role set is removed.
public struct RolesClearedEvent has copy, drop {
    party_id: address,
    admin_cap_id: address,
    roles_count_before: u64,
    roles_count_after: u64,
}

// === Role constructors ===

public fun artist(): ArtistRole { ArtistRole::Artist }
public fun producer(): ArtistRole { ArtistRole::Producer }
public fun dj(): ArtistRole { ArtistRole::Dj }
public fun composer(): ArtistRole { ArtistRole::Composer }
public fun songwriter(): ArtistRole { ArtistRole::Songwriter }
public fun band(): ArtistRole { ArtistRole::Band }
public fun label(): ArtistRole { ArtistRole::Label }
public fun collective(): ArtistRole { ArtistRole::Collective }

/// Builds a custom role. Aborts if empty or too long.
public fun custom(name: String): ArtistRole {
    assert!(!name.is_empty(), EEmptyCustomName);
    assert!(name.length() <= MAX_CUSTOM_NAME_LENGTH, ECustomNameTooLong);
    ArtistRole::Custom(name)
}

/// The canonical name of a role (its own string for `Custom`).
public fun role_name(self: &ArtistRole): String {
    match (self) {
        ArtistRole::Artist => b"Artist".to_string(),
        ArtistRole::Producer => b"Producer".to_string(),
        ArtistRole::Dj => b"DJ".to_string(),
        ArtistRole::Composer => b"Composer".to_string(),
        ArtistRole::Songwriter => b"Songwriter".to_string(),
        ArtistRole::Band => b"Band".to_string(),
        ArtistRole::Label => b"Label".to_string(),
        ArtistRole::Collective => b"Collective".to_string(),
        ArtistRole::Custom(name) => *name,
    }
}

// === Write API ===

/// Adds a role to the party. Aborts in `typed_set` if already held or the max
/// is reached.
public fun add_role(self: &mut Party, cap: &PartyAdminCap, role: ArtistRole) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let role_kind = role_kind(&role);
    let role_name = *role.name().as_bytes();
    let uid = self.uid_mut(cap);
    let roles_count_before = set::keys<RolesKey, ArtistRole>(uid, RolesKey()).length();
    set::add(uid, RolesKey(), role, MAX_ROLES);
    let roles_count_after = set::keys<RolesKey, ArtistRole>(uid, RolesKey()).length();
    emit(RoleAddedEvent {
        party_id,
        admin_cap_id,
        role_kind,
        role_name,
        roles_count_before,
        roles_count_after,
    });
}

/// Removes a role from the party. Aborts in `typed_set` if not held. The whole
/// field is dropped when the last role leaves.
public fun remove_role(self: &mut Party, cap: &PartyAdminCap, role: ArtistRole) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let role_kind = role_kind(&role);
    let role_name = *role.name().as_bytes();
    let uid = self.uid_mut(cap);
    let roles_count_before = set::keys<RolesKey, ArtistRole>(uid, RolesKey()).length();
    set::remove(uid, RolesKey(), role);
    let roles_count_after = set::keys<RolesKey, ArtistRole>(uid, RolesKey()).length();
    emit(RoleRemovedEvent {
        party_id,
        admin_cap_id,
        role_kind,
        role_name,
        roles_count_before,
        roles_count_after,
    });
}

/// Removes the party's entire role set. No-op if none is set.
public fun clear_roles(self: &mut Party, cap: &PartyAdminCap) {
    let party_id = object::id(self).to_address();
    let admin_cap_id = object::id(cap).to_address();
    let uid = self.uid_mut(cap);
    if (set::exists(uid, RolesKey())) {
        let roles = set::keys<RolesKey, ArtistRole>(uid, RolesKey());
        let roles_count_before = roles.length();
        set::clear<RolesKey, ArtistRole>(uid, RolesKey());
        let roles_count_after = set::keys<RolesKey, ArtistRole>(uid, RolesKey()).length();
        emit(RolesClearedEvent {
            party_id,
            admin_cap_id,
            roles_count_before,
            roles_count_after,
        });
    }
}

// === Views ===

/// Whether the party holds any roles.
public fun has_roles(self: &Party): bool {
    set::exists(self.uid(), RolesKey())
}

/// Whether the party holds the given role.
public fun has_role(self: &Party, role: ArtistRole): bool {
    set::contains(self.uid(), RolesKey(), &role)
}

/// The party's roles.
public fun roles(self: &Party): vector<ArtistRole> {
    set::keys(self.uid(), RolesKey())
}

// === Private Helpers ===

/// Returns the stable kind discriminator used in role events.
fun role_kind(self: &ArtistRole): u8 {
    match (self) {
        ArtistRole::Artist => 0,
        ArtistRole::Producer => 1,
        ArtistRole::Dj => 2,
        ArtistRole::Composer => 3,
        ArtistRole::Songwriter => 4,
        ArtistRole::Band => 5,
        ArtistRole::Label => 6,
        ArtistRole::Collective => 7,
        ArtistRole::Custom(_) => 8,
    }
}

// === Test Functions ===

/// Test-only accessor for every `RoleAddedEvent` field, in declaration order.
#[test_only]
public fun added_event_fields(
    event: &RoleAddedEvent,
): (address, address, u8, vector<u8>, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.role_kind,
        event.role_name,
        event.roles_count_before,
        event.roles_count_after,
    )
}

/// Test-only descriptive alias for `added_event_fields`.
#[test_only]
public fun role_added_event_fields(
    event: &RoleAddedEvent,
): (address, address, u8, vector<u8>, u64, u64) {
    added_event_fields(event)
}

/// Test-only accessor for every `RoleRemovedEvent` field, in declaration order.
#[test_only]
public fun removed_event_fields(
    event: &RoleRemovedEvent,
): (address, address, u8, vector<u8>, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.role_kind,
        event.role_name,
        event.roles_count_before,
        event.roles_count_after,
    )
}

/// Test-only descriptive alias for `removed_event_fields`.
#[test_only]
public fun role_removed_event_fields(
    event: &RoleRemovedEvent,
): (address, address, u8, vector<u8>, u64, u64) {
    removed_event_fields(event)
}

/// Test-only accessor for every `RolesClearedEvent` field, in declaration order.
#[test_only]
public fun cleared_event_fields(
    event: &RolesClearedEvent,
): (address, address, u64, u64) {
    (
        event.party_id,
        event.admin_cap_id,
        event.roles_count_before,
        event.roles_count_after,
    )
}

/// Test-only descriptive alias for `cleared_event_fields`.
#[test_only]
public fun roles_cleared_event_fields(
    event: &RolesClearedEvent,
): (address, address, u64, u64) {
    cleared_event_fields(event)
}
