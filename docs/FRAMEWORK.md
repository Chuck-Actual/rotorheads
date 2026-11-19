# Rotorheads framework

Agents read this before editing. When you change a mechanic, update that mechanic's section in this file before you finish. The next agent learns from this file, not from your chat.

## How an agent works here

- Open new agents on this same project. `.cursor/rules/dcs-host.mdc` is always applied and points here.
- Stay inside the mechanic you were asked about. FARP warehouse and pad stock are not part of a CTLD task.
- Edit `mission/src/rh/*.lua`. From `mission/`, run `lua5.1 tests/run.lua` and then `lua5.1 tools/build.lua`. Commit `mission/dist/rotorheads.lua` with the source change.
- The owner replaces `C:\Users\Hill\Saved Games\DCS\Missions\Rotorheads\rotorheads.lua`, quits the mission to the main menu, and hosts the newest `RH Campaign A.miz` or `RH Campaign B.miz` (see Campaign files). Replacing the script does not reload a mission that is already running.
- Editor changes go into the newest campaign file, saved under the same name with the server stopped. `RH Manual.miz` is only the start of a fresh war.

## What runs

`rh_loader.lua` loads MOOSE, then `rotorheads.lua`. `tools/build.lua` concatenates the modules in this order, each inside its own `pcall`:

`util`, `config`, `core`, `dcs`, `world`, `logistics`, `outposts`, `factories`, `redair`, `lives`, `markers`, `convoy`, `livemap`, `ctld`, `csar`, `main`

`RH.start` in `main.lua` loads the save, restores the world, then starts logistics, outposts, factories, red air, paratroopers, lives, markers, convoy, CTLD, CSAR, and the live map. `RH.persistence.save` writes `Saved Games\DCS\rotorheads\campaign.lua`. Everything under `RH.state` is that file.

`server/Hooks/rh_hooks.lua` is the server hook. It cannot see mission globals through `net.dostring_in`. Mission calls go through `a_do_script`.

`mission/src/rh/dcs.lua` is the only module that calls the DCS API and MOOSE. Tests replace `RH.dcs` with `mission/tests/fake_dcs.lua`.

## Mission files

| File | Role |
| --- | --- |
| `Missions\Rotorheads\rotorheads.lua` | The campaign script the mission loads. |
| `Missions\Rotorheads\Moose_.lua` | MOOSE. Load it before the campaign script. |
| `Missions\RH Manual.miz` | The start of a fresh war. FARP warehouse flags live in its `warehouses` file. |
| `Missions\RH Campaign A.miz`, `RH Campaign B.miz` | The war written back into a mission by the hook. The newest one is hosted and is the one to open in the editor. |
| `Saved Games\DCS\rotorheads\campaign.lua` | The war: FARPs, lives, factories, pad stock. |
| `Saved Games\DCS\rotorheads\world.lua` | Ground units and statics captured from the running mission. |

`static1-4` and `static1-5` are the editor FARP pads (unit ids 1000011 and 1000023). The mission editor names statics that way. They are heliports, not a script group. Their warehouse entries must keep `dynamicSpawn = true` and `unlimitedFuel`, `unlimitedMunitions`, and `unlimitedAircrafts` false. `mission/tools/patch_farp_warehouses.py` rewrites those two entries. Writing `0` with `setLiquidAmount` or `setItem` does not turn an unlimited warehouse into an empty one.

## Campaign files

`server/Hooks/rh_hooks.lua` writes the war into a mission about every 30 seconds and when the mission stops. It uses `mission/src/rh/miz.lua`, installed beside the hook as `rh_miz.lua`. The hosted file is locked, so it writes the other one of `RH Campaign A.miz` and `RH Campaign B.miz` (from `RH Manual.miz` it writes the older slot). The scheduled restart hosts the file it just wrote. On the first frame, before the campaign script loads, a hosted slot that is older than the other slot is swapped for the newer one. Paths come from `lfs.writedir()`, so the same hook works in `Saved Games\DCS` and in `Saved Games\DCS.dcs_serverrelease` on another PC.

`miz.patch` works from `world.lua`. A group already in the file is moved in place and keeps its ids and warehouse. A name in `baseline` or `seen` that is no longer alive leaves the file, with its warehouse entry. A FARP in `world.farps` with no pad yet, including one marked this session, is written as a `Heliports` static (`FARP`, `FARPS`, dynamic spawn, hot start allowed) plus its `config.farp.services` pieces. Each new pad gets a `warehouses` entry: limited fuel, munitions, and aircraft, 999 of each helicopter, no planes, and `jet_fuel.InitFuel` set from the saved kilograms in tons. A logistics center pad gets the unlimited entry. Pads already in the file only have `InitFuel` updated. `persistence/` is dropped from the copy. The trigger zone `RH_SAVE_COPY` marks the file as a save, with property `savedAt` set to the world save time.

