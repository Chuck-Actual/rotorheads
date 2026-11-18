local NM = 1852

local function setup()
  local w = T.fresh()
  w.airbases = {
    { name = "Bassel Al-Assad", point = { x = 0, y = 0 }, kind = "airdrome", coalition = "blue" },
    { name = "Aleppo", point = { x = 200000, y = 0 }, kind = "airdrome", coalition = "red" },
    { name = "Hama", point = { x = 0, y = 150000 }, kind = "airdrome", coalition = "neutral" },
  }
  RH.logistics.register("LC Bassel", { x = 500, y = 0 }, { lc = true, airbase = "Bassel Al-Assad" })
  RH.logistics.register("RH_FARP_ALPHA", { x = 40000, y = 0 })
  return w
end

T.test("a FARP pad is granted 10 tons and 40 missiles once, then restarts keep the saved count", function()
  T.fresh()
  local stock, fresh = RH.logistics.ensurePadStock("static1-4")
  T.ok(fresh)
  T.eq(stock.fuelKg, 10000)
  T.eq(stock.missiles["weapons.missiles.AGM_114K"], 40)
  T.eq(stock.missiles["weapons.missiles.AGM_114L"], 40)
  T.eq(stock.missiles["weapons.missiles.Vikhr_M"], 40)
  stock.fuelKg = 4000
  stock.missiles["weapons.missiles.AGM_114K"] = 12
  stock.missiles["weapons.missiles.AGM_114L"] = 7
  stock.missiles["weapons.missiles.Vikhr_M"] = 0
  local again, second = RH.logistics.ensurePadStock("static1-4")
  T.ok(not second)
  T.eq(again.fuelKg, 4000)
  T.eq(again.missiles["weapons.missiles.AGM_114K"], 12)
  T.eq(again.missiles["weapons.missiles.AGM_114L"], 7)
  T.eq(again.missiles["weapons.missiles.Vikhr_M"], 0)
end)

T.test("a new FARP starts with no crates and general supply is worth five", function()
  setup()
  T.eq(RH.state.farps.RH_FARP_ALPHA.crates, 0)
  T.eq(RH.logistics.crateWorth("General supply x10"), 5)
  T.eq(RH.logistics.crateWorth("Humvee TOW"), 1)
  T.ok(not RH.logistics.takeCrates(RH.state.farps.RH_FARP_ALPHA, 1))
end)

T.test("FARP stock is consumed and refilled up to the cap", function()
  setup()
  local farp = RH.state.farps.RH_FARP_ALPHA
  farp.crates = 40
  T.ok(RH.logistics.takeCrates(farp, 10))
  T.eq(farp.crates, 30)
  T.ok(not RH.logistics.takeCrates(farp, 1000), "cannot take more than stock")
  local added = RH.logistics.returnCrates(farp, 1000)
  T.eq(farp.crates, RH.config.farp.maxCrates)
  T.eq(added, RH.config.farp.maxCrates - 30)
end)

T.test("Logistics Centers have unlimited crates", function()
  setup()
  local lc = RH.state.farps["LC Bassel"]
  T.ok(RH.logistics.hasUnlimitedCrates(lc))
  T.ok(RH.logistics.takeCrates(lc, 100000))
end)

T.test("editor pads are labeled FARP ALPHA and FARP BRAVO with a crate count", function()
  local w = setup()
  w.statics["static1-4"] = { alive = true, point = { x = 40763, y = 9580 }, typeName = "FARP" }
  w.statics["static1-5"] = { alive = true, point = { x = 46469, y = 6473 }, typeName = "FARP" }
  RH.logistics.discoverEditorPads()
  local bravo
  for _, farp in pairs(RH.state.farps) do
    if farp.label == "FARP BRAVO" then bravo = farp end
  end
  T.eq(bravo.name, "static1-5")
  T.eq(bravo.crates, 0)
  T.eq(bravo.built, false)
  T.eq(RH.logistics.mapLabelText(bravo), "FARP BRAVO\nCrates: 0")
  RH.logistics.refreshMapLabels()
  local label = w.drawings["farp-stock-static1-5"]
  T.eq(label.text, "FARP BRAVO\nCrates: 0")
  T.eq(label.side, "all")
  T.eq(label.fontSize, 18)
  RH.logistics.spawnBuilt()
  for _, name in ipairs(w.farpsSpawned) do T.ok(name ~= "static1-4" and name ~= "static1-5") end
end)

