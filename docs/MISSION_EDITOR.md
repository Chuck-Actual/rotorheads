# Building the mission in the DCS Mission Editor

The scripts find everything by name, so the mission file only needs objects placed with the names below.
Nothing has to be scripted by hand. Start with one factory, one outpost, two areas of operation and one FARP,
check it works, then grow the map.

This page builds the starting mission (`RH Manual.miz`). Once the war is running, the server hook writes it
into `RH Campaign A.miz` or `RH Campaign B.miz` beside the mission (see [LOCAL_TESTING.md](LOCAL_TESTING.md)).
Open the newest one to inspect, add, move, or delete units and FARPs, save it under the same name, and host it.
Leave the hidden trigger zone `RH_SAVE_COPY` in place: it tells the campaign that the file is a save.

The examples use the **Syria** map (Latakia → Aleppo front, as on Rotorheads), but any map works.

## 1. Load the scripts

Run `tools\windows\install.ps1` first (see [LOCAL_TESTING.md](LOCAL_TESTING.md)). It puts `Moose_.lua` and
`rotorheads.lua` in `Saved Games\DCS\Missions\Rotorheads\`. Then create two triggers that load them from disk:

| Trigger | Type | Condition | Action |
| --- | --- | --- | --- |
| `Load MOOSE` | MISSION START | (none) | DO SCRIPT → `dofile(lfs.writedir() .. [[Missions\Rotorheads\Moose_.lua]])` |
| `Load Rotorheads` | ONCE | TIME MORE (2) | DO SCRIPT → `dofile(lfs.writedir() .. [[Missions\Rotorheads\rotorheads.lua]])` |

To change settings without rebuilding, put `RH_CONFIG_OVERRIDES = { ... }` above the `dofile` line in the second
trigger (any key from `mission/src/rh/config.lua`).

Loading from disk needs the desanitized `MissionScripting.lua` (which the campaign needs anyway to save) and
means script updates apply on the next mission start. If you would rather embed the scripts in the `.miz`, use
DO SCRIPT FILE with the same two files instead, and re-pick them after every update.

## 2. Trigger zones

Use circular trigger zones. The radius matters where noted.

| Name pattern | What it is | Radius |
| --- | --- | --- |
| `RH_FACTORY_<Name>` | REDFOR factory. Place two red static buildings (e.g. *Workshop A*, *Factory* from *Structures*) inside the zone. Destroying all statics inside disables the factory. | covers the buildings, ~300 m |
| `RH_AO_<Name>` | Area of operations REDFOR occupies. Three red groups garrison it and are replaced from the nearest factory by road. | 2–4 km |
| `RH_OUTPOST_<Name>` | REDFOR outpost. Stack three red *Container red* statics inside. | covers the containers, ~100 m |
| `RH_REDHELI_<Name>` | Where Mi-26 repair flights and Mi-28 Havocs launch from (red FARP or airbase). | any |
| `RH_REDAIR_<Name>` | Where red fighters scramble from (red airbase). | any |
| `RH_PARA_<Name>` | Optional. Where paratroopers can be dropped after a restart. Defaults to the AOs. | 3–5 km |
| `RH_BLUEZONE_<Name>` | Friendly area. MASHes can only be built inside a blue zone. One per Alpha / Bravo / Charlie AO is typical. | 10–15 km |
| `RH_FARP_<Name>` | A FARP or airfield you start the war with. Put the zone on the FARP's main pad. If it is within 1 NM of an airfield it becomes a **Logistics Center** with unlimited crates. | ~250 m |
| `MASH <Name>` | Optional starting MASH. | ~100 m |

An AO "belongs" to the nearest outpost within 20 km. Capturing that outpost stops the AO from being reinforced,
which is how the front moves.

## 3. Template groups

Tick **Late Activation** on every template. The scripts copy them. Each one is a normal group placed anywhere
(off to the side of the map is fine). Missing templates are skipped with a line in `dcs.log`, so you can start small.

### REDFOR (country: Russia or Syria)

| Group name | Suggested contents |
| --- | --- |
| `RH_TPL_RED_ARMOR` | 2× T-72B |
| `RH_TPL_RED_IFV` | 2× BMP-2 |
| `RH_TPL_RED_APC` | 2× BTR-80 |
| `RH_TPL_RED_AAA` | ZSU-23-4 Shilka + Ural |
| `RH_TPL_RED_SAM` | SA-8 Osa or SA-13 Strela-10 |
| `RH_TPL_RED_ARTY` | 2× 2S9 Nona |
| `RH_TPL_RED_INF` | 6× infantry AK + RPG |
| `RH_TPL_RED_PARA_RPG` | 4× infantry RPG (paratroopers) |
| `RH_TPL_RED_PARA_MANPADS` | 2× SA-18 Igla + 2× AK |
| `RH_TPL_RED_MI26` | 1× Mi-26 (helicopter group) |
| `RH_TPL_RED_MI28` | 1× Mi-28N with guns/rockets (Shturm optional) |
| `RH_TPL_RED_MIG29` | 2× MiG-29A, air-to-air loadout |
| `RH_TPL_RED_F4` | 2× F-4E, air-to-air loadout |
| `RH_TPL_RED_INSURGENT_TECH` | 2× technical / pickup with DShK (insurgents country) |
| `RH_TPL_RED_INSURGENT_INF` | 6× insurgent infantry |

### BLUFOR (country: USA or CJTF Blue)

Troop squads (all infantry). Only build the sizes you need:

| Group name | Contents |
| --- | --- |
| `RH_TPL_BLUE_INF_STD_12` / `_6` | M4 riflemen + M249 + RPG |
| `RH_TPL_BLUE_INF_AT_12` / `_6` / `_2` | RPG / Javelin heavy |
| `RH_TPL_BLUE_INF_AA_12` / `_6` / `_2` | Stinger MANPADS + M4 |
| `RH_TPL_BLUE_INF_MORTAR_10` / `_6` | 2B11 mortars + M4 |
| `RH_TPL_BLUE_INF_JTAC_6` / `_2` | M4 + M249 (pair with a JTAC script if you like) |
| `RH_TPL_BLUE_INF_SOF_6` / `_4` | M249 + RPG + Stinger |

Vehicles built from crates (one group each, see `mission/src/rh/config.lua` for crate counts):
`RH_TPL_BLUE_HMMWV_JTAC`, `RH_TPL_BLUE_HMMWV_TOW`, `RH_TPL_BLUE_STRYKER`, `RH_TPL_BLUE_STRYKER_MGS`,
`RH_TPL_BLUE_BRADLEY`, `RH_TPL_BLUE_ABRAMS`, `RH_TPL_BLUE_LEO2`, `RH_TPL_BLUE_M109`, `RH_TPL_BLUE_VULCAN`,
`RH_TPL_BLUE_GEPARD`, `RH_TPL_BLUE_AVENGER`, `RH_TPL_BLUE_ROLAND`, `RH_TPL_BLUE_NASAMS_RADAR`,
`RH_TPL_BLUE_NASAMS_C2`, `RH_TPL_BLUE_NASAMS_LN`, `RH_TPL_BLUE_HAWK`, `RH_TPL_BLUE_AMMO` (M939),
`RH_TPL_BLUE_FUEL` (M978).

Construction kits. The kit group is a placeholder that the script removes and replaces with the real structure,
so any single cheap vehicle works (e.g. one HMMWV):
`RH_TPL_BLUE_FARP_KIT`, `RH_TPL_BLUE_MASH_KIT`, `RH_TPL_BLUE_OUTPOST_KIT`, `RH_TPL_BLUE_UHREPAIR_KIT`.

Other:

| Group name | Contents |
| --- | --- |
| `RH_TPL_BLUE_MASH` | What a built MASH looks like: e.g. a field hospital tent + ambulance |
| `RH_TPL_DOWNED_PILOT` | 1× infantry soldier (MOOSE CSAR uses it for downed pilots) |
| `RH_TPL_CONVOY_TRUCK` | 2× ZIL-131, placed in a **neutral** country so REDFOR ignores them |
| `RH_TPL_CONVOY_ESCORT` | 1× HMMWV (blue) |

## 4. Player slots

Rotorheads uses **dynamic slots**. On each FARP / airfield you want players to spawn at, open the warehouse
settings, enable *Dynamic Spawn*, and allow the airframes you want (UH-1H, UH-60L, Mi-8, CH-47F, AH-64D, Ka-50,
Mi-24P, OH-58D, Gazelle, C-130J…). FARPs built in-game are written into the campaign file as pads with dynamic slots enabled.

Keep the four landing spots empty. A crate under a spawn spot blows up the helicopter, and one beside it
starts the helicopter running a foot in the air. At launch the mission removes any static object within 40 m of
a FARP pad and any vehicle within 35 m. Put tents, depots, windsocks, and Humvees 45 m out or farther.

Add the ships as normal ship groups. If you name the units `Tarawa` and `Theodore Roosevelt` (or change
`ships` in `config.lua`) they become crate and troop load points.

## 5. Radios

Rotorheads conventions: **250.000 MHz AM** for traffic and UH coordination, **30.000 MHz FM** for tactical
(rifle calls, AH coordination). Preset them in the slots where the module supports it.