When `RH_SAVE_COPY` is present, `world.restore` keeps the units as they are in the file: nothing is respawned, moved back, or removed, and new editor units are adopted. `logistics.dropDeletedFarps` retires a built FARP whose pad is gone (deleted in the editor), and moves the record of a pad that was moved. A marked FARP with no pad still spawns from script. When `savedAt` is more than 5 minutes older than the world save, the file is treated as stale: the old restore runs and the host is told to use the newer file.

A FARP built during a session is spawned at once only on the next restart, when it is already in the mission file. DCS does not finish setting up a heliport created by a script after mission start.

## Mechanics

### CTLD

`ctld.lua` builds the MOOSE CTLD menu from `config.lua` `troops`, `vehicles`, and `kits`. Every buildable group is a late-activated mission group named `RH_TPL_BLUE_*`. If a kit template is missing, `ctld.ensureKitTemplate` copies `RH_TPL_BLUE_HMMWV_TOW` so the crate still appears. Built vehicles are moved behind the helicopter by `ctld.placeBehind`.

`config.testVehicleCrates` is `1` while ground units are being tested. The real count stays on each vehicle. Set the override to `nil` to use those counts again. Logistics Centers and ships have unlimited crates. General supply is loaded only there. Its template is `RH_TPL_BLUE_SUPPLY`, separate from the FARP kit. Build does not accept general supply, and it does not mark a FARP. Only the FARP Crate kit marks a FARP. After general supply is dropped at a FARP, park within 150 m of that FARP tent and use F10 > CTLD > **Return crates to tent** (also under Manage Crates). The check uses the tent, not the pad. Each general-supply crate adds 5 to that FARP. Those crates can then be drawn back out at the tent as ground-unit crates.

Not in this build, and not to be assumed: an "all crates or one crate" menu, a flattened troop menu, or joining NASAMS and Roland pieces into one group.

### FARPs and logistics

Player FARPs are marked in the mission and written into the next campaign file as real pads (see Campaign files). `logistics.spawnBuilt` only fills the warehouse of a pad that is already there. When the hosted file has no pad for it, it falls back to `SPAWNSTATIC:InitFARP` (dynamic spawn on, and hot start left as a player choice). A pad with hot start locked off forces every spawn cold and hides that switch. The dynamic spawn screen is where the player picks the helicopter, the pylon loadout, and hot or cold. Air-to-ground missiles are not on that shelf until a delivery is in the warehouse. `RH_FARP_Bassel` in the current save is the logistics center at the tent, and it is not built.

The editor pads and player-built pads share one warehouse rule. `warehouseReset` is a one-time clear: the first launch after that flag is missing writes 0 kg of jet fuel and 0 of the saved air-to-ground missiles, including the old Hellfire and Vikhr grant, then sets the flag. A later delivery is saved and comes back on the next launch. A new pad starts with 0 kg of jet fuel and no air-to-ground missiles. Guns, rockets, pods, air-to-air missiles, and helicopter dynamic-spawn slots are written back to the high shelf counts on each launch. Fuel and air-to-ground missiles are not. `logistics.capturePads` reads the live warehouse about every 30 seconds, after a 25 second hold so the startup write cannot be saved as an empty tank. The numbers land on `RH.state.padStock` and on that FARP's `liquids` and `ammoItems`. The next launch writes those numbers back. A count at or above one million is treated as unlimited and is not saved. A logistics center pad is not written, so the airfield warehouse stays unlimited.

Names come from `config.farp.names` (COPPERHEAD, RATTLESNAKE, MUSTANG, LONGBOW, DAGGER, OUTLAW, WARHORSE, SWITCHBLADE, IRONCLAD, GHOST). A name is taken until that FARP record is gone. The map label sits just east of the tent, white on a dark box, for blue: the name, then `Crates: N`. The mark is created once and its text is updated in place. It stays up. The blue load circle is separate and lasts 60 seconds. CTLD > Show logistics zones draws those circles again and registers the same circle as the CTLD load zone. A logistics center uses a 500 m circle. A FARP tent uses 150 m. A saved `loadZoneReady` flag does not skip that zone on the next launch. `RH_FARP_Bassel` stays the logistics center and reads `Crates: unlimited`.

The Chinook and the C-130 move fuel and air-to-ground missiles with the DCS rearm/refuel window while the aircraft is being serviced by that FARP pad. This script does not define a drop radius for that warehouse, does not spawn that cargo, and does not add a count when the aircraft unloads. It only records whatever the FARP warehouse already holds. The 150 m tent circle, and the 500 m logistics-center circle, are the CTLD crate zones. Cargo left on the ground in those circles does not enter the warehouse. Crate stock is a different number, owned by the CTLD menu.

