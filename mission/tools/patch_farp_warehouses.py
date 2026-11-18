#!/usr/bin/env python3
"""Turn editor FARP pads in a .miz into limited dynamic-spawn heliports.

DCS reads dynamic spawn and the unlimited checkboxes from the warehouses file
inside the mission, keyed by the pad's unitId. A static named static1-4 is
still a FARP. The campaign script cannot clear those checkboxes after launch.

Usage: python3 tools/patch_farp_warehouses.py RH_Manual.miz
"""

import sys
import zipfile
from io import BytesIO

HELICOPTERS = [
    "Mi-8MTV2", "Mi-8MT", "Mi-24P", "UH-1H", "UH-60L", "CH-47Fbl1",
    "SA342M", "SA342L", "SA342Mistral", "SA342Minigun", "OH58D", "OH-6A",
    "AH-64D_BLK_II", "Ka-50", "Ka-50_3",
]
AIRFRAMES = 999


def farp_unit_ids(mission):
    ids = []
    # A FARP pad is the only static whose type line is exactly FARP.
    parts = mission.split('["type"] = "FARP",')
    for part in parts[1:]:
        window = part[:800]
        marker = '["unitId"] = '
        at = window.find(marker)
        if at < 0:
            continue
        rest = window[at + len(marker):]
        number = []
        for ch in rest:
            if ch.isdigit():
                number.append(ch)
            else:
                break
        if number:
            ids.append(int("".join(number)))
    return ids


def aircrafts_block():
    lines = ["\t\t\t[\"aircrafts\"] = ", "\t\t\t{", "\t\t\t\t[\"helicopters\"] = ", "\t\t\t\t{"]
    for name in HELICOPTERS:
        lines.append("\t\t\t\t\t[\"%s\"] = " % name)
        lines.append("\t\t\t\t\t{")
        lines.append("\t\t\t\t\t\t[\"initialAmount\"] = %d," % AIRFRAMES)
        lines.append("\t\t\t\t\t\t[\"unlimited\"] = false,")
        lines.append("\t\t\t\t\t},")
    lines += ["\t\t\t\t},", "\t\t\t\t[\"planes\"] = ", "\t\t\t\t{", "\t\t\t\t},", "\t\t\t},"]
    return "\n".join(lines)


def patch_warehouse(text, unit_id):
    start = text.find("\t\t[%d] = " % unit_id)
    end = text.find("-- end of [%d]" % unit_id, start)
    if start < 0 or end < 0:
        raise SystemExit("warehouse entry %s is missing" % unit_id)
    block = text[start:end]
    for flag in ("unlimitedMunitions", "unlimitedAircrafts", "unlimitedFuel"):
        old = '["%s"] = true' % flag
        new = '["%s"] = false' % flag
        if old not in block:
            raise SystemExit("%s has no %s = true" % (unit_id, flag))
        block = block.replace(old, new, 1)
    old_spawn = '["dynamicSpawn"] = false'
    if old_spawn not in block:
        raise SystemExit("%s is not dynamicSpawn false" % unit_id)
    block = block.replace(old_spawn, '["dynamicSpawn"] = true', 1)
    block = block.replace('["InitFuel"] = 100', '["InitFuel"] = 0')
    old_aircraft = '\t\t\t["aircrafts"] = {},'
    if old_aircraft not in block:
        raise SystemExit("%s aircrafts table is not the empty editor default" % unit_id)
    block = block.replace(old_aircraft, aircrafts_block(), 1)
    return text[:start] + block + text[end:]


def patch_miz(data):
    src = zipfile.ZipFile(BytesIO(data))
    mission = src.read("mission").decode("utf-8")
    warehouses = src.read("warehouses").decode("utf-8")
    ids = farp_unit_ids(mission)
    if not ids:
        raise SystemExit("no FARP pads found in the mission")
    for unit_id in ids:
        warehouses = patch_warehouse(warehouses, unit_id)
    out = BytesIO()
    with zipfile.ZipFile(out, "w") as dst:
        for info in src.infolist():
            payload = warehouses.encode("utf-8") if info.filename == "warehouses" else src.read(info.filename)
            dst.writestr(info, payload)
    src.close()
    return out.getvalue(), ids


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: patch_farp_warehouses.py <in.miz> <out.miz>")
    data = open(sys.argv[1], "rb").read()
    patched, ids = patch_miz(data)
    open(sys.argv[2], "wb").write(patched)
    print("patched FARP unitIds %s" % ", ".join(str(i) for i in ids))


if __name__ == "__main__":
    main()
