-- Reads a .miz, puts the saved ground war into its mission table, and writes a new .miz.
-- The original mission file is never modified. inflate.lua sits in the same folder as this file.
-- A DCS hook runs in its own environment, so a global set by the hook is not visible here.

local miz = {}

local function findInflate()
  local function usable(mod)
    return type(mod) == "table" and type(mod.inflate) == "function"
  end
  if usable(RH_INFLATE) then return RH_INFLATE end
  if _G and usable(_G.RH_INFLATE) then return _G.RH_INFLATE end
  local src = ""
  if debug and debug.getinfo then
    local info = debug.getinfo(1, "S")
    src = info and info.source or ""
  end
  src = src:gsub("^@", "")
  local dir = src:match("^(.*)[/\\][^/\\]+$")
  if not dir or not loadfile then return nil end
  local sep = dir:find("\\", 1, true) and "\\" or "/"
  local chunk = loadfile(dir .. sep .. "inflate.lua")
  if not chunk then return nil end
  local ok, mod = pcall(chunk)
  if ok and usable(mod) then return mod end
  return nil
end

local inflate = nil

function miz.use(mod)
  if type(mod) == "table" and type(mod.inflate) == "function" then inflate = mod end
end

local function inflater()
  if inflate and type(inflate.inflate) == "function" then return inflate end
  inflate = findInflate()
  return inflate
end

local function le16(n)
  n = math.floor(n) % 65536
  return string.char(n % 256, math.floor(n / 256))
end

local function le32(n)
  n = math.floor(n) % 4294967296
  local b1 = n % 256
  local b2 = math.floor(n / 256) % 256
  local b3 = math.floor(n / 65536) % 256
  local b4 = math.floor(n / 16777216) % 256
  return string.char(b1, b2, b3, b4)
end

local function u16(s, i)
  local a, b = s:byte(i, i + 1)
  return a + b * 256
end

local function u32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

