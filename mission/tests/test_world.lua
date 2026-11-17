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

T.test("editor mission is RH Test.miz unless the hook saw another file", function()
  T.fresh()
  local files = { ["C:\\DCS\\Missions\\RH Test.miz"] = true }
  T.eq(RH.world.pickSource("C:\\DCS\\", nil, function(p) return files[p] end), "C:\\DCS\\Missions\\RH Test.miz")
  files["D:\\Other.miz"] = true
  T.eq(RH.world.pickSource("C:\\DCS\\", "  D:\\Other.miz\r\n", function(p) return files[p] end), "D:\\Other.miz")
  T.eq(RH.world.pickSource("C:\\DCS\\", "C:\\DCS\\Missions\\RH_Editor.miz", function(p) return files[p] end), "C:\\DCS\\Missions\\RH Test.miz")
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
