# Event payload inventory

Events preserve identifiers, authorization provenance, compact business context,
and meaningful state changes. Bios, CTA labels/URLs, and bulk role/tag text stay
in object storage and are read on demand. Setters still validate, authorize,
and write equal replacements without emitting; first attachment (including an
empty CTA list) emits, and absent clear stays silent.

## All declared events

`party_id` and `admin_cap_id` retain object identity and authorizing capability.
Counts retain transition context. Country/language codes are validated two-byte
codes (at most ten ordered languages); short role/tag/genre names identify the
single changed display value. Media quilt IDs are fixed-width references.
Genre clear retains at most twenty removed relationship IDs, useful because
those relationships are destroyed. Phantom `Data` identifies a platform slice.
The legacy wrapper events remain inert; their declarations are unchanged.

| Package | Event | Retained fields (declaration order) |
|---|---|---|
| `lib/platform_link` | `PlatformLinkSetEvent<phantom Data>` | `parent_id`, `existed_before`, `exists_after` |
| `lib/platform_link` | `PlatformLinkRemovedEvent<phantom Data>` | `parent_id`, `existed_before`, `exists_after` |
| `party_cta` | `CtasSetEvent` | `party_id`, `admin_cap_id`, `existed_before`, `previous_count`, `count` |
| `party_cta` | `CtasClearedEvent` | `party_id`, `admin_cap_id`, `previous_count` |
| `party_genre` | `GenreAddedEvent` | `party_id`, `admin_cap_id`, `genre_id`, `genre_name`, `genre_count_before`, `genre_count_after`, `max_genres` |
| `party_genre` | `GenreRemovedEvent` | `party_id`, `admin_cap_id`, `genre_id`, `genre_count_before`, `genre_count_after` |
| `party_genre` | `GenresClearedEvent` | `party_id`, `admin_cap_id`, `genre_count_before`, `genre_count_after`, `genre_ids_before` |
| `party_media` | `MediaSetEvent` | `party_id`, `admin_cap_id`, `existed_before`, `previous_quilt`, `quilt` |
| `party_media` | `MediaClearedEvent` | `party_id`, `admin_cap_id`, `previous_quilt` |
| `party_platform_link` | `LinkSetEvent<phantom Data>` | `party_id` |
| `party_platform_link` | `LinkClearedEvent<phantom Data>` | `party_id` |
| `party_profile` | `PartyProfileSetEvent` | `party_id`, `admin_cap_id`, `had_profile`, `previous_country`, `previous_languages`, `country`, `languages` |
| `party_profile` | `PartyProfileClearedEvent` | `party_id`, `admin_cap_id`, `previous_country`, `previous_languages` |
| `party_roles` | `RoleAddedEvent` | `party_id`, `admin_cap_id`, `role_kind`, `role_name`, `roles_count_before`, `roles_count_after` |
| `party_roles` | `RoleRemovedEvent` | `party_id`, `admin_cap_id`, `role_kind`, `role_name`, `roles_count_before`, `roles_count_after` |
| `party_roles` | `RolesClearedEvent` | `party_id`, `admin_cap_id`, `roles_count_before`, `roles_count_after` |
| `party_tags` | `TagAddedEvent` | `party_id`, `admin_cap_id`, `tag`, `tag_count_before`, `tag_count_after` |
| `party_tags` | `TagRemovedEvent` | `party_id`, `admin_cap_id`, `tag`, `tag_count_before`, `tag_count_after` |
| `party_tags` | `TagsClearedEvent` | `party_id`, `admin_cap_id`, `tag_count_before`, `tag_count_after` |

Pure `party_music`, `party_social`, and `party_pro_link` payload packages declare
and emit no events. `lib/platform_link` emits the authoritative platform events;
`party_platform_link` retains its cap gate and does not emit duplicate events.
There are 19 declarations: 17 active events and two inert compatibility types.

## Source-derived BCS payload bounds

These are serialized **payload bytes**, not total transaction/event-envelope
sizes, gas measurements, or claims about gas savings. An address/u256 is 32
bytes, u64 is 8, bool is 1; vector lengths use ULEB128, and Option has a one-byte
presence prefix. Maximums use storage-validation bounds and reachable changed
writes. Type tags are outside these payload sizes.

| Event | Previous maximum | Current maximum | Reason |
|---|---:|---:|---|
| `CtasSetEvent` | 82,605 | 81 | Remove two ordered sets of 20 labels (60 B) and URLs (2,000 B) |
| `CtasClearedEvent` | 41,334 | 72 | Remove the deleted content snapshot |
| `PartyProfileSetEvent` | 17,129 | 135 | Remove two 300 B short and 8,192 B long bios; retain codes |
| `PartyProfileClearedEvent` | 8,596 | 99 | Remove deleted bios; retain codes |
| `GenreAddedEvent` | 1,419 | 185 | Replace 19+20 IDs with counts; retain 64 B name and changed ID |
| `GenreRemovedEvent` | 1,346 | 112 | Replace 20+19 IDs with counts |
| `GenresClearedEvent` | 706 | 721 | Retain <=20 removed IDs, replace empty result list with transition counts |
| `RoleAddedEvent`, `RoleRemovedEvent` | 142 | 142 | Retain one <=60 B role name, kind, and counts |
| `RolesClearedEvent` | 826 | 80 | Remove 12 names and kind list |
| `TagAddedEvent`, `TagRemovedEvent` | 131 | 131 | Retain one <=50 B tag and counts |
| `TagsClearedEvent` | 1,611 | 80 | Remove 30 tags |
| `MediaSetEvent` | 129 | 129 | Two fixed-size quilt IDs |
| `MediaClearedEvent` | 96 | 96 | Removed fixed-size quilt ID |
| `PlatformLinkSetEvent<Data>` | `116 + ULEB(T) + T` | 34 | Remove duplicated type name (`T` UTF-8 bytes), lengths and two hashes |
| `PlatformLinkRemovedEvent<Data>` | `75 + ULEB(T) + T` | 34 | Remove duplicated type name, length and hash |
| Inert `LinkSetEvent<Data>`, `LinkClearedEvent<Data>` | 32 | 32 | Not emitted |

Platform previous formulas describe replacement/removal with present data;
initial set uses an empty prior digest and is 32 bytes smaller. Generic `Data`
had no module-level type-name bound. The new primitive also avoids event-only
BCS serialization and hashing, while comparing the full value for change
detection. Actual app/API/indexer/CLI source had no consumers of those hashes;
SDK generated codecs and wire assertions require matching schema updates.

CTA set bound: `81 + 4 + 2*20*((1+60)+(2+2000)) = 82,605`.
Profile code context is at most `4 + (1+10*3) = 35` bytes per side.
Tests serialize max-content and tiny/empty-content events to verify that text
length no longer controls event payload size, and retain storage, authorization,
no-op, optional/empty, relationship, and validation assertions.