local function bxor(a, b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local aa, bb = a % 2, b % 2
    if aa ~= bb then r = r + bit end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit = bit * 2
  end
  return r
end

local crcTable = {}
do
  for n = 0, 255 do
    local c = n
    for _ = 1, 8 do
      if c % 2 == 1 then c = bxor(math.floor(c / 2), 0xEDB88320) else c = math.floor(c / 2) end
    end
    crcTable[n] = c
  end
end

-- Lua 5.1 has no bit operators. The checksum runs a byte at a time through an 8-bit xor table,
-- so a 400 KB mission takes a fraction of a second instead of stalling the host.
local xor8, crcBytes
local function crcTables()
  if xor8 then return end
  xor8 = {}
  for a = 0, 255 do
    for b = 0, 255 do xor8[a * 256 + b] = bxor(a, b) end
  end
  crcBytes = { {}, {}, {}, {} }
  for n = 0, 255 do
    local c = crcTable[n]
    crcBytes[1][n] = c % 256
    crcBytes[2][n] = math.floor(c / 256) % 256
    crcBytes[3][n] = math.floor(c / 65536) % 256
    crcBytes[4][n] = math.floor(c / 16777216) % 256
  end
end

function miz.crc32(s)
  crcTables()
  local x, c0, c1, c2, c3 = xor8, crcBytes[1], crcBytes[2], crcBytes[3], crcBytes[4]
  local r0, r1, r2, r3 = 255, 255, 255, 255
  local byte = string.byte
  for i = 1, #s do
    local idx = x[r0 * 256 + byte(s, i)]
    r0 = x[c0[idx] * 256 + r1]
    r1 = x[c1[idx] * 256 + r2]
    r2 = x[c2[idx] * 256 + r3]
    r3 = c3[idx]
  end
  return (255 - r0) + (255 - r1) * 256 + (255 - r2) * 65536 + (255 - r3) * 16777216
end

local function inflateRaw(data)
  local out = {}
  local lib = inflater()
  if not lib then return nil, "inflate.lua was not loaded" end
  lib.inflate{ input = data, output = function(b) out[#out + 1] = string.char(b) end }
  return table.concat(out)
end

-- One zip entry. record is the original local-file bytes, including a data descriptor when present.
local function readZip(bytes)
  local eocd
  local from = math.max(1, #bytes - 65557)
  for i = #bytes - 21, from, -1 do
    if bytes:byte(i) == 0x50 and bytes:byte(i + 1) == 0x4b and bytes:byte(i + 2) == 0x05 and bytes:byte(i + 3) == 0x06 then
      eocd = i
      break
    end
  end
  if not eocd then return nil, "not a zip file" end
  local count = u16(bytes, eocd + 10)
  local cdOffset = u32(bytes, eocd + 16) + 1
  local entries = {}
  local p = cdOffset
  for _ = 1, count do
    if bytes:sub(p, p + 3) ~= "PK\001\002" then return nil, "bad central directory" end
    local method = u16(bytes, p + 10)
    local crc = u32(bytes, p + 16)
    local compSize = u32(bytes, p + 20)
    local uncompSize = u32(bytes, p + 24)
    local nameLen = u16(bytes, p + 28)
    local extraLen = u16(bytes, p + 30)
    local commentLen = u16(bytes, p + 32)
    local localOff = u32(bytes, p + 42) + 1
    local name = bytes:sub(p + 46, p + 45 + nameLen)
    if bytes:sub(localOff, localOff + 3) ~= "PK\003\004" then return nil, "bad local header for " .. name end
    local flag = u16(bytes, localOff + 6)
    local localMethod = u16(bytes, localOff + 8)
    local localNameLen = u16(bytes, localOff + 26)
    local localExtraLen = u16(bytes, localOff + 28)
    local dataStart = localOff + 30 + localNameLen + localExtraLen
    local dataEnd = dataStart + compSize - 1
    local recordEnd = dataEnd
    if flag % 16 >= 8 then
      local sig = bytes:sub(dataEnd + 1, dataEnd + 4)
      if sig == "PK\007\008" then recordEnd = dataEnd + 16 else recordEnd = dataEnd + 12 end
    end
    local data = bytes:sub(dataStart, dataEnd)
    entries[#entries + 1] = {
      name = name,
      method = localMethod ~= 0 and localMethod or method,
      crc = crc,
      compSize = compSize,
      uncompSize = uncompSize,
      record = bytes:sub(localOff, recordEnd),
      data = data,
    }
    p = p + 46 + nameLen + extraLen + commentLen
  end
  return entries
end

local function writeZip(entries)
  local parts = {}
  local central = {}
  local offset = 0
  for _, e in ipairs(entries) do
    parts[#parts + 1] = e.record
    local nameLen = #e.name
    central[#central + 1] = "PK\001\002"
      .. le16(20) .. le16(20) .. le16(0) .. le16(e.method)
      .. le16(0) .. le16(0)
      .. le32(e.crc) .. le32(e.compSize) .. le32(e.uncompSize)
      .. le16(nameLen) .. le16(0) .. le16(0)
      .. le16(0) .. le16(0) .. le32(0)
      .. le32(offset) .. e.name
    offset = offset + #e.record
  end
  local cd = table.concat(central)
  parts[#parts + 1] = cd
  parts[#parts + 1] = "PK\005\006" .. le16(0) .. le16(0) .. le16(#entries) .. le16(#entries)
    .. le32(#cd) .. le32(offset) .. le16(0)
  return table.concat(parts)
end

local function storedRecord(name, data)
  local crc = miz.crc32(data)
  local header = "PK\003\004" .. le16(20) .. le16(0) .. le16(0) .. le16(0) .. le16(0)
    .. le32(crc) .. le32(#data) .. le32(#data) .. le16(#name) .. le16(0) .. name
  return {
    name = name,
    method = 0,
    crc = crc,
    compSize = #data,
    uncompSize = #data,
    record = header .. data,
  }
end

function miz.entryText(entry)
  if entry.method == 0 then return entry.data end
  if entry.method == 8 then return inflateRaw(entry.data) end
  return nil, "unsupported zip method " .. tostring(entry.method) .. " for " .. entry.name
end

-- Lua-literal serializer. Every numeric key is written as [n], the way the Mission Editor saves,
-- so a table with gaps (warehouse ids, airport ids) reads back with the same keys.
local function serialize(value, indent)
  indent = indent or ""
  local t = type(value)
  if t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then return "0" end
    if value == math.floor(value) and math.abs(value) < 1e15 then return string.format("%d", value) end
    return string.format("%.6f", value)
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "table" then
    local nextIndent = indent .. "  "
    local parts = {}
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local na, nb = type(a) == "number", type(b) == "number"
      if na and nb then return a < b end
      if na ~= nb then return na end
      return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(keys) do
      local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. serialize(k) .. "]")
      parts[#parts + 1] = nextIndent .. key .. " = " .. serialize(value[k], nextIndent)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "nil"
end

function miz.loadTable(text, varName)
  if type(text) ~= "string" then return nil, varName .. " text missing" end
  if text:byte(1) == 239 and text:byte(2) == 187 and text:byte(3) == 191 then text = text:sub(4) end
  local fn, err = loadstring(text)
  if not fn then return nil, err end
  local env = {}
  if setfenv then setfenv(fn, env) end
  local ok, err2 = pcall(fn)
  if not ok then return nil, err2 end
  if type(env[varName]) ~= "table" then return nil, varName .. " table not found" end
  return env[varName]
end

function miz.loadMission(text)
  return miz.loadTable(text, "mission")
end

local function coalitionName(name)
  if name == "neutral" then return "neutrals" end
  return name or "blue"
end

local function bucketName(kind)
  if kind == "ship" then return "ship" end
  if kind == "static" then return "static" end
  return "vehicle"
end

local function walkCountries(mission, fn)
  local coal = mission.coalition or {}
  for _, side in ipairs({ "blue", "red", "neutrals" }) do
    local block = coal[side]
    local countries = block and block.country
    if type(countries) == "table" then
      for _, country in pairs(countries) do
        if type(country) == "table" then fn(side, country) end
      end
    end
  end
end

local function groupLabel(group)
  if type(group) ~= "table" then return nil end
  if type(group.name) == "string" then return group.name end
  local units = group.units
  local unit = units and (units[1] or units["1"])
  return unit and unit.name
end

local function maxId(mission)
  local max = 1000
  local function see(n)
    if type(n) == "number" and n > max then max = n end
  end
  walkCountries(mission, function(_, country)
    for _, bucket in ipairs({ "vehicle", "ship", "static", "plane", "helicopter" }) do
      local groups = country[bucket] and country[bucket].group
      if type(groups) == "table" then
        for _, group in pairs(groups) do
          if type(group) == "table" then
            see(group.groupId)
            if type(group.units) == "table" then
              for _, unit in pairs(group.units) do
                if type(unit) == "table" then see(unit.unitId) end
              end
            end
          end
        end
      end
    end
  end)
  return max
end

local function denseGroups(groups, drop, droppedIds)
  local kept = {}
  for _, group in pairs(groups or {}) do
    local name = groupLabel(group)
    if type(group) == "table" then
      if not (name and drop[name]) then
        kept[#kept + 1] = group
      elseif droppedIds and type(group.units) == "table" then
        for _, unit in pairs(group.units) do
          if type(unit) == "table" and type(unit.unitId) == "number" then droppedIds[#droppedIds + 1] = unit.unitId end
        end
      end
    end
  end
  table.sort(kept, function(a, b) return tostring(groupLabel(a)) < tostring(groupLabel(b)) end)
  return kept
end

local function nextId(state)
  state.n = state.n + 1
  return state.n
end

-- Groups are written with every field the Mission Editor writes. The editor stops loading on a group that lacks them.
local function vehicleRoute(x, y)
  return {
    spans = {},
    routeRelativeTOT = true,
    points = { {
      alt = 0, alt_type = "BARO", type = "Turning Point", action = "Off Road", formation_template = "",
      ETA = 0, ETA_locked = true, speed = 0, speed_locked = true, x = x, y = y,
      task = { id = "ComboTask", params = { tasks = {} } },
    } },
  }
end

local function staticRoute(x, y)
  return { points = { { alt = 0, type = "", name = "", action = "", speed = 0, formation_template = "", x = x, y = y } } }
end

local function vehicleUnit(unit, obj, ids)
  return {
    name = unit.name or obj.name,
    type = unit.type or obj.type or "Hummer",
    x = unit.x or obj.x or 0,
    y = unit.y or obj.y or 0,
    heading = unit.heading or obj.heading or 0,
    skill = unit.skill or "Average",
    unitId = nextId(ids),
    playerCanDrive = false,
    coldAtStart = false,
  }
end

local function vehicleGroup(obj, ids)
  local units = {}
  for i, unit in ipairs(obj.units or {}) do units[i] = vehicleUnit(unit, obj, ids) end
  if #units == 0 then units[1] = vehicleUnit({}, obj, ids) end
  local x, y = units[1].x, units[1].y
  return {
    name = obj.name,
    task = "Ground Nothing",
    taskSelected = true,
    tasks = {},
    x = x,
    y = y,
    visible = false,
    hidden = false,
    lateActivation = false,
    uncontrollable = false,
    start_time = 0,
    groupId = nextId(ids),
    route = vehicleRoute(x, y),
    units = units,
  }
end

local function isCargoType(typeName)
  local t = string.lower(tostring(typeName or ""))
  return t:find("cargo", 1, true) ~= nil or t:find("crate", 1, true) ~= nil
end

local function staticGroup(obj, ids)
  local x, y = obj.x or 0, obj.y or 0
  local unit = {
    name = obj.name,
    type = obj.type or "FARP Tent",
    x = x,
    y = y,
    heading = obj.heading or 0,
    category = obj.category or "Fortifications",
    unitId = nextId(ids),
  }
  if obj.shape then unit.shape_name = obj.shape end
  if obj.farp then
    unit.category = "Heliports"
    unit.heliport_frequency = tonumber(obj.freq) or 127.5
    unit.heliport_modulation = 0
    unit.heliport_callsign_id = 1
    unit.dynamicSpawn = true
    unit.allowHotStart = true
  elseif unit.category == "Cargos" or isCargoType(unit.type) then
    unit.category = "Cargos"
    unit.mass = tonumber(obj.mass) or 1000
    unit.canCargo = true
  else
    unit.rate = 50
    unit.tasks = {}
  end
  return {
    name = obj.name,
    heading = obj.heading or 0,
    x = x,
    y = y,
    dead = false,
    groupId = nextId(ids),
    route = staticRoute(x, y),
    units = { unit },
  }
end

local function denseCountries(mission, side)
  mission.coalition = mission.coalition or {}
  mission.coalition[side] = mission.coalition[side] or { country = {} }
  local block = mission.coalition[side]
  local dense = {}
  for _, country in pairs(type(block.country) == "table" and block.country or {}) do
    if type(country) == "table" then dense[#dense + 1] = country end
  end
  block.country = dense
  return dense
end

-- A country the editor did not write has no name, and the editor cannot load it. Units go into a
-- country already in the file: the same id on that side, else that id on another side, else the side's first country.
local function ensureCountry(mission, side, countryId)
  for _, country in ipairs(denseCountries(mission, side)) do
    if country.id == countryId then return country end
  end
  for _, other in ipairs({ "blue", "red", "neutrals" }) do
    for _, country in ipairs(denseCountries(mission, other)) do
      if country.id == countryId and type(country.name) == "string" then return country end
    end
  end
  for _, try in ipairs({ side, "blue", "red" }) do
    local first = denseCountries(mission, try)[1]
    if first and type(first.name) == "string" then return first end
  end
  return nil
end

local function updateGroup(group, obj)
  if obj.x then group.x = obj.x end
  if obj.y then group.y = obj.y end
  if obj.heading then group.heading = obj.heading end
  if type(group.units) ~= "table" then return end
  if obj.kind == "static" then
    for _, unit in pairs(group.units) do
      if type(unit) == "table" then
        if obj.x then unit.x = obj.x end
        if obj.y then unit.y = obj.y end
        if obj.heading then unit.heading = obj.heading end
      end
    end
    return
  end
  local byName = {}
  for _, unit in ipairs(obj.units or {}) do
    if unit.name then byName[unit.name] = unit end
  end
  local list = {}
  for _, unit in pairs(group.units) do
    if type(unit) == "table" then list[#list + 1] = unit end
  end
  local kept = {}
  for _, unit in ipairs(list) do
    local src = byName[unit.name]
    if not src and #list == 1 and #(obj.units or {}) == 1 then src = obj.units[1] end
    if src then
      if src.x then unit.x = src.x end
      if src.y then unit.y = src.y end
      if src.heading then unit.heading = src.heading end
      kept[#kept + 1] = unit
    end
  end
  -- A unit killed inside a living group stays out. A save with no matching names leaves the group alone.
  if #kept > 0 then group.units = kept end
end

local function findGroup(mission, name)
  local found
  walkCountries(mission, function(_, country)
    if found then return end
    for _, bucket in ipairs({ "vehicle", "ship", "static" }) do
      local groups = country[bucket] and country[bucket].group
      if type(groups) == "table" then
        for _, group in pairs(groups) do
          if groupLabel(group) == name then found = group return end
        end
      end
    end
  end)
  return found
end

local function addGroup(mission, obj, ids)
  if obj.kind == "ship" then return nil end
  local side = coalitionName(obj.coalition)
  local country = ensureCountry(mission, side, obj.country or 2)
  if not country then return nil end
  local bucket = bucketName(obj.kind)
  country[bucket] = country[bucket] or { group = {} }
  if type(country[bucket].group) ~= "table" then country[bucket].group = {} end
  local entry = obj.kind == "static" and staticGroup(obj, ids) or vehicleGroup(obj, ids)
  local groups = country[bucket].group
  groups[#groups + 1] = entry
  return entry
end

-- Bearing 0 is north (+x), 90 is east (+y), the same as COORDINATE:Translate in the running mission.
local function offset(point, dist, bearingDeg)
  local rad = math.rad(bearingDeg or 0)
  return point.x + math.cos(rad) * (dist or 0), point.y + math.sin(rad) * (dist or 0)
end

miz.SAVE_MARKER = "RH_SAVE_COPY"

-- The running campaign checks for this zone. Its presence means the file is a save, so the units in it are the war.
local function ensureMarker(mission, at, savedAt)
  mission.triggers = mission.triggers or {}
  mission.triggers.zones = mission.triggers.zones or {}
  local zones = mission.triggers.zones
  local properties = { { key = "savedAt", value = tostring(savedAt or 0) } }
  local maxZone = 0
  for _, zone in pairs(zones) do
    if type(zone) == "table" then
      if zone.name == miz.SAVE_MARKER then
        zone.properties = properties
        return
      end
      if type(zone.zoneId) == "number" and zone.zoneId > maxZone then maxZone = zone.zoneId end
    end
  end
  local list = {}
  for _, zone in pairs(zones) do
    if type(zone) == "table" then list[#list + 1] = zone end
  end
  list[#list + 1] = {
    name = miz.SAVE_MARKER,
    x = at and at.x or 0,
    y = at and at.y or 0,
    radius = 50,
    heading = 0,
    zoneId = maxZone + 1,
    hidden = true,
    type = 0,
    color = { 1, 1, 1, 0.15 },
    properties = properties,
  }
  mission.triggers.zones = list
end

local DEFAULT_HELICOPTERS = {
  "Mi-8MTV2", "Mi-8MT", "Mi-24P", "UH-1H", "UH-60L", "CH-47Fbl1",
  "SA342M", "SA342L", "SA342Mistral", "SA342Minigun", "OH58D", "OH-6A",
  "AH-64D_BLK_II", "Ka-50", "Ka-50_3",
}

-- The same entry the Mission Editor writes for a pad with Dynamic Spawn on. Fuel and air-to-ground
-- missiles are limited; the running campaign fills guns, rockets, and air-to-air from its own shelf list.
function miz.warehouseEntry(pad, helicopters)
  local limited = not pad.lc
  local heli = {}
  if limited then
    for _, name in ipairs(helicopters or DEFAULT_HELICOPTERS) do
      heli[name] = { initialAmount = pad.airframes or 999, unlimited = false }
    end
  end
  local full = limited and 0 or 100
  return {
    allowHotStart = true,
    dynamicSpawn = true,
    dynamicCargo = true,
    unlimitedMunitions = not limited,
    unlimitedAircrafts = not limited,
    unlimitedFuel = not limited,
    coalition = pad.coalition or "blue",
    jet_fuel = { InitFuel = limited and (pad.fuelKg or 0) / 1000 or 100 },
    gasoline = { InitFuel = full },
    diesel = { InitFuel = full },
    methanol_mixture = { InitFuel = full },
    aircrafts = limited and { helicopters = heli, planes = {} } or {},
    weapons = {},
    OperatingLevel_Air = 10,
    OperatingLevel_Eqp = 10,
    OperatingLevel_Fuel = 10,
    periodicity = 30,
    size = 100,
    speed = 16.666666,
    suppliers = {},
  }
end

local function padUnit(group)
  local units = type(group) == "table" and group.units
  local unit = units and (units[1] or units["1"])
  if type(unit) == "table" and unit.category == "Heliports" then return unit end
  return nil
end

-- Returns what the warehouses file needs: unit ids that left the mission and pads that joined it.
function miz.patch(mission, world)
  -- Everything the campaign has ever saved and is no longer alive leaves the file, so a
  -- destroyed unit does not come back. Living groups already in the file are moved in place,
  -- which keeps their ids, routes, loadouts, and warehouse settings.
  local result = { droppedIds = {}, newPads = {} }
  local alive = {}
  for _, obj in ipairs(world.objects or {}) do
    if type(obj.name) == "string" then alive[obj.name] = obj end
  end
  local drop = {}
  for name in pairs(world.baseline or {}) do
    if not alive[name] then drop[name] = true end
  end
  for name in pairs(world.seen or {}) do
    if not alive[name] then drop[name] = true end
  end
  walkCountries(mission, function(_, country)
    for _, bucket in ipairs({ "vehicle", "ship", "static" }) do
      if country[bucket] and type(country[bucket].group) == "table" then
        country[bucket].group = denseGroups(country[bucket].group, drop, result.droppedIds)
      end
    end
  end)

  local farpByName = {}
  for _, rec in ipairs(world.farps or {}) do
    if type(rec.name) == "string" then farpByName[rec.name] = rec end
  end
  local function notePad(entry, name, coalition)
    local unit = padUnit(entry)
    if not unit then return end
    local rec = farpByName[name] or {}
    result.newPads[#result.newPads + 1] = {
      unitId = unit.unitId,
      name = name,
      lc = rec.lc == true,
      coalition = coalitionName(coalition) == "red" and "red" or "blue",
      fuelKg = (world.pads or {})[name] or rec.fuelKg or 0,
    }
  end

  local ids = { n = maxId(mission) }
  local taken = {}
  walkCountries(mission, function(_, country)
    for _, bucket in ipairs({ "vehicle", "ship", "static", "plane", "helicopter" }) do
      for _, group in pairs(country[bucket] and type(country[bucket].group) == "table" and country[bucket].group or {}) do
        if type(group) == "table" then
          if group.name then taken[group.name] = true end
          for _, unit in pairs(type(group.units) == "table" and group.units or {}) do
            if type(unit) == "table" and unit.name then taken[unit.name] = true end
          end
        end
      end
    end
  end)
  -- Two units with one name keep the editor from loading. A group that would repeat a name stays out.
  local function nameFree(obj)
    if taken[obj.name] then return false end
    for _, unit in ipairs(obj.units or {}) do
      if unit.name and unit.name ~= obj.name and taken[unit.name] then return false end
    end
    return true
  end
  local function claim(obj)
    taken[obj.name] = true
    for _, unit in ipairs(obj.units or {}) do if unit.name then taken[unit.name] = true end end
  end
  for _, obj in ipairs(world.objects or {}) do
    if type(obj.name) == "string" then
      local group = findGroup(mission, obj.name)
      if group then
        updateGroup(group, obj)
      elseif nameFree(obj) then
        local entry = addGroup(mission, obj, ids)
        if entry then claim(obj) end
        if obj.farp then notePad(entry, obj.name, obj.coalition) end
      end
    end
  end

  -- A FARP marked this session has no pad yet. Writing it here makes it a pad DCS loads with the mission.
  for _, rec in ipairs(world.farps or {}) do
    if type(rec.name) == "string" and not rec.editor and rec.x and rec.y and not findGroup(mission, rec.name) then
      local pad = {
        name = rec.name, kind = "static", type = "FARP", category = "Heliports", shape = "FARPS", farp = true,
        freq = rec.freq, x = rec.x, y = rec.y, heading = 0, coalition = "blue", country = rec.country or 2,
      }
      notePad(addGroup(mission, pad, ids), rec.name, "blue")
      for _, piece in ipairs(world.farpServices or {}) do
        local pieceName = rec.name .. " " .. tostring(piece.label)
        if not findGroup(mission, pieceName) then
          local px, py = offset(rec, piece.dist or 40, piece.bearing or 0)
          local heading = math.rad(piece.heading or 0)
          if piece.kind == "vehicle" then
            addGroup(mission, {
              name = pieceName, kind = "vehicle", coalition = "blue", country = rec.country or 2, x = px, y = py, heading = heading,
              units = { { name = pieceName, type = piece.typeName or "Hummer", x = px, y = py, heading = heading } },
            }, ids)
          else
            addGroup(mission, {
              name = pieceName, kind = "static", coalition = "blue", country = rec.country or 2, type = piece.typeName,
              shape = piece.shape, category = piece.category or "Fortifications", x = px, y = py, heading = heading,
            }, ids)
          end
        end
      end
    end
  end

  -- Pads already in the file keep their warehouse. Their saved jet fuel is shown in the editor.
  result.padFuel = {}
  for name, fuelKg in pairs(world.pads or {}) do
    local unit = padUnit(findGroup(mission, name))
    if unit and type(unit.unitId) == "number" and type(fuelKg) == "number" then result.padFuel[unit.unitId] = fuelKg end
  end

  local first = (world.farps or {})[1]
  ensureMarker(mission, first and { x = first.x, y = first.y } or nil, world.savedAt)
  return mission, result
end

function miz.patchWarehouses(warehouses, result, world)
  warehouses = warehouses or {}
  warehouses.warehouses = warehouses.warehouses or {}
  warehouses.airports = warehouses.airports or {}
  local list = warehouses.warehouses
  for _, id in ipairs(result.droppedIds or {}) do list[id] = nil end
  for _, pad in ipairs(result.newPads or {}) do
    if type(pad.unitId) == "number" then
      pad.airframes = world and world.airframes
      list[pad.unitId] = miz.warehouseEntry(pad, world and world.helicopters)
    end
  end
  for id, fuelKg in pairs(result.padFuel or {}) do
    local entry = list[id]
    if type(entry) == "table" and entry.unlimitedFuel == false then
      entry.jet_fuel = entry.jet_fuel or {}
      entry.jet_fuel.InitFuel = fuelKg / 1000
    end
  end
  return warehouses
end

function miz.exportBytes(mizBytes, world)
  local entries, err = readZip(mizBytes)
  if not entries then return nil, err end
  local missionText, missionErr, warehouseText, warehouseErr
  local out = {}
  for _, entry in ipairs(entries) do
    if entry.name == "mission" then
      missionText, missionErr = miz.entryText(entry)
    elseif entry.name == "warehouses" then
      warehouseText, warehouseErr = miz.entryText(entry)
      if not warehouseText then return nil, warehouseErr end
    elseif entry.name:sub(1, 12) ~= "persistence/" then
      -- Esc, Save Mission leaves a hidden unit copy under persistence/. Loading it put deleted vehicles back.
      out[#out + 1] = entry
    end
  end
  if not missionText then return nil, missionErr or "mission entry not found" end
  local mission, loadErr = miz.loadMission(missionText)
  if not mission then return nil, loadErr end
  local _, result = miz.patch(mission, world)
  local warehouses
  if warehouseText then
    local loaded, whErr = miz.loadTable(warehouseText, "warehouses")
    if not loaded then return nil, whErr end
    warehouses = loaded
  end
  if warehouses or #result.newPads > 0 then
    warehouses = miz.patchWarehouses(warehouses, result, world)
    table.insert(out, 1, storedRecord("warehouses", "warehouses = " .. serialize(warehouses) .. "\n"))
  end
  table.insert(out, 1, storedRecord("mission", "mission = " .. serialize(mission) .. "\n"))
  return writeZip(out)
end

function miz.exportText(missionPath, worldText, destPath)
  local f = io.open(missionPath, "rb")
  if not f then return nil, "cannot read " .. tostring(missionPath) end
  local mizBytes = f:read("*a")
  f:close()
  if not mizBytes or mizBytes == "" then return nil, "cannot read " .. tostring(missionPath) end
  local fn, err = loadstring("return " .. worldText)
  if not fn then return nil, err end
  if setfenv then setfenv(fn, {}) end
  local ok, world = pcall(fn)
  if not ok or type(world) ~= "table" then return nil, "world save unreadable" end
  local bytes, exportErr = miz.exportBytes(mizBytes, world)
  if not bytes then return nil, exportErr end
  local canRename = os and os.rename and os.remove
  local tmp = canRename and destPath .. ".tmp" or destPath
  local out = io.open(tmp, "wb")
  if not out then return nil, "cannot write " .. tmp end
  out:write(bytes)
  out:close()
  if canRename then
    os.remove(destPath)
    if os.rename(tmp, destPath) == nil then return nil, "cannot replace " .. destPath end
  end
  return true
end

function miz.exportFile(missionPath, worldPath, destPath)
  local f = io.open(worldPath, "rb")
  if not f then return nil, "cannot read " .. tostring(worldPath) end
  local worldText = f:read("*a")
  f:close()
  if not worldText then return nil, "cannot read " .. tostring(worldPath) end
  return miz.exportText(missionPath, worldText, destPath)
end

if RH then RH.miz = miz end
return miz
