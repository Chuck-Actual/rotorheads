# Testing on your own PC

This gets the campaign running in your normal DCS game first. Once it works, the same files go to the dedicated
server (see the end of this page).

Players spawn with **dynamic slots** at blue airfields and FARPs, so there are no slotted aircraft to set up.

## Where everything lives

| Folder | What is in it |
| --- | --- |
| `C:\Rotorheads\` | Your copy of this project. Any folder works; the steps below assume this one. |
| `%USERPROFILE%\Saved Games\DCS\Missions\Rotorheads\` | `rotorheads.lua` and `Moose_.lua` (copied by the install script). Save your `.miz` here too. |
| `%USERPROFILE%\Saved Games\DCS\Scripts\Hooks\rh_hooks.lua` | The server hook (chat commands, restart timer). Copied by the install script. |
| `%USERPROFILE%\Saved Games\DCS\rotorheads\` | Campaign saves (`campaign.lua`, `world.lua`, `ctld.csv`, `csar.csv`) and `livemap.json`. **Delete it to start a fresh war.** |
| `RH_Editor.miz`, next to the mission you launched | A copy of that mission with the saved ground units, FARPs, and statics written in. Open this in the Mission Editor when you need to fix something by hand. The file you launched is left unchanged. |
| `%USERPROFILE%\Saved Games\DCS\Logs\dcs.log` | The log. Every campaign line starts with `[RH]`. |
| `<DCS install>\Scripts\MissionScripting.lua` | Must be edited so the campaign can save (the install script does it). |

If your Saved Games folder is `DCS.openbeta`, the script finds that instead.

## Step 1: Get the files onto your PC

1. Create a repository for this project from the agent view, then on your PC open PowerShell and run:
   ```powershell
   git clone <your repo URL> C:\Rotorheads
   ```
   No Git? Install [Git for Windows](https://git-scm.com/download/win), or use **Code → Download ZIP** on the
   repository page and extract it so that `C:\Rotorheads\README.md` exists.

## Step 2: Run the install script

1. Start menu → type `PowerShell` → right-click **Windows PowerShell** → **Run as administrator**
   (needed to edit `MissionScripting.lua` under Program Files).
2. Run:
   ```powershell
   cd C:\Rotorheads
   powershell -ExecutionPolicy Bypass -File tools\windows\install.ps1 -Desanitize
   ```
3. It prints every file it copied. All lines should be green. Yellow lines say what to fix: usually
   "re-run as Administrator" or "pass -DcsInstallDir" if DCS is installed somewhere unusual, for example
   `-DcsInstallDir "D:\DCS World"`.

Re-run step 2 (with `-Desanitize`) after every DCS update, because updates restore `MissionScripting.lua`.

## Step 3: Build a small test mission

Start small: one airfield, one FARP zone, one red factory, one outpost, one area. Open DCS → **Mission Editor** →
**New**, pick **Syria**, and do the following. [MISSION_EDITOR.md](MISSION_EDITOR.md) has the full naming
reference for later.

### 3a. Blue airfield with dynamic spawn

1. Click **Bassel Al-Assad** airfield (on the coast near Latakia). Set its coalition to **Blue**.
2. In the airfield's panel open the **Warehouse** / dynamic spawn settings: tick **Dynamic Spawn**
   (and **Allow hot start** if you like). Tick **Unlimited aircraft**, **Unlimited munitions** and
   **Unlimited fuel** for now.
3. Place a circular **trigger zone** on the main apron named `RH_FARP_Bassel`, radius ~250 m.
   Because it is within 1 NM of an airfield it becomes a **Logistics Center** (unlimited crates).
4. Place a second trigger zone near the apron named `MASH Bassel`, radius ~100 m. This is your starting MASH
   for CSAR tests.
5. Place a big trigger zone named `RH_BLUEZONE_West`, radius ~15 km, centred on the airfield (MASHes may only
   be built inside a blue zone).

Do the same Dynamic Spawn ticking on any other airfield or FARP you want to spawn at. Blue airfields or FARPs
captured later keep the setting.

### 3b. A small red front about 20–30 km east

1. **Factory**: two red static buildings (Structures → e.g. *Workshop A*) next to each other, country Russia.
   Put a trigger zone `RH_FACTORY_Test` (~300 m) over them.
2. **Outpost**: three red *Container red* statics together, ~10 km closer to the airfield than the factory.
   Trigger zone `RH_OUTPOST_Test` (~100 m) over them.
3. **Area of operations**: trigger zone `RH_AO_Test`, radius 3 km, near the outpost.
4. **Red heli base** (for Mi-26 / Mi-28 launches): trigger zone `RH_REDHELI_East` somewhere behind the factory.

### 3c. Template groups (all with **Late Activation** ticked)

Place these anywhere out of the way. The names must match exactly.

| Group name | Coalition / country | Contents |
| --- | --- | --- |
| `RH_TPL_RED_ARMOR` | Red / Russia | 2× T-72B |
| `RH_TPL_RED_INF` | Red / Russia | 6× infantry AK |
| `RH_TPL_RED_MI28` | Red / Russia | 1× Mi-28N (helicopter group) |
| `RH_TPL_RED_MI26` | Red / Russia | 1× Mi-26 (helicopter group) |
| `RH_TPL_BLUE_INF_STD_6` | Blue / USA | 6× infantry M4 |
| `RH_TPL_DOWNED_PILOT` | Blue / USA | 1× infantry M4 |
| `RH_TPL_BLUE_HMMWV_TOW` | Blue / USA | 1× HMMWV TOW |
| `RH_TPL_BLUE_FARP_KIT` | Blue / USA | 1× HMMWV (placeholder, replaced by the FARP) |

Anything the scripts need but you have not placed is skipped with a line in `dcs.log`, so the rest can come later.

### 3d. The two triggers that load everything

1. **Triggers** panel → **New** → type **MISSION START**, name `Load MOOSE`. Action **DO SCRIPT**, text:
   ```lua
   dofile(lfs.writedir() .. [[Missions\Rotorheads\Moose_.lua]])
   ```
2. **New** → type **ONCE**, name `Load Rotorheads`. Condition **TIME MORE** `2`. Action **DO SCRIPT**, text:
   ```lua
   RH_CONFIG_OVERRIDES = {
     outpost = { holdTimeMin = 60, holdTimeMax = 90 },
     factory = { reinforceInterval = 120, repairFlightInterval = 300 },
     redAir = { areaCooldown = 120, fighterCooldown = 120 },
     lives = { restoreAfter = 600 },
   }
   dofile(lfs.writedir() .. [[Missions\Rotorheads\rotorheads.lua]])
   ```
   The overrides shorten the timers so you can see things happen during a test. Delete that block later for
   the real Rotorheads timings.

Loading with `dofile` means the mission always uses the latest script on disk: after an update you only
re-run the install script and restart the mission. No need to re-open the Mission Editor.

Save as `Saved Games\DCS\Missions\Rotorheads\RH_Test.miz`.

## Step 4: Launch it as a local multiplayer server

Host from your game rather than single player. Dynamic slots, chat commands and the restart timer behave
like the real server that way.

1. Main menu → **Multiplayer** → **New Server**.
2. Add `RH_Test.miz`, set a password so it stays private, untick **Public**, and **Start**.
3. In the slot list pick a dynamic slot at Bassel Al-Assad, e.g. a **UH-1H**.

## Step 5: Check it works

Do these in order. Stop at the first one that fails and send me what happened (see step 6).

| # | Do this | You should see |
| --- | --- | --- |
| 1 | Wait ~5 s after the mission starts | On-screen: *"Rotorheads Private is live. Type -lives…"*. If you also see a *WARNING… not desanitized* message, re-run step 2 as Administrator. |
| 2 | Look in `Saved Games\DCS\rotorheads\` | `campaign.lua`, `world.lua`, and `livemap.json` exist. `world.lua` is rewritten every 30 seconds. |
| 3 | Chat `-help`, `-time`, `-lives`, `-farps` | Replies in chat. `-farps` lists the Bassel zone marked **(LC)** with unlimited crates. |
| 4 | F10 map → Other → **CTLD** → Manage Troops | Load **Standard (6)** while on the apron, take off, land, unload. Blue infantry appears. |
| 5 | In a Chinook (6 internal crates): CTLD → Manage Crates → **Humvee TOW** → **1**. That loads four small CDS crates. Fly at least 300 m off the apron, drop them, then Manage Crates → Build while the four are within 50 m | A TOW HMMWV is built where the crates were. |
| 6 | Place an F10 map marker with the text `-smoke,green` near you (within 15 km) | Green smoke appears at the marker. |
| 7 | Fly towards the factory | At 5 km it is revealed on the F10 map. Red convoys drive from the factory to the AO. |
| 8 | Destroy the three outpost containers (any attack helo) | A yellow zone appears and a Mi-28 launches from `RH_REDHELI_East`. |
| 9 | Unload your 6 troops in the yellow zone after clearing the red units | Zone turns blue; after 60–90 s the outpost is captured. |
| 10 | Spawn an **AH-64D** or **Ka-50**, crash or eject | `-lives` shows 2. A downed pilot appears (F10 → Other → CSAR). |
| 11 | Rescue that pilot in a UH-1H and land at the MASH / airfield | Message that the life was restored; `-lives` shows 3 again. |
| 12 | Type `-save`, end the mission, start it again | Captured outpost stays captured, built units are back where you left them, lives are kept. |

## Saves and the Mission Editor

The running mission is not the file the editor has open. Units built after launch (Humvees, crates, FARP pads)
live in the simulation until they are written out. Every 30 seconds, and again when you leave, the script
records ground units, ships, statics, and FARP warehouses into `world.lua`. The next launch puts back anything
that is missing, and removes an editor-placed ground unit that was destroyed.

Leaving the mission also writes `RH_Editor.miz` in the same folder as the mission you launched. Open **that**
file in the Mission Editor when you want to move or delete something by hand. The mission you have been
flying is not overwritten. After you edit `RH_Editor.miz`, launch that file if you want the hand edit to be
the one the campaign continues from. A new unit you place in it is kept. Cargo that is inside a helicopter
at the moment of the save is not part of this snapshot.

Re-run `tools\windows\install.ps1` after this update so the hook that writes `RH_Editor.miz` is installed.
DCS has to be restarted before a new hook loads.

## Step 6: When something is wrong

Send me:

- what you did and what happened (screenshot of any Lua error box is great);
- the lines from `Saved Games\DCS\Logs\dcs.log` that contain `[RH]`, `SCRIPTING` or `error`. This PowerShell
  line collects them:
  ```powershell
  Select-String -Path "$env:USERPROFILE\Saved Games\DCS\Logs\dcs.log" -Pattern '\[RH|SCRIPTING|ERROR' | Select-Object -Last 80
  ```

I fix it here and push. Then on your PC:

```powershell
cd C:\Rotorheads
git pull
powershell -ExecutionPolicy Bypass -File tools\windows\install.ps1
```

and restart the mission.

## Later: moving to the dedicated server

When the mission works locally:

1. On the Windows VM, install the DCS dedicated server and the Syria map, clone this project there too, and run
   the install script as Administrator with `-Server -Desanitize`. That targets
   `Saved Games\DCS.dcs_serverrelease\`.
2. Copy `RH_Test.miz` (or your final mission) into
   `Saved Games\DCS.dcs_serverrelease\Missions\Rotorheads\` on the VM.
3. Copy your local `Saved Games\DCS\rotorheads\` folder over too if you want to keep the war you started.
4. Start the server with that mission (web GUI or `serverSettings.lua`, see `server/serverSettings.example.lua`).
