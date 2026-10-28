# AnticrashRAID

Keeps RAID: WW2 from crashing on broken network messages (lag, mods, malicious players).
Port of Anticrash by TdlQ (PAYDAY 2). Author of this port: BangL.

## What it does

| Protection | Where |
| --- | --- |
| Every handler of `ConnectionNetworkHandler` and `UnitNetworkHandler` runs protected; a failure is logged with sender and parameters | `AnticrashRAID.lua` (`install`) |
| Text parameters of the messages must be valid UTF-8, otherwise they are replaced by `*ill-formed text*` | `lua/text_fields.lua` (generated), `utf8_clean` |
| Outfit strings are checked (weapon factory ids, melee weapon) before they are applied | `lua/connectionnetworkhandler.lua` |
| Blueprint strings: unknown factory id -> empty blueprint, parts are rebuilt from the default blueprint | `lua/weaponfactorymanager.lua` |
| Unknown stance code of a player husk is rejected | `lua/unitnetworkhandler.lua` |
| Unit spawns in `HuskPlayerMovement:anim_cbk_spawn_melee_item` and in the projectile messages are skipped when the unit is not loaded | `protect_spawn` |
| `ObjectInteractionManager:end_action_interact` is protected | `install` |

Differences to the PAYDAY 2 version: no ban (RAID has no ban list, `kick_peer` message id 0 only puts the
peer on the kicked list of the session), no loot cleaner, no mod list text check, no walk nav point /
underbarrel handlers (they do not exist in RAID), no `is_server_ok` check (RAID lobbies only carry numbers).

## Settings (Options > Anticrash)

Per source: `default`, `unprotected` (no protection for it), `quiet` (log only), `chat`, `kick`.
Defaults are mild: **chat** (at most one message per source and peer every 30 s), nothing is kicked
unless chosen. A kick needs 3 failures of the same peer within 60 s and only works as host.
The menu lists the manual sources and every source that failed once. Settings: `saves/AnticrashRAID.txt`.

## Updating the text fields

After a game update that changes `settings/network.network_settings`:

    python3 tools/gen_text_fields.py <extracted>/settings/network.network_settings > lua/text_fields.lua

Auth tickets and the outfit signature are binary, they are excluded in the script (`EXCEPTIONS`).

## Untested

Written from the decompile and a PD2 comparison, not played yet: the menu, the real handlers under load, the
outfit check with other mods' weapons, multiplayer. If something misbehaves, set the matching source to
`unprotected` in the menu (e.g. `unpack_blueprint_from_string`).
