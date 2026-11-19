T.test("world restore brings back a dropped Humvee and drops a destroyed editor unit", function()
  T.fresh()
  RH.state.farps["FARP 01"] = { x = 1, y = 2, built = true }
  local saved = {
    baselineReady = true,
    baseline = { ["Tank 1"] = true, ["Shed"] = true },
    objects = {
      { name = "Shed", kind = "static", x = 10, y = 10, origin = "baseline" },
      { name = "RH_TPL_BLUE_HMMWV_TOW#001", kind = "vehicle", x = 50, y = 80, origin = "runtime" },
      { name = "FARP 01", kind = "static", x = 1, y = 2, origin = "farp", farp = true },
      { name = "FARP 01 Humvee", kind = "vehicle", x = 3, y = 4, origin = "farp" },
    },
  }
  local alive = {
    { name = "Tank 1", x = 0, y = 0 },
    { name = "Shed", x = 10, y = 10 },
    { name = "New Truck", x = 5, y = 5 },
    { name = "Garrison Alpha", x = 9, y = 9 },
    { name = "RH_TPL_BLUE_HMMWV_TOW", x = 1, y = 1 },
  }
  local plan = RH.world.plan(saved, alive)
  T.eq(#plan.spawn, 1)
  T.eq(plan.spawn[1].name, "RH_TPL_BLUE_HMMWV_TOW#001")
  T.eq(#plan.destroy, 1)
  T.eq(plan.destroy[1], "Tank 1")
  T.eq(#plan.adopt, 1)
  T.eq(plan.adopt[1], "New Truck")
  T.eq(#plan.refresh, 0)
end)

T.test("a renamed FARP does not restore its old service Humvee", function()
  T.fresh()
  RH.state.farps["static1-4"] = { name = "static1-4", label = "FARP MUSTANG", x = 1, y = 2, editor = true }
  local plan = RH.world.plan({
    baseline = {},
    objects = {
      { name = "FARP MUSTANG Humvee", kind = "vehicle", x = 3, y = 4 },
      { name = "RH_TPL_BLUE_HMMWV_TOW#001", kind = "vehicle", x = 50, y = 80 },
    },
  }, {})
  T.eq(#plan.spawn, 1)
  T.eq(plan.spawn[1].name, "RH_TPL_BLUE_HMMWV_TOW#001")
  T.ok(RH.world.farpOwned("FARP MUSTANG Humvee"))
  T.ok(RH.world.farpOwned("static1-4 Tent"))
end)

T.test("a moved Humvee is respawned at the saved point", function()
  T.fresh()
  local saved = {
    baseline = {},
    objects = {
      { name = "RH_TPL_BLUE_HMMWV_TOW-1", kind = "vehicle", x = 1000, y = 2000, origin = "runtime" },
    },
  }
  local plan = RH.world.plan(saved, { { name = "RH_TPL_BLUE_HMMWV_TOW-1", x = 0, y = 0 } })
  T.eq(#plan.refresh, 1)
  T.eq(#plan.spawn, 0)
end)

T.test("the hook can reassemble the world save from slices", function()
  T.fresh()
  RH.world._payload = "{\n  name = \"Humvee #1\",\n}\n"
  T.eq(RH.world.payloadSlice(1, 10), "{\n  name =")
  T.eq(RH.world.payloadSlice(2, 10), " \"Humvee #")
  local n = #RH.world._payload
  local parts = {}
  for i = 1, math.ceil(n / 10) do parts[#parts + 1] = RH.world.payloadSlice(i, 10) end
  T.eq(table.concat(parts), RH.world._payload)
end)

T.test("world capture records a runtime Humvee and keeps the editor baseline", function()
  local w = T.fresh()
  local roster = {
    { name = "Shed", kind = "static", x = 1, y = 2 },
    { name = "Garrison North", kind = "vehicle", x = 3, y = 4 },
  }
  w.dcs.snapshotGround = function() return roster end
  T.ok(RH.world.capture())
  T.eq(RH.state.world.baseline["Shed"], true)
  T.eq(RH.state.world.baselineReady, true)
  roster = {
    { name = "Shed", kind = "static", x = 1, y = 2 },
    { name = "RH_TPL_BLUE_HMMWV_TOW#001", kind = "vehicle", x = 8, y = 9 },
    { name = "Garrison North", kind = "vehicle", x = 3, y = 4 },
  }
  T.ok(RH.world.capture())
  T.eq(RH.state.world.baseline["RH_TPL_BLUE_HMMWV_TOW#001"], nil)
  local origins = {}
  for _, obj in ipairs(RH.state.world.objects) do origins[obj.name] = obj.origin end
  T.eq(origins["Shed"], "baseline")
  T.eq(origins["RH_TPL_BLUE_HMMWV_TOW#001"], "runtime")
  T.eq(origins["Garrison North"], nil)
  T.ok(w.files["save/world.lua"]:find("HMMWV"))
end)

T.test("world capture lists FARPs, pad fuel, and every name it has saved for the mission file", function()
  local w = T.fresh()
  RH.state.farps["FARP Mustang"] = { name = "FARP Mustang", x = 100, y = 200, built = true, label = "FARP Mustang" }
  RH.state.farps["FARP Bronco"] = { name = "FARP Bronco", x = 300, y = 400, pending = true, label = "FARP Bronco" }
  RH.state.farps["RH_FARP_Zone"] = { name = "RH_FARP_Zone", x = 1, y = 1, lc = true }
  RH.state.padStock = { ["FARP Mustang"] = { fuelKg = 1500, missiles = {}, granted = true }, Huge = { fuelKg = 5000000 } }
  local roster = { { name = "Truck", kind = "vehicle", x = 1, y = 2 } }
  w.dcs.snapshotGround = function() return roster end
  RH.world.capture()
  roster = {}
  RH.world.capture()
  local saved = RH.state.world
  T.eq(saved.seen["Truck"], true, "a dead truck stays known so the export can remove it")
  local names = {}
  for _, rec in ipairs(saved.farps) do names[rec.name] = rec end
  T.ok(names["FARP Mustang"] and names["FARP Bronco"], "built and marked FARPs are listed")
  T.eq(names["FARP Bronco"].pending, true)
  T.eq(names["RH_FARP_Zone"], nil, "a zone-only record with no pad is left out")
  T.eq(saved.pads["FARP Mustang"], 1500)
  T.eq(saved.pads.Huge, nil, "an unlimited reading is not a delivery")
  T.eq(#saved.farpServices, 5)
  T.eq(saved.airframes, 999)
  local hasC130 = false
  for _, typeName in ipairs(saved.helicopters) do if typeName == "C-130J-30" then hasC130 = true end end
  T.eq(hasC130, false, "fixed wing never gets a FARP slot")
end)

local function hostedSaveCopy(w, stamp)
  table.insert(w.zones, { name = "RH_SAVE_COPY", point = { x = 0, y = 0 }, radius = 50 })
  w.dcs.zoneProperty = function(zone, key)
    if zone == "RH_SAVE_COPY" and key == "savedAt" then return stamp end
  end
end

T.test("a save copy keeps the units the editor left in it", function()
  local w = T.fresh()
  RH.state.world = {
    baselineReady = true, savedAt = 5000,
    baseline = { Shed = true },
    objects = {
      { name = "Shed", kind = "static", x = 1, y = 2 },
      { name = "Deleted Humvee", kind = "vehicle", x = 5, y = 5 },
      { name = "Moved Tank", kind = "vehicle", x = 0, y = 0 },
    },
  }
  hostedSaveCopy(w, "4990")
  local spawned, destroyed = {}, {}
  w.dcs.spawnSnapshot = function(obj) spawned[#spawned + 1] = obj.name end
  w.dcs.destroyNamed = function(name) destroyed[#destroyed + 1] = name end
  w.dcs.groundRoster = function()
    return { { name = "Moved Tank", x = 900, y = 900 }, { name = "Editor Truck", x = 7, y = 7 } }
  end
  local plan = RH.world.restore()
  T.eq(RH.world.hostingSaveCopy, true)
  T.eq(#spawned, 0, "a vehicle deleted in the editor stays deleted, and a shed the editor removed is not rebuilt")
  T.eq(#destroyed, 0, "a tank moved in the editor is not dragged back")
  T.eq(plan.adopt[1], "Editor Truck")
  T.eq(RH.state.world.baseline["Editor Truck"], true)
end)

T.test("an old save copy falls back to putting units back from the save", function()
  local w = T.fresh()
  RH.state.world = {
    baselineReady = true, savedAt = 100000, baseline = {},
    objects = { { name = "Built Humvee", kind = "vehicle", x = 5, y = 5 } },
  }
  hostedSaveCopy(w, "1000")
  local spawned = {}
  w.dcs.spawnSnapshot = function(obj) spawned[#spawned + 1] = obj.name end
  w.dcs.groundRoster = function() return {} end
  RH.world.restore()
  T.eq(RH.world.hostingSaveCopy, false)
  T.eq(spawned[1], "Built Humvee")
  T.ok(w.messages[#w.messages].text:find("older than the save"), "the host is told to use the newer file")
end)

T.test("RH Manual.miz has no marker, so missing units come back as before", function()
  local w = T.fresh()
  RH.state.world = { baselineReady = true, baseline = {}, objects = { { name = "Built Humvee", kind = "vehicle", x = 5, y = 5 } } }
  local spawned = {}
  w.dcs.spawnSnapshot = function(obj) spawned[#spawned + 1] = obj.name end
  w.dcs.groundRoster = function() return {} end
  RH.world.restore()
  T.eq(RH.world.hostingSaveCopy, false)
  T.eq(spawned[1], "Built Humvee")
end)
