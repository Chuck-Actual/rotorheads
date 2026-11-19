local function loadMiz()
  RH_INFLATE = dofile("src/rh/inflate.lua")
  return dofile("src/rh/miz.lua")
end

local function sampleMission()
  return {
    theatre = "Syria",
    coalition = {
      blue = {
        country = {
          {
            id = 2,
            vehicle = {
              group = {
                {
                  name = "Tank 1",
                  task = "Ground Nothing",
                  x = 0, y = 0,
                  groupId = 10,
                  route = { points = { { x = 0, y = 0, action = "On Road" } } },
                  units = { { name = "Tank 1", type = "M-1 Abrams", x = 0, y = 0, unitId = 11, skill = "Excellent" } },
                },
                {
                  name = "RH_TPL_BLUE_HMMWV_TOW",
                  x = 5, y = 5,
                  units = { { name = "RH_TPL_BLUE_HMMWV_TOW", type = "Hummer", x = 5, y = 5, unitId = 12 } },
                },
              },
            },
            plane = {
              group = {
                { name = "Viper", units = { { name = "Viper", type = "F-16C_50", unitId = 40 } } },
              },
            },
          },
        },
      },
    },
  }
end

T.test("editor patch adds a Humvee, moves a tank, and deletes a dead one", function()
  local miz = loadMiz()
  local mission = sampleMission()
  mission.coalition.blue.country[1].vehicle.group[#mission.coalition.blue.country[1].vehicle.group + 1] = {
    name = "Old Truck", x = 1, y = 1, units = { { name = "Old Truck", type = "Ural-375", unitId = 13 } },
  }
  miz.patch(mission, {
    baseline = { ["Tank 1"] = true, ["Old Truck"] = true },
    objects = {
      { name = "Tank 1", kind = "vehicle", origin = "baseline", x = 30, y = 40, units = { { name = "Tank 1", x = 30, y = 40, heading = 1.5 } } },
      { name = "RH_TPL_BLUE_HMMWV_TOW#001", kind = "vehicle", origin = "runtime", coalition = "blue", country = 2, x = 100, y = 200,
        units = { { name = "Humvee unit", type = "Hummer", x = 100, y = 200, heading = 0.2 } } },
      { name = "FARP 01", kind = "static", origin = "farp", coalition = "blue", country = 2, farp = true, type = "FARP",
        x = 8, y = 9, heading = 0, freq = 127.5 },
    },
  })
  local groups = mission.coalition.blue.country[1].vehicle.group
  local names = {}
  for _, g in ipairs(groups) do names[g.name] = g end
  T.ok(names["Tank 1"], "tank stays")
  T.eq(names["Tank 1"].x, 30)
  T.eq(names["Tank 1"].units[1].skill, "Excellent")
  T.eq(names["Tank 1"].route.points[1].action, "On Road")
  T.ok(names["RH_TPL_BLUE_HMMWV_TOW"], "template stays")
  T.ok(names["RH_TPL_BLUE_HMMWV_TOW#001"], "built humvee added")
  T.eq(names["Old Truck"], nil)
  T.eq(mission.coalition.blue.country[1].plane.group[1].name, "Viper")
  local statics = mission.coalition.blue.country[1].static.group
  T.eq(statics[1].name, "FARP 01")
  T.eq(statics[1].units[1].dynamicSpawn, true)
  T.eq(statics[1].units[1].allowHotStart, true)
  T.eq(statics[1].units[1].category, "Heliports")
end)

T.test("miz round trip keeps a deflated options file and the patched mission", function()
  local miz = loadMiz()
  local builder = os.tmpname() .. ".py"
  local bf = assert(io.open(builder, "w"))
  bf:write([[
import zipfile
mission = """mission = {
  theatre = "Syria",
  coalition = {
    blue = { country = { { id = 2, vehicle = { group = { { name = "Tank 1", x = 0, y = 0, units = { { name = "Tank 1", type = "M-1 Abrams", x = 0, y = 0 } } } } } } } },
  },
}
"""
with zipfile.ZipFile("/tmp/rh-sample.miz", "w", compression=zipfile.ZIP_DEFLATED) as z:
    z.writestr("mission", mission)
    z.writestr("options", "options = { keep = true }")
]])
  bf:close()
  assert(os.execute("python3 " .. builder) == 0, "could not build sample miz")
  os.remove(builder)
  local src = assert(io.open("/tmp/rh-sample.miz", "rb"))
  local raw = src:read("*a")
  src:close()
  local world = {
    baseline = { ["Tank 1"] = true },
    objects = {
      { name = "Tank 1", kind = "vehicle", origin = "baseline", coalition = "blue", country = 2, x = 12, y = 34,
        units = { { name = "Tank 1", type = "M-1 Abrams", x = 12, y = 34 } } },
      { name = "Field Humvee", kind = "vehicle", origin = "runtime", coalition = "blue", country = 2, x = 70, y = 80,
        units = { { name = "Field Humvee", type = "Hummer", x = 70, y = 80 } } },
    },
  }
  local out, err = miz.exportBytes(raw, world)
  T.ok(out, err)
  local f = assert(io.open("/tmp/rh-editor-test.miz", "wb"))
  f:write(out)
  f:close()
  local checker = os.tmpname() .. ".py"
  local cf = assert(io.open(checker, "w"))
  cf:write([[
import zipfile
z = zipfile.ZipFile("/tmp/rh-editor-test.miz")
opts = z.read("options").decode()
mission = z.read("mission").decode()
print(opts)
print("HUMVEE" if "Field Humvee" in mission else "NOHUMVEE")
print("MOVED" if "x = 12" in mission else "NOMOVE")
print("TANKSKILL" if "M-1 Abrams" in mission else "NOTANK")
]])
  cf:close()
  local check = assert(io.popen("python3 " .. checker, "r"))
  local report = check:read("*a")
  check:close()
  os.remove(checker)
  T.ok(report:find("keep = true", 1, true), report)
  T.ok(report:find("HUMVEE"), report)
  T.ok(report:find("MOVED"), report)
  T.ok(report:find("TANKSKILL"), report)
end)
