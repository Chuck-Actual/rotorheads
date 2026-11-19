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

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Python unpacks the zip so the check does not trust the packer it is testing.
local function unpack(bytes)
  local path = os.tmpname() .. ".miz"
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
  local dir = path .. ".d"
  assert(os.execute(string.format("mkdir -p %q && cd %q && python3 -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall()' %q", dir, dir, path)) == 0, "python could not open the export")
  local list = assert(io.popen(string.format("cd %q && find . -type f | sort", dir)))
  local names = {}
  for line in list:lines() do names[line:gsub("^%./", "")] = true end
  list:close()
  return dir, names
end

local function staticsNamed(mission)
  local out = {}
  for _, side in pairs(mission.coalition) do
    for _, country in pairs(side.country or {}) do
      for _, bucket in ipairs({ "static", "vehicle" }) do
        for _, group in pairs(country[bucket] and country[bucket].group or {}) do
          out[group.name] = out[group.name] and (out[group.name] + 1) or 1
          out[group.name .. "#group"] = group
        end
      end
    end
  end
  return out
end

local function manualWorld()
  return {
    savedAt = 1700000000,
    baseline = {},
    seen = {},
    objects = {},
    farps = {
      { name = "FARP Pinto", x = 41000, y = 12000, pending = true },
      { name = "static1-4", x = 40763, y = 9580, editor = true },
    },
    pads = { ["FARP Pinto"] = 2500, ["static1-4"] = 900 },
    farpServices = {
      { kind = "static", label = "Tent", typeName = "FARP Tent", shape = "PalatkaB", category = "Fortifications", dist = 70, bearing = 270, heading = 90 },
      { kind = "vehicle", label = "Humvee", typeName = "Hummer", dist = 45, bearing = 270, heading = 90 },
    },
    airframes = 999,
    helicopters = { "UH-1H", "CH-47Fbl1" },
  }
end

T.test("a marked FARP goes into RH Manual.miz as a real pad with a limited dynamic-spawn warehouse", function()
  local miz = loadMiz()
  local out, err = miz.exportBytes(readFile("RH_Manual.miz"), manualWorld())
  T.ok(out, err)
  local dir, names = unpack(out)
  T.ok(names["mission"] and names["warehouses"] and names["options"], "the main files are kept")
  for name in pairs(names) do T.ok(name:sub(1, 12) ~= "persistence/", "the hidden Save Mission copy is dropped: " .. name) end
  local mission = assert(miz.loadMission(readFile(dir .. "/mission")))
  local wh = assert(miz.loadTable(readFile(dir .. "/warehouses"), "warehouses"))
  local found = staticsNamed(mission)
  local pad = found["FARP Pinto#group"]
  T.ok(pad, "pad written")
  local unit = pad.units[1]
  T.eq(unit.category, "Heliports")
  T.eq(unit.type, "FARP")
  T.eq(unit.shape_name, "FARPS")
  T.eq(unit.dynamicSpawn, true)
  T.eq(unit.allowHotStart, true)
  T.ok(found["FARP Pinto Tent#group"], "tent written")
  T.ok(math.abs(found["FARP Pinto Tent#group"].x - 41000) < 0.01, "tent is due west, so x is unchanged")
  T.ok(math.abs(found["FARP Pinto Tent#group"].y - (12000 - 70)) < 0.01, "tent is 70 m west")
  T.eq(found["FARP Pinto Humvee#group"].units[1].type, "Hummer")
  local entry = wh.warehouses[unit.unitId]
  T.ok(entry, "the new pad has a warehouse entry")
  T.eq(entry.dynamicSpawn, true)
  T.eq(entry.allowHotStart, true)
  T.eq(entry.unlimitedFuel, false)
  T.eq(entry.unlimitedMunitions, false)
  T.eq(entry.unlimitedAircrafts, false)
  T.eq(entry.jet_fuel.InitFuel, 2.5, "the saved 2500 kg shows as 2.5 tons in the editor")
  T.eq(entry.aircrafts.helicopters["CH-47Fbl1"].initialAmount, 999)
  T.eq(entry.aircrafts.planes["C-130J-30"], nil)
  local srcDir = unpack(readFile("RH_Manual.miz"))
  local before = assert(miz.loadTable(readFile(srcDir .. "/warehouses"), "warehouses"))
  local editorPadId = staticsNamed(assert(miz.loadMission(readFile(srcDir .. "/mission"))))["static1-4#group"].units[1].unitId
  for id, old in pairs(before.warehouses) do
    local new = wh.warehouses[id]
    T.ok(new, "editor warehouse " .. tostring(id) .. " is kept")
    T.eq(new.dynamicSpawn, old.dynamicSpawn)
    T.eq(new.unlimitedFuel, old.unlimitedFuel)
  end
  local editorEntry = wh.warehouses[editorPadId]
  if editorEntry.unlimitedFuel == false then
    T.eq(editorEntry.jet_fuel.InitFuel, 0.9, "the editor pad shows its saved fuel")
  end
  os.execute(string.format("rm -rf %q", srcDir))
  local zones = {}
  for _, z in pairs(mission.triggers.zones) do zones[z.name] = z end
  T.ok(zones.RH_SAVE_COPY, "the save marker is written")
  T.eq(zones.RH_SAVE_COPY.properties[1].value, "1700000000")
  T.ok(zones.RH_SAVE_COPY.hidden)
  T.ok(next(wh.airports) ~= nil, "airfield warehouses are kept")
  os.execute(string.format("rm -rf %q", dir))
end)