T.test("an editor tent shows crates at startup, limits pulls, and gets one Humvee", function()
  local w = setup()
  w.statics.tent = { alive = true, point = { x = 80000, y = 1000 }, typeName = "FARP Tent" }
  table.insert(w.airbases, { name = "static-pad", point = { x = 80040, y = 1000 }, kind = "helipad", coalition = "blue" })
  local spawned = {}
  local fueled = {}
  RH.dcs.objectExists = function(name) return spawned[name] ~= nil end
  RH.dcs.spawnVehicle = function(name, typeName) spawned[name] = typeName end
  RH.dcs.writePadStock = function(name, stock) fueled[name] = stock.fuelKg end
  RH.logistics.discoverEditorPads()
  local farp
  for _, f in pairs(RH.state.farps) do
    if f.editor and f.x == 80000 then farp = f end
  end
  T.eq(farp.crates, 0)
  T.ok(string.find(RH.logistics.mapLabelText(farp), "Crates: 0", 1, true) ~= nil)
  RH.logistics.equipEditorFarps()
  RH.logistics.equipEditorFarps()
  T.eq(spawned[farp.name .. " Humvee"], "Hummer")
  T.eq(fueled["static-pad"], 10000)
  local n = 0
  for _ in pairs(spawned) do n = n + 1 end
  T.eq(n, 1)

  dofile("src/rh/ctld.lua")
  ZONE = { FindByName = function() return nil end }
  ZONE_RADIUS = { New = function() end }
  CTLD = { CargoZoneType = { LOAD = "load" } }
  SMOKECOLOR = { Blue = 1 }
  local zones = {}
  local inst = {
    AddCTLDZone = function(_, name) zones[#zones + 1] = name end,
    _SendMessage = function(_, text) end,
  }
  RH.ctld.instance = inst
  T.eq(RH.ctld.addFarpZone(farp), true)
  T.eq(#zones, 1)
  T.eq(RH.ctld.addFarpZone(farp), nil)
  RH.ctld.installHooks(inst)
  local unit = { GetVec2 = function() return { x = 80005, y = 1005 } end }
  local cargo = { GetName = function() return "Avenger" end, GetCratesNeeded = function() return 1 end }
  T.eq(inst:CanGetCrates({}, unit, cargo, 1), false)
  T.eq(farp.crates, 0)
  farp.crates = 25
  T.eq(inst:CanGetCrates({}, unit, cargo, 1), true)
  T.eq(farp.crates, 24)
  T.eq(inst:CanGetCrates({}, unit, cargo, 30), false)
  T.eq(farp.crates, 24)
end)

T.test("the load circle sits on the FARP tent, not the pad", function()
  local w = setup()
  dofile("src/rh/ctld.lua")
  local farp = RH.state.farps.RH_FARP_ALPHA
  w.statics.pad = { alive = true, point = { x = farp.x, y = farp.y }, typeName = "FARP" }
  w.statics.fuel = { alive = true, point = { x = farp.x + 70, y = farp.y }, typeName = "FARP Fuel Depot" }
  w.statics.tent = { alive = true, point = { x = farp.x, y = farp.y - 70 }, typeName = "FARP Tent" }
  local points, atTent = RH.ctld.tentPoints(farp)
  T.eq(atTent, true)
  T.eq(#points, 1)
  T.eq(points[1].y, farp.y - 70)
end)

T.test("Return crates to tent is on the CTLD menu", function()
  T.fresh()
  dofile("src/rh/ctld.lua")
  T.eq(RH.config.testVehicleCrates, 1)
  local added = {}
  MENU_GROUP_COMMAND = { New = function(_, _, label, parent)
    table.insert(added, { label = label, parent = parent })
    return { Refresh = function() end }
  end }
  local group = {}
  local unit = { GetGroup = function() return group end, GetVec2 = function() return { x = 10, y = 10 } end }
  UNIT = { FindByName = function(_, name) if name == "Heli-1" then return unit end end }
  local inst = { CtldUnits = { ["Heli-1"] = "Heli-1" }, CrateDistance = 50 }
  function inst:_RefreshF10Menus()
    group.CTLDTopmenu = group.CTLDTopmenu or { name = "top" }
    group.MyTopCratesMenu = group.MyTopCratesMenu or { name = "crates" }
  end
  local removed = 0
  function inst:_RemoveCratesNearby()
    removed = removed + 1
    T.eq(inst.CrateDistance, RH.config.farp.loadRadius)
  end
  RH.ctld.installMenus(inst)
  inst:_RefreshF10Menus()
  inst:_RefreshF10Menus()
  T.eq(#added, 2)
  T.eq(added[1].label, "Return crates to tent")
  T.eq(added[1].parent.name, "top")
  T.eq(added[2].parent.name, "crates")
  RH.ctld.instance = { _SendMessage = function() end }
  RH.ctld.returnCratesToTent(inst, group, unit)
  T.eq(removed, 0)
  RH.logistics.register("static1-5", { x = 10, y = 10 }, { editor = true, label = "FARP BRAVO" })
  RH.ctld.returnCratesToTent(inst, group, unit)
  T.eq(removed, 1)
  T.eq(inst.CrateDistance, 50)
  MENU_GROUP_COMMAND = nil
  UNIT = nil
  RH.ctld.instance = nil
end)

T.test("return crates at the tent finds a FARP whose pad is more than 500 m away", function()
  local w = setup()
  dofile("src/rh/ctld.lua")
  local farp = RH.state.farps.RH_FARP_ALPHA
  w.statics.tent = { alive = true, point = { x = farp.x, y = farp.y + 700 }, typeName = "FARP Tent", name = "RH_FARP_ALPHA Tent" }
  local removed = 0
  local inst = { CrateDistance = 50, _RemoveCratesNearby = function() removed = removed + 1 end }
  RH.ctld.instance = { _SendMessage = function() end }
  local unit = { IsAlive = function() return true end, GetVec2 = function() return { x = farp.x + 15, y = farp.y + 700 } end }
  RH.ctld.returnCratesToTent(inst, nil, unit)
  T.eq(removed, 1)
  T.eq(inst.CrateDistance, 50)
  RH.ctld.instance = nil
end)

T.test("general supply cannot be built into a FARP", function()
  setup()
  dofile("src/rh/ctld.lua")
  T.ok(RH.config.kits.generalSupply.template ~= RH.config.kits.farp.template)
  local inst = {}
  local messages = {}
  RH.ctld.instance = { _SendMessage = function(_, text) table.insert(messages, text) end }
  RH.ctld.installHooks(inst)
  local before = 0
  for _ in pairs(RH.state.farps) do before = before + 1 end
  T.eq(inst:OnBeforeCratesBuild(nil, nil, nil, {}, nil, "General supply x5"), false)
  local unit = { GetVec2 = function() return { x = 90000, y = 0 } end, GetPlayerName = function() return "Pilot" end, IsAlive = function() return true end }
  inst:OnAfterCratesBuildStarted(nil, nil, nil, {}, unit, "General supply x5")
  local destroyed = false
  inst:OnAfterCratesBuild(nil, nil, nil, {}, unit, {
    GetName = function() return "RH_TPL_BLUE_SUPPLY-1" end,
    Destroy = function() destroyed = true end,
    GetVec2 = function() return { x = 90000, y = 0 } end,
  })
  local after = 0
  for _ in pairs(RH.state.farps) do after = after + 1 end
  T.eq(after, before)
  T.eq(destroyed, true)
  T.ok(#messages > 0)
  RH.ctld.instance = nil
end)

T.test("FARP must be 1 mile from other FARPs and Logistics Centers", function()
  setup()
  local mile = RH.config.farp.minSeparation
  local ok, reason = RH.logistics.validateFarpSite({ x = 40000 + mile * 0.5, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("needs 1 mile"), reason)
  ok, reason = RH.logistics.validateFarpSite({ x = mile * 0.5, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("Logistics Center"), reason)
  ok = RH.logistics.validateFarpSite({ x = 40000 + mile * 1.1, y = 0 })
  T.eq(ok, true)
end)

T.test("a FARP 10 NM from an airfield with no LC is allowed", function()
  setup()
  local ok, kind = RH.logistics.validateFarpSite({ x = 0, y = 150000 - 10 * NM })
  T.eq(ok, true)
  T.eq(kind, "farp")
end)

T.test("a helicopter pad is not a Logistics Center and does not block a FARP", function()
  local w = setup()
  table.insert(w.airbases, { name = "HS02", point = { x = 9000, y = 0 }, kind = "airdrome", coalition = "blue", logistics = false })
  local ok, kind = RH.logistics.validateFarpSite({ x = 9000, y = 400 })
  T.eq(ok, true)
  T.eq(kind, "farp")
end)

T.test("building within 1 NM of a friendly airfield makes an LC", function()
  local w = setup()
  local ok, kind, airfield = RH.logistics.validateFarpSite({ x = 0, y = 150000 + 0.5 * NM })
  T.eq(ok, true)
  T.eq(kind, "lc")
  T.eq(airfield.name, "Hama")
  local farp = RH.logistics.buildFarp({ x = 0, y = 150000 + 0.5 * NM }, "Viper")
  T.eq(farp.name, "LC Hama")
  T.ok(farp.lc)
  T.eq(farp.pending, true)
  T.eq(#w.farpsSpawned, 0)
  RH.logistics.start()
  T.eq(farp.built, true)
  T.eq(farp.pending, false)
  T.eq(w.farpsSpawned[1], "LC Hama")
  local again, why = RH.logistics.validateFarpSite({ x = 100, y = 150000 })
  T.eq(again, false)
  T.ok(why:find("1 mile"), why)
end)

T.test("FARP stocks guns, rockets, and air-to-air missiles, not air-to-ground", function()
  T.fresh()
  T.eq(RH.logistics.farpSupplyCount("shells", "weapons.shells.M230_HEDP M789"), 5000)
  T.eq(RH.logistics.farpSupplyCount("nurs", "weapons.nurs.HYDRA_70_M151"), 999)
  T.eq(RH.logistics.farpSupplyCount("containers", "weapons.containers.APK-9"), nil)
  T.eq(RH.logistics.farpSupplyCount("gunmounts", "weapons.gunmounts.{CH47_AFT_M134D}"), 99)
  T.eq(RH.logistics.farpSupplyCount("missiles", "weapons.missiles.AIM_9X"), 99)
  T.eq(RH.logistics.farpSupplyCount("missiles", "weapons.missiles.FIM_92C"), 99)
  T.eq(RH.logistics.farpSupplyCount("missiles", "weapons.missiles.Mistral"), 99)
  local keptOff = {
    "AGM_114K", "AGM_114", "Vikhr_M", "SA9M311", "ADM_141A", "ADM_141B", "AM39",
    "CM-400AKG", "M30", "M31", "HY-2", "Kh25MP_PRGS1VP", "Kh-66_Grom", "X_28",
    "LD-10", "M39A1", "M48", "P_500", "P_700", "S_25L", "SCUD_RAKETA", "V-1",
    "YJ-12", "YJ-62", "YJ-82", "P_9M117", "AGR_20A",
  }
  for _, name in ipairs(keptOff) do
    local item = "weapons.missiles." .. name
    T.eq(RH.logistics.farpSupplyCount("missiles", item), nil)
    T.ok(RH.logistics.keepHauledWeapon(item))
  end
  T.ok(not RH.logistics.keepHauledWeapon("weapons.missiles.AIM_9X"))
  T.ok(not RH.logistics.keepHauledWeapon("weapons.nurs.HYDRA_70_M151"))
  T.ok(not RH.logistics.keepHauledWeapon("weapons.containers.APK-9"))
  T.eq(RH.logistics.farpAirframeCount("UH-1H"), 999)
  T.eq(RH.logistics.farpAirframeCount("AH-64D_BLK_II"), 999)
  T.eq(RH.logistics.farpAirframeCount("C-130J-30"), 0)
end)

T.test("a FARP brings the services DCS needs to rearm and refuel", function()
  T.fresh()
  local types = {}
  for _, piece in ipairs(RH.config.farp.services) do types[piece.typeName] = true end
  T.ok(types["FARP Tent"])
  T.ok(types["FARP Fuel Depot"])
  T.ok(types["FARP Ammo Dump Coating"])
  T.ok(types["Hummer"])
  T.ok(not types["M 818"])
end)

T.test("a built FARP stacked on an editor pad is dropped and the pad shows the crate count", function()
  local w = setup()
  w.statics["static1-4"] = { alive = true, point = { x = 80000, y = 0 }, typeName = "FARP" }
  w.statics.tent = { alive = true, point = { x = 80000, y = -70 }, typeName = "FARP Tent" }
  RH.logistics.register("FARP 01", { x = 80020, y = -10 }, { built = true })
  RH.logistics.register("FARP 02", { x = 120000, y = 0 }, { pending = true })
  RH.state.world = { objects = { { name = "FARP 01" }, { name = "FARP 01 Tent" }, { name = "Humvee" } } }
  local dropped = RH.logistics.dropStackedFarps()
  T.eq(#dropped, 1)
  T.eq(dropped[1], "FARP 01")
  T.eq(RH.state.farps["FARP 01"], nil)
  T.eq(RH.state.farps["FARP 02"].pending, true)
  T.eq(#RH.state.world.objects, 1)
  T.eq(RH.state.world.objects[1].name, "Humvee")
  RH.logistics.discoverEditorPads()
  local labeled
  for _, farp in pairs(RH.state.farps) do
    if farp.name == "static1-4" then labeled = farp end
  end
  T.eq(labeled.editor, true)
  T.eq(RH.logistics.mapLabelText(labeled), "FARP ALPHA\nCrates: 0")
  RH.logistics.spawnBuilt()
  T.eq(#w.farpsSpawned, 1)
  T.eq(w.farpsSpawned[1], "FARP 02")
end)

T.test("a marked FARP waits for the next restart and then spawns empty", function()
  local w = setup()
  local mile = RH.config.farp.minSeparation
  local farp = RH.logistics.buildFarp({ x = 40000 + mile * 2, y = 0 }, "Viper")
  T.eq(farp.name, "FARP 01")
  T.eq(farp.crates, 0)
  T.eq(farp.liquids, nil)
  T.eq(farp.pending, true)
  T.ok(w.files["save/campaign.lua"]:find("FARP 01"), "mark is written immediately")
  RH.logistics.spawnBuilt()
  T.eq(farp.built, true)
  T.eq(farp.liquids, nil)
  T.eq(farp.ammoItems, nil)
end)

T.test("cannot build an LC at a red airfield", function()
  setup()
  local ok, reason = RH.logistics.validateFarpSite({ x = 200000, y = 500 })
  T.eq(ok, false)
  T.ok(reason:find("REDFOR"), reason)
end)

T.test("MASH needs a blue zone and 16 km separation", function()
  local w = setup()
  w.zones = { { name = "RH_BLUEZONE_WEST", point = { x = 0, y = 0 }, radius = 60000 } }
  local ok, reason = RH.logistics.validateMashSite({ x = 100000, y = 100000 })
  T.eq(ok, false)
  T.ok(reason:find("blue zone"), reason)
  T.ok(RH.logistics.buildMash({ x = 10000, y = 0 }, "Medic"))
  ok, reason = RH.logistics.validateMashSite({ x = 20000, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("16 km"), reason)
  T.ok(RH.logistics.buildMash({ x = 30000, y = 0 }, "Medic"))
  T.eq(#w.mashesSpawned, 2)
end)

T.test("MASH capacity and transport tasks", function()
  setup()
  RH.logistics.registerMash("MASH 01", { x = 0, y = 0 })
  T.eq(RH.logistics.admitPatients("MASH 01", 25), 25)
  T.eq(RH.logistics.admitPatients("MASH 01", 10), 10)
  T.ok(not RH.logistics.mashFull("MASH 01"))
  T.eq(RH.logistics.startTransport("herc", "MASH 01", 30), 30)
  T.eq(RH.state.mashes["MASH 01"].patients, 5)
  T.eq(RH.logistics.completeTransport("herc"), 30)
end)

T.test("FARP crate template is copied from the Humvee so Get crates can list it", function()
  T.fresh()
  dofile("src/rh/ctld.lua")
  _DATABASE = { Templates = { Groups = {
    RH_TPL_BLUE_HMMWV_TOW = {
      GroupName = "RH_TPL_BLUE_HMMWV_TOW",
      Template = { name = "RH_TPL_BLUE_HMMWV_TOW", units = { { name = "tow" } } },
    },
  } } }
  T.ok(RH.ctld.ensureKitTemplate("RH_TPL_BLUE_FARP_KIT"))
  local kit = _DATABASE.Templates.Groups.RH_TPL_BLUE_FARP_KIT
  T.eq(kit.Template.name, "RH_TPL_BLUE_FARP_KIT")
  T.eq(kit.Template.units[1].name, "tow")
  kit.Template.units[1].name = "changed"
  T.eq(_DATABASE.Templates.Groups.RH_TPL_BLUE_HMMWV_TOW.Template.units[1].name, "tow")
  _DATABASE = nil
end)

T.test("captured outposts extend the blue zone", function()
  local w = setup()
  w.zones = { { name = "RH_OUTPOST_KAFR", point = { x = 90000, y = 0 }, radius = 200 } }
  RH.outposts.discover()
  T.ok(not RH.logistics.inBlueZone({ x = 90000, y = 0 }))
  RH.state.outposts.RH_OUTPOST_KAFR = { status = "captured" }
  T.ok(RH.logistics.inBlueZone({ x = 90000, y = 1000 }))
end)
