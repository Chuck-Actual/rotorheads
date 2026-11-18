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

T.test("editor pads take two different bank names and keep a crate count", function()
  local w = setup()
  local random = math.random
  math.random = function() return 1 end
  w.statics["static1-4"] = { alive = true, point = { x = 40763, y = 9580 }, typeName = "FARP" }
  w.statics["static1-5"] = { alive = true, point = { x = 46469, y = 6473 }, typeName = "FARP" }
  RH.logistics.discoverEditorPads()
  math.random = random
  local first = RH.state.farps["static1-4"]
  local second = RH.state.farps["static1-5"]
  T.eq(first.label, "FARP COPPERHEAD")
  T.eq(second.label, "FARP RATTLESNAKE")
  T.eq(second.crates, 0)
  T.eq(RH.logistics.mapLabelText(second), "FARP RATTLESNAKE\nCrates: 0")
  RH.logistics.refreshMapLabels()
  local label = w.drawings["farp-stock-static1-5"]
  T.eq(label.text, "FARP RATTLESNAKE\nCrates: 0")
  T.eq(label.side, "blue")
  T.eq(label.fontSize, 18)
  local markId = label.markId
  second.crates = 74
  RH.logistics.refreshMapLabels()
  T.eq(w.drawings["farp-stock-static1-5"].text, "FARP RATTLESNAKE\nCrates: 74")
  T.eq(w.drawings["farp-stock-static1-5"].markId, markId)
  RH.state.farps["static1-4"] = nil
  math.random = function() return 1 end
  T.eq(RH.logistics.pickFarpName(), "FARP COPPERHEAD")
  math.random = random
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
  T.eq(RH.ctld.addFarpZone(farp), true)
  T.eq(#zones, 1)
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
  T.eq(#added, 6)
  T.eq(added[1].label, "Show logistics zones")
  T.eq(added[1].parent.name, "top")
  T.eq(added[2].label, "Pack MASH")
  T.eq(added[3].label, "Return crates to tent")
  T.eq(added[4].parent.name, "crates")
  T.eq(added[5].label, "Pack MASH")
  T.eq(added[6].label, "Return crates to tent")
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

T.test("show logistics zones draws a circle and leaves the crate count", function()
  local w = setup()
  dofile("src/rh/ctld.lua")
  local farp = RH.logistics.register("FARP MUSTANG", { x = 80000, y = 0 }, { label = "FARP MUSTANG", crates = 4 })
  farp.loadPoints = { { x = 80000, y = -70 } }
  RH.logistics.refreshMapLabels()
  T.ok(RH.ctld.showLoadZones({}) >= 1)
  T.eq(w.drawings["rh-load-FARP MUSTANG-1"].text, "Load")
  T.eq(w.drawings["farp-stock-FARP MUSTANG"].text, "FARP MUSTANG\nCrates: 4")
  w.advance(60)
  T.eq(w.drawings["rh-load-FARP MUSTANG-1"], nil)
  T.eq(w.drawings["farp-stock-FARP MUSTANG"].text, "FARP MUSTANG\nCrates: 4")
end)

T.test("a saved FARP and the Bassel logistics center get a zone and a crate label", function()
  local w = setup()
  dofile("src/rh/ctld.lua")
  local old = RH.logistics.register("static1-4", { x = 90000, y = 0 }, { editor = true, label = "FARP Tent", crates = 12 })
  old.loadZoneReady = true
  local lc = RH.state.farps["LC Bassel"]
  lc.loadZoneReady = true
  RH.logistics.assignFarpNames()
  T.ok(RH.logistics.isBankName(old.label))
  T.eq(old.loadZoneReady, nil)
  T.ok(not RH.logistics.isBankName(lc.label))
  RH.logistics.refreshMapLabels()
  T.eq(w.drawings["farp-stock-static1-4"].text, old.label .. "\nCrates: 12")
  T.eq(w.drawings["farp-stock-LC Bassel"].text, "LC Bassel\nCrates: unlimited")
  local created = {}
  local added = {}
  ZONE = { FindByName = function() return nil end }
  ZONE_RADIUS = { New = function(_, name, _, radius) created[#created + 1] = { name = name, radius = radius } end }
  CTLD = { CargoZoneType = { LOAD = "load" } }
  SMOKECOLOR = { Blue = 1 }
  RH.ctld.instance = { AddCTLDZone = function(_, name) added[#added + 1] = name end }
  RH.ctld.zoneReady = {}
  old.loadZoneReady = true
  lc.loadZoneReady = true
  RH.ctld.ensureFarpZone(lc)
  RH.ctld.ensureFarpZone(old)
  T.eq(created[1].radius, 500)
  T.eq(created[2].radius, 150)
  T.eq(#added, 2)
  RH.ctld.ensureFarpZone(lc)
  T.eq(#added, 2)
  RH.ctld.showLoadZones({})
  T.eq(w.drawings["rh-load-LC Bassel-1"].radius, 500)
  T.eq(w.drawings["rh-load-static1-4-1"].radius, 150)
  ZONE, ZONE_RADIUS, CTLD, SMOKECOLOR = nil, nil, nil, nil
  RH.ctld.instance = nil
end)

T.test("the Chinook does not load or drop crates through CTLD", function()
  T.fresh()
  dofile("src/rh/ctld.lua")
  local calls = {}
  local inst = {
    hoverautoloading = true,
    _GetAndLoad = function() calls.get = true end,
    _LoadCratesNearby = function() calls.load = true end,
    _UnloadCrates = function() calls.drop = true end,
    _UnloadSingleCrateSet = function() calls.one = true end,
    _SendMessage = function(_, text) calls.msg = text end,
  }
  RH.ctld.guardChinook(inst)
  T.eq(inst.hoverautoloading, false)
  local chinook = { GetTypeName = function() return "CH-47Fbl1" end }
  local uh = { GetTypeName = function() return "UH-1H" end }
  T.eq(inst:_GetAndLoad({}, chinook), inst)
  T.eq(inst:_LoadCratesNearby({}, chinook), inst)
  T.eq(inst:_UnloadCrates({}, chinook), inst)
  T.eq(calls.get, nil)
  T.ok(string.find(calls.msg, "cargo menu", 1, true) ~= nil)
  inst:_GetAndLoad({}, uh)
  inst:_UnloadCrates({}, uh)
  T.eq(calls.get, true)
  T.eq(calls.drop, true)
end)

T.test("Chinook ground crew crates are not CTLD boarded cargo", function()
  T.fresh()
  dofile("src/rh/ctld.lua")
  CTLD_CARGO = { Enum = { GCLOADABLE = "gc", TROOPS = "troops", VEHICLE = "vehicle" } }
  UNIT = { FindByName = function(_, name)
    if name == "hook" then return { GetTypeName = function() return "CH-47Fbl1" end } end
    if name == "huey" then return { GetTypeName = function() return "UH-1H" end } end
  end }
  local inst = { Loaded_Cargo = {
    hook = { Cratesloaded = 2, Cargo = {
      { ClassName = "DYNAMICCARGO", GetType = function() return "gc" end, GetName = function() return "crate" end },
      { GetType = function() return "troops" end, GetName = function() return "Squad" end },
    } },
    huey = { Cratesloaded = 1, Cargo = {
      { GetType = function() return "vehicle" end, GetName = function() return "Avenger" end },
    } },
  } }
  RH.ctld.forgetChinookGroundCrewCrates(inst)
  T.eq(#inst.Loaded_Cargo.hook.Cargo, 1)
  T.eq(inst.Loaded_Cargo.hook.Cratesloaded, 0)
  T.eq(#inst.Loaded_Cargo.huey.Cargo, 1)
  UNIT = nil
  CTLD_CARGO = nil
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
  T.ok(string.find(RH.logistics.mapLabelText(labeled), "Crates: 0", 1, true) ~= nil)
  T.ok(not RH.logistics.labelIsPlaceholder(labeled.label))
  RH.logistics.spawnBuilt()
  T.eq(#w.farpsSpawned, 1)
  T.eq(w.farpsSpawned[1], "FARP 02")
end)

T.test("a marked FARP waits for the next restart and then spawns empty", function()
  local w = setup()
  local mile = RH.config.farp.minSeparation
  local random = math.random
  math.random = function() return 1 end
  local farp = RH.logistics.buildFarp({ x = 40000 + mile * 2, y = 0 }, "Viper")
  math.random = random
  T.eq(farp.name, "FARP COPPERHEAD")
  T.eq(farp.label, "FARP COPPERHEAD")
  T.eq(farp.crates, 0)
  T.eq(farp.liquids, nil)
  T.eq(farp.pending, true)
  T.ok(w.files["save/campaign.lua"]:find("FARP COPPERHEAD"), "mark is written immediately")
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

T.test("a MASH builds only within 1 km of a FARP or Logistics Center", function()
  local w = setup()
  w.statics["static1-7"] = { alive = true, typeName = "FARP", point = { x = 39745, y = 0 }, side = "blue" }
  w.statics["static1-3"] = { alive = true, typeName = "FARP", point = { x = 39503, y = 0 }, side = "blue" }
  table.insert(w.units, {
    name = "RH_TPL_BLUE_LINEBACKER-23286#001-01", side = "blue", alive = true, ground = true, pos = { x = 39584, y = 0 },
  })
  local ok, reason = RH.logistics.validateMashSite({ x = 100000, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("not within 1000 m"), reason)
  -- Inside the 150 m FARP load circle, and closer to a pad static. Neither blocks the build.
  T.ok(RH.logistics.buildMash({ x = 39900, y = 0 }, "Medic"))
  T.eq(RH.state.mashes["MASH 01"].player, true)
  -- 900 m from the FARP, still inside the 1 km limit, next to a pad and a blue vehicle.
  T.ok(RH.logistics.buildMash({ x = 39100, y = 0 }, "Medic"))
  ok, reason = RH.logistics.validateMashSite({ x = 41100, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("not within 1000 m"), reason)
  T.ok(RH.logistics.buildMash({ x = 900, y = 0 }, "Medic"))
  T.eq(#w.mashesSpawned, 3)
end)

T.test("an editor MASH zone is not spawned and its tent is removed", function()
  local w = setup()
  w.zones = {
    { name = "RH_BLUEZONE_WEST", point = { x = 0, y = 0 }, radius = 60000 },
    { name = "MASH Bassel", point = { x = 0, y = 800 }, radius = 100 },
  }
  RH.state.mashes["MASH Bassel"] = { x = 0, y = 800, patients = 4 }
  RH.state.mashes["MASH 01"] = { x = 10000, y = 0, patients = 2, player = true }
  w.statics["MASH Bassel tent"] = {
    alive = true, typeName = "Tent04", display = "M92_Tent04", point = { x = 0, y = 800 }, side = "blue",
  }
  w.statics["RH_FARP_Bassel Tent"] = {
    alive = true, typeName = "FARP Tent", display = "PalatkaB", point = { x = 500, y = 0 }, side = "blue",
  }
  RH.state.world = {
    objects = { { name = "MASH Bassel tent", x = 0, y = 800 } },
    baseline = { ["MASH Bassel tent"] = true },
  }
  RH.logistics.spawnPlayerMashes()
  T.eq(RH.state.mashes["MASH Bassel"], nil)
  T.eq(RH.state.mashes["MASH 01"].patients, 2)
  T.eq(#w.mashesSpawned, 1)
  T.eq(w.mashesSpawned[1], "MASH 01")
  T.eq(w.statics["MASH Bassel tent"].alive, false)
  T.eq(w.statics["RH_FARP_Bassel Tent"].alive, true)
  T.eq(#RH.state.world.objects, 0)
  T.eq(RH.state.world.baseline["MASH Bassel tent"], nil)
  T.ok(RH.world.excluded("MASH Bassel tent"))
  T.ok(not RH.world.excluded("RH_FARP_Bassel Tent"))
end)

T.test("packing a MASH removes the tent and places the six build crates", function()
  local w = setup()
  dofile("src/rh/ctld.lua")
  RH.logistics.buildMash({ x = 40000, y = 0 }, "Medic")
  RH.state.mashes["MASH 01"].patients = 2
  w.statics["MASH 01 tent"] = {
    alive = true, typeName = "Tent04", display = "M92_Tent04", point = { x = 40000, y = 0 }, side = "blue",
  }
  RH.state.world = {
    objects = { { name = "MASH 01 tent", x = 40000, y = 0 } },
    baseline = { ["MASH 01 tent"] = true },
  }
  RH.state.farps["RH_FARP_ALPHA"].crates = 2
  local calls = {}
  local replies = {}
  local cargo = { Name = "MASH Crate", GetName = function() return "MASH Crate" end, GetCratesNeeded = function() return 6 end }
  local inst = {
    Cargo_Crates = { cargo },
    _GetCrates = function(self, group, unit, got, number, drop, pack, quiet)
      table.insert(calls, { number = number, drop = drop, pack = pack, quiet = quiet, cargo = got })
      return true
    end,
    _SendMessage = function(_, text) replies[#replies + 1] = text end,
  }
  RH.ctld.instance = inst
  local unit = { GetVec2 = function() return { x = 40040, y = 0 } end }
  local packed, found = RH.ctld.packMashNearby(inst, {}, unit, true)
  T.eq(packed, true)
  T.eq(found, true)
  T.eq(RH.state.mashes["MASH 01"], nil)
  T.eq(w.statics["MASH 01 tent"].alive, false)
  T.eq(#RH.state.world.objects, 0)
  T.eq(RH.state.world.baseline["MASH 01 tent"], nil)
  T.eq(calls[1].number, 6)
  T.eq(calls[1].pack, true)
  T.eq(calls[1].drop, false)
  T.eq(calls[1].cargo, cargo)
  T.ok(replies[#replies]:find("6 MASH crates"))
  T.ok(replies[#replies]:find("2 patients"))
  RH.logistics.buildMash({ x = 40000, y = 0 }, "Medic")
  packed, found = RH.ctld.packMashNearby(inst, {}, { GetVec2 = function() return { x = 42000, y = 0 } end }, false)
  T.eq(packed, false)
  T.eq(found, false)
  T.ok(RH.state.mashes["MASH 01"])
  inst._GetCrates = function() return false end
  packed, found = RH.ctld.packMashNearby(inst, {}, unit, true)
  T.eq(packed, false)
  T.eq(found, true)
  T.ok(RH.state.mashes["MASH 01"])
  RH.ctld.installHooks(inst)
  local stock = RH.state.farps["RH_FARP_ALPHA"].crates
  T.eq(inst:CanGetCrates({}, unit, cargo, 6, false, true), true)
  T.eq(RH.state.farps["RH_FARP_ALPHA"].crates, stock)
  T.eq(inst:CanGetCrates({}, unit, cargo, 6), false)
  T.eq(RH.state.farps["RH_FARP_ALPHA"].crates, stock)
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
  T.ok(RH.ctld.ensureKitTemplate("RH_TPL_BLUE_MASH_KIT"))
  T.eq(_DATABASE.Templates.Groups.RH_TPL_BLUE_MASH_KIT.Template.name, "RH_TPL_BLUE_MASH_KIT")
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

T.test("an existing FARP label stays up and the crate count is rewritten on it", function()
  local textCalls, updates = {}, {}
  trigger = { action = {
    textToAll = function(_, id, _, _, _, _, _, text) textCalls[#textCalls + 1] = { id = id, text = text } end,
    setMarkupText = function(id, text) updates[#updates + 1] = { id = id, text = text } end,
    setMarkupPositionStart = function() end,
    removeMark = function() end,
  } }
  land = { getHeight = function() return 0 end }
  world = { event = {
    S_EVENT_BIRTH = 1, S_EVENT_DEAD = 2, S_EVENT_UNIT_LOST = 3, S_EVENT_PILOT_DEAD = 4,
    S_EVENT_EJECTION = 5, S_EVENT_CRASH = 6, S_EVENT_PLAYER_LEAVE_UNIT = 7, S_EVENT_KILL = 8,
    S_EVENT_SHOT = 9, S_EVENT_LAND = 10, S_EVENT_MARK_ADDED = 11, S_EVENT_MARK_CHANGE = 12,
    S_EVENT_MARK_REMOVED = 13,
  } }
  local saved = RH.dcs
  dofile("src/rh/dcs.lua")
  RH.dcs.drawLabel("farp-stock-static1-7", "blue", { x = 40763, y = 9510 }, "FARP COPPERHEAD\nCrates: 49", 18, 900001)
  RH.dcs.drawLabel("farp-stock-static1-7", "blue", { x = 40763, y = 9510 }, "FARP COPPERHEAD\nCrates: 74", 18, 900001)
  T.eq(#textCalls, 1)
  T.ok(textCalls[1].id ~= 900001)
  T.eq(textCalls[1].text, "FARP COPPERHEAD\nCrates: 49")
  T.eq(#updates, 1)
  T.eq(updates[1].id, textCalls[1].id)
  T.eq(updates[1].text, "FARP COPPERHEAD\nCrates: 74")
  RH.dcs = saved
  trigger, land, world = nil, nil, nil
end)