A script-built FARP that lands within 400 m of an editor pad or tent is a duplicate. `logistics.dropStackedFarps` deletes that copy, including `FARP 01` and its tent, depots, and Humvee, and the editor pad keeps the crate count. A marked FARP in an empty field is still spawned.

The editor tent is a CTLD load zone. Troops can always be picked up there. Ground-unit crates can be picked up only while the FARP stock covers them. Hovering into the zone does not load crates. `logistics.oneHumvee` keeps a single M1025 (DCS type Hummer) 25 m east of the tent and deletes any other service Hummer within 120 m of that spot. A crate-built vehicle whose name contains `RH_TPL_` or `#` is left alone. A renamed FARP no longer restores the old service Humvee from the world save. The same pass writes the pad's saved fuel and air-to-ground missiles, so rearm uses the warehouse that was already in the mission.

The CH-47 loads and unloads crates with the rearm/refuel cargo menu, which is what changes the aircraft weight. CTLD Get Crates only puts the crates on the ground for that helicopter. UH helicopters still load and drop with CTLD. Return crates to tent counts the crates on the ground after that unload. General supply is not taken into the tent until that command.

### MASH and CSAR

A MASH exists only after a player builds the 6-crate MASH kit. An editor zone named `MASH` is not registered. On start, `logistics.spawnPlayerMashes` drops every saved MASH that a player did not build, deletes the hospital tents (including the one the old zone left at the north end of the airfield), and spawns tents only for player MASHes. The logistics tent stays. The world save does not keep hospital tents, because `logistics` spawns them from `RH.state.mashes`.

The only build check is distance. `logistics.validateMashSite` allows the build when the point is within 1 km of a FARP or Logistics Center, including that site's load points. Pads, statics, and ground units do not block it. Outside that 1 km the build is refused and the pilot is told they are not within 1000 m of a FARP or Logistics Center. CTLD's load circle is separate: 150 m around a FARP tent (`config.farp.loadRadius`) and 500 m around a logistics center (`config.farp.lcLoadRadius`). `nobuildinloadzones` is off, so a crate set can be built inside that circle. The hospital is a `Tent04` named `<name> tent`. `ctld.ensureKitTemplate` copies `RH_TPL_BLUE_MASH_KIT` when that group is missing, so **FARP AND MASH** lists MASH Crate. Building it calls `logistics.buildMash`.

CTLD Pack crates decommissions a player MASH within 100 m. `logistics.packMash` deletes the tent, the map mark, and the save entry. CTLD then places the same 6 MASH crates on the ground beside the helicopter. Those are normal cargo statics: a utility helicopter loads them with CTLD, and the Chinook loads them from the rearm and refuel cargo menu. Packing does not take crates out of FARP stock. The crates can be hauled to a FARP or a logistics center and returned there like any other crate.

Each player MASH keeps a blue map mark that says `MASH`, sitting just east of the tent. The mark is drawn again on start and about every 30 seconds, so a MASH already in the save gets one too. The save key stays unique. The name pilots see is the 10 km MGRS square, such as `MASH YE72`: the 100 km letters plus the first easting digit and the first northing digit. CSAR > MASH > Check MASH status, and `-mash`, list every MASH that way, closest to the player first, as `MASH YE72 - 1.2 km - 4/30 pilots`.

CSAR uses `RH_TPL_DOWNED_PILOT` and the MOOSE CSAR module. Drop-off is that tent, on the ground, within 150 m. A MASH holds 30 pilots. A full one stops taking rescues until a transport task frees slots.

A crash, ejection, stranded crew, or disembark inside the block does not leave a downed pilot. The block is 400 m around every FARP pad and load point (`config.csar.blockFarp`), 400 m around a friendly ship or small pad, and 2500 m around a friendly airfield beacon (`config.csar.blockAirfield`). The pilot hears "No CSAR" and the life rules are unchanged. Pilots already standing in that block, including ones reloaded from the CSAR save, are deleted on launch and about every 30 seconds. `world` does not write `RH Pilot` or `Downed Pilot` groups into the next mission file.

### The rest

Outposts, factories, red air, paratroopers, lives, map markers, convoys, and the live map each have their own module and start from `RH.start`. Red ground units in this build spawn from templates again. They are not saved and restored as live groups. That persistence was removed with the MASH rollback.

## Do not repeat

- Do not rebuild a FARP with `coalition.addGroup`. The dynamic-spawn list uses `coalition.addStaticObject` with `dynamicSpawn = true`, or the pad already saved in the mission.
- Do not zero a warehouse to make it limited.
- Do not respawn units from `persistence/Rotorheads.json` inside a `.miz`.
- Do not export over the mission that is being hosted. Write the other campaign slot.
- Do not compute the zip checksum bit by bit. The hook runs on the host's main thread every 30 seconds.
