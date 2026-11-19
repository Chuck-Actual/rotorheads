# Rotorheads

Read `docs/FRAMEWORK.md` before editing, and update the section for any mechanic you change before you finish. That file is what the next agent reads. Host and save rules also live in `.cursor/rules/dcs-host.mdc`.

The owner hosts a LAN server from the DCS client on one PC. Scripts are in `Saved Games\DCS\Missions\Rotorheads`. The campaign save is the separate folder `Saved Games\DCS\rotorheads`. Host the newest of `RH Campaign A.miz` and `RH Campaign B.miz`, which the hook writes from the save; `RH Manual.miz` starts a fresh war. Do not respawn units from `persistence/Rotorheads.json` inside a mission file.
