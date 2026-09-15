// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Attaches `PlatformLink<Data>` records to a `Party` — one independent link per
/// platform type (`set_link<XData>`, `set_link<SpotifyData>`, …), each in its own
/// dynamic field keyed by `Data`. Adding one platform never rewrites another's,
/// and a new platform needs no change here.
///
/// This one module serves every platform (social, music, anything) because it is
/// generic over `Data`; the payload types live in their own small packages
/// (`party_social`, `party_music`, …). All writes are gated by the
/// `PartyAdminCap` via `uid_mut`; views are permissionless. Storage mutations
/// emit the authoritative rich `platform_link::PlatformLinkSetEvent` or
/// `platform_link::PlatformLinkRemovedEvent` from the primitive, so the event
/// carries the parent, defining-ID-qualified payload type, existence
/// transition, and bounded payload summaries. This module adds no replacement
/// event.
module party_platform_link::party_platform_link;

use partyos::party::{Party, PartyAdminCap};
use platform_link::platform_link::{Self, PlatformLink};

// === Events ===

/// Legacy compatibility declaration for the former wrapper set event.
///
/// This type is inert: `set_link` delegates to `platform_link::set`, which
/// emits the authoritative `PlatformLinkSetEvent<Data>` instead.
#[allow(unused_field)]
public struct LinkSetEvent<phantom Data> has copy, drop {
    party_id: ID,
}

/// Legacy compatibility declaration for the former wrapper clear event.
///
/// This type is inert: `clear_link` delegates to `platform_link::clear`, which
/// emits the authoritative `PlatformLinkRemovedEvent<Data>` when a link exists.
#[allow(unused_field)]
public struct LinkClearedEvent<phantom Data> has copy, drop {
    party_id: ID,
}

// === Write API ===

/// Sets (or replaces) a platform's link on the party. The primitive emits one
/// `PlatformLinkSetEvent<Data>` for an insertion or changed replacement; an
/// equal replacement still writes silently.
public fun set_link<Data: copy + drop + store>(
    self: &mut Party,
    cap: &PartyAdminCap,
    link: PlatformLink<Data>,
) {
    platform_link::set(self.uid_mut(cap), link);
}

/// Clears a platform's link from the party. Cap authorization is checked before
/// the existence check. A present link delegates to the primitive, which emits
/// one `PlatformLinkRemovedEvent<Data>`; absent and repeated clears are silent.
public fun clear_link<Data: copy + drop + store>(self: &mut Party, cap: &PartyAdminCap) {
    // Cap-gate first: a wrong cap must abort even when no link is present, so
    // authorization never depends on state the caller can't be sure of.
    let uid = self.uid_mut(cap);
    if (platform_link::exists_<Data>(uid)) {
        platform_link::clear<Data>(uid);
    }
}

// === Views ===

/// Whether the party has a link for this platform.
public fun has_link<Data: copy + drop + store>(self: &Party): bool {
    platform_link::exists_<Data>(self.uid())
}

/// The party's link for this platform, if set.
public fun link<Data: copy + drop + store>(self: &Party): Option<PlatformLink<Data>> {
    platform_link::get<Data>(self.uid())
}