T.test("exporting the save copy again keeps one pad, one id, and one warehouse entry", function()
  local miz = loadMiz()
  local world = manualWorld()
  local first = assert(miz.exportBytes(readFile("RH_Manual.miz"), world))
  local dir1 = unpack(first)
  local m1 = assert(miz.loadMission(readFile(dir1 .. "/mission")))
  local padId = staticsNamed(m1)["FARP Pinto#group"].units[1].unitId
  -- Next session: the pad is up and alive, fuel was delivered, a Humvee was built and then killed.
  world.farps[1].pending = false
  world.farps[1].built = true
  world.pads["FARP Pinto"] = 4000
  world.objects = {
    { name = "FARP Pinto", kind = "static", origin = "farp", coalition = "blue", country = 2, farp = true, type = "FARP", x = 41000, y = 12000, heading = 0 },
    { name = "FARP Pinto Tent", kind = "static", origin = "farp", coalition = "blue", country = 2, type = "FARP Tent", x = 41000, y = 11930, heading = 0 },
    { name = "FARP Pinto Humvee", kind = "vehicle", origin = "farp", coalition = "blue", country = 2, x = 41000, y = 11955,
      units = { { name = "FARP Pinto Humvee", type = "Hummer", x = 41000, y = 11955 } } },
  }
  world.seen = { ["FARP Pinto"] = true, ["FARP Pinto Tent"] = true, ["FARP Pinto Humvee"] = true, ["Dead Humvee"] = true }
  local second = assert(miz.exportBytes(first, world))
  local dir2 = unpack(second)
  local m2 = assert(miz.loadMission(readFile(dir2 .. "/mission")))
  local wh = assert(miz.loadTable(readFile(dir2 .. "/warehouses"), "warehouses"))
  local found = staticsNamed(m2)
  T.eq(found["FARP Pinto"], 1, "one pad")
  T.eq(found["FARP Pinto Tent"], 1, "one tent")
  T.eq(found["FARP Pinto#group"].units[1].unitId, padId, "the pad keeps its id")
  T.eq(wh.warehouses[padId].jet_fuel.InitFuel, 4, "the delivered fuel is shown")
  local markers = 0
  for _, z in pairs(m2.triggers.zones) do if z.name == "RH_SAVE_COPY" then markers = markers + 1 end end
  T.eq(markers, 1)
  os.execute(string.format("rm -rf %q %q", dir1, dir2))
end)

T.test("a saved unit that died leaves the file, and so does its warehouse entry", function()
  local miz = loadMiz()
  local mission = sampleMission()
  mission.coalition.blue.country[1].static = { group = {
    { name = "FARP Gone", units = { { name = "FARP Gone", type = "FARP", category = "Heliports", unitId = 77 } } },
  } }
  mission.coalition.blue.country[1].vehicle.group[3] = {
    name = "Built Truck", units = { { name = "Built Truck", type = "Ural-375", unitId = 78 } },
  }
  local world = { baseline = {}, seen = { ["FARP Gone"] = true, ["Built Truck"] = true }, objects = {} }
  local _, result = miz.patch(mission, world)
  local found = staticsNamed(mission)
  T.eq(found["FARP Gone"], nil)
  T.eq(found["Built Truck"], nil)
  T.ok(found["RH_TPL_BLUE_HMMWV_TOW"], "a template the save never held stays")
  local wh = miz.patchWarehouses({ warehouses = { [77] = { dynamicSpawn = true } } }, result, world)
  T.eq(wh.warehouses[77], nil)
end)

T.test("a living group in the file keeps its id and loses only its dead unit", function()
  local miz = loadMiz()
  local mission = sampleMission()
  mission.coalition.blue.country[1].vehicle.group[3] = {
    name = "Convoy Pair", groupId = 50,
    units = { { name = "Pair 1", type = "Ural-375", unitId = 51 }, { name = "Pair 2", type = "Ural-375", unitId = 52 } },
  }
  miz.patch(mission, { baseline = {}, seen = {}, objects = {
    { name = "Convoy Pair", kind = "vehicle", origin = "runtime", x = 9, y = 9, units = { { name = "Pair 2", x = 9, y = 9 } } },
  } })
  local group = staticsNamed(mission)["Convoy Pair#group"]
  T.eq(group.groupId, 50)
  T.eq(#group.units, 1)
  T.eq(group.units[1].unitId, 52)
  T.eq(group.units[1].x, 9)
end)

T.test("a logistics center pad gets an unlimited warehouse", function()
  local miz = loadMiz()
  local entry = miz.warehouseEntry({ lc = true })
  T.eq(entry.unlimitedFuel, true)
  T.eq(entry.unlimitedMunitions, true)
  T.eq(entry.unlimitedAircrafts, true)
  T.eq(entry.dynamicSpawn, true)
end)

T.test("the fast checksum matches zlib", function()
  local miz = loadMiz()
  local cases = { "", "a", "123456789", string.rep("\255\0\128", 1000) }
  for _, s in ipairs(cases) do
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
    local p = assert(io.popen("python3 -c 'import zlib,sys;print(zlib.crc32(open(sys.argv[1],\"rb\").read()))' " .. path))
    local want = tonumber(p:read("*l"))
    p:close()
    os.remove(path)
    T.eq(miz.crc32(s), want, "crc of " .. #s .. " bytes")
  end
end)

T.test("the export works in the DCS hook environment, which has no io.type, io.stderr, os.remove or os.rename", function()
  local saved = { iotype = io.type, stderr = io.stderr, remove = os.remove, rename = os.rename }
  local dest = os.tmpname() .. " RH Campaign A.miz"
  local worldText = '{ savedAt = 1700000000, baseline = {}, seen = {}, objects = {}, farps = { { name = "FARP Pinto", x = 41000, y = 12000, pending = true } }, pads = { ["FARP Pinto"] = 0 }, airframes = 999, helicopters = { "UH-1H" } }'
  local ok, result, err = pcall(function()
    local miz = loadMiz()
    io.type, io.stderr, os.remove, os.rename = nil, nil, nil, nil
    return miz.exportText("RH_Manual.miz", worldText, dest)
  end)
  io.type, io.stderr, os.remove, os.rename = saved.iotype, saved.stderr, saved.remove, saved.rename
  T.ok(ok, tostring(result))
  T.ok(result, tostring(err))
  local dir, names = unpack(readFile(dest))
  T.ok(names["mission"] and names["warehouses"], "the campaign file opens")
  T.ok(readFile(dir .. "/mission"):find("FARP Pinto", 1, true), "the marked FARP is in it")
end)
