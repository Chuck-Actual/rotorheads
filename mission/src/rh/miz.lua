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

local inflate = findInflate()
assert(inflate, "inflate.lua was not loaded from the Hooks folder")

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

function miz.crc32(s)
  local crc = 0xFFFFFFFF
  for i = 1, #s do
    local idx = bxor(crc % 256, s:byte(i))
    crc = bxor(crcTable[idx], math.floor(crc / 256))
  end
  return bxor(crc, 0xFFFFFFFF)
end

local function inflateRaw(data)
  local out = {}
  inflate.inflate{ input = data, output = function(b) out[#out + 1] = string.char(b) end }
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

-- Lua-literal serializer. Same shape as RH.util.serialize, kept here so the hook has no other dependency.
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
    local n = #value
    for i = 1, n do parts[#parts + 1] = nextIndent .. serialize(value[i], nextIndent) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local isArray = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
      if not isArray then
        local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. serialize(k) .. "]")
        parts[#parts + 1] = nextIndent .. key .. " = " .. serialize(value[k], nextIndent)
      end
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "nil"
end

function miz.loadMission(text)
  if type(text) ~= "string" then return nil, "mission text missing" end
  if text:byte(1) == 239 and text:byte(2) == 187 and text:byte(3) == 191 then text = text:sub(4) end
  local fn, err = loadstring(text)
  if not fn then return nil, err end
  local env = {}
  if setfenv then setfenv(fn, env) end
  local ok, err2 = pcall(fn)
  if not ok then return nil, err2 end
  if type(env.mission) ~= "table" then return nil, "mission table not found" end
  return env.mission
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

local function denseGroups(groups, drop)
  local kept = {}
  for _, group in pairs(groups or {}) do
    local name = groupLabel(group)
    if type(group) == "table" and not (name and drop[name]) then kept[#kept + 1] = group end
  end
  table.sort(kept, function(a, b) return tostring(groupLabel(a)) < tostring(groupLabel(b)) end)
  return kept
end

local function nextId(state)
  state.n = state.n + 1
  return state.n
end

local function vehicleGroup(obj, ids)
  local units = {}
  for i, unit in ipairs(obj.units or {}) do
    units[i] = {
      name = unit.name or obj.name,
      type = unit.type or obj.type or "Hummer",
      x = unit.x or obj.x or 0,
      y = unit.y or obj.y or 0,
      heading = unit.heading or obj.heading or 0,
      skill = unit.skill or "Average",
      unitId = nextId(ids),
      playerCanDrive = false,
      transportable = { randomTransportable = false },
    }
  end
  if #units == 0 then
    units[1] = {
      name = obj.name, type = obj.type or "Hummer", x = obj.x or 0, y = obj.y or 0,
      heading = obj.heading or 0, skill = "Average", unitId = nextId(ids),
      playerCanDrive = false, transportable = { randomTransportable = false },
    }
  end
  return {
    name = obj.name,
    task = "Ground Nothing",
    x = obj.x or 0,
    y = obj.y or 0,
    visible = true,
    groupId = nextId(ids),
    route = { points = { { x = obj.x or 0, y = obj.y or 0, type = "Off Road", action = "Off Road", speed = 0 } } },
    units = units,
  }
end

local function staticGroup(obj, ids)
  local unit = {
    name = obj.name,
    type = obj.type or "FARP Tent",
    x = obj.x or 0,
    y = obj.y or 0,
    heading = obj.heading or 0,
    category = obj.category or "Fortifications",
    unitId = nextId(ids),
  }
  if obj.shape then unit.shape_name = obj.shape end
  if obj.farp then
    unit.category = "Heliports"
    unit.heliport_frequency = tostring(obj.freq or "127.5")
    unit.heliport_modulation = 0
    unit.heliport_callsign_id = 1
    unit.dynamicSpawn = true
  end
  return {
    name = obj.name,
    heading = obj.heading or 0,
    x = obj.x or 0,
    y = obj.y or 0,
    dead = false,
    groupId = nextId(ids),
    units = { unit },
  }
end

local function ensureCountry(mission, side, countryId)
  mission.coalition = mission.coalition or {}
  mission.coalition[side] = mission.coalition[side] or { country = {} }
  local countries = mission.coalition[side].country
  if type(countries) ~= "table" then countries = {} mission.coalition[side].country = countries end
  local dense = {}
  for _, country in pairs(countries) do
    if type(country) == "table" then dense[#dense + 1] = country end
  end
  for _, country in ipairs(dense) do
    if country.id == countryId then
      mission.coalition[side].country = dense
      return country
    end
  end
  local country = { id = countryId }
  dense[#dense + 1] = country
  mission.coalition[side].country = dense
  return country
end

local function updateGroup(group, obj)
  if obj.x then group.x = obj.x end
  if obj.y then group.y = obj.y end
  if obj.heading then group.heading = obj.heading end
  local byName = {}
  for _, unit in ipairs(obj.units or {}) do
    if unit.name then byName[unit.name] = unit end
  end
  if type(group.units) ~= "table" then return end
  for _, unit in pairs(group.units) do
    if type(unit) == "table" then
      local src = byName[unit.name]
      if not src and #(obj.units or {}) == 1 then src = obj.units[1] end
      if src then
        if src.x then unit.x = src.x end
        if src.y then unit.y = src.y end
        if src.heading then unit.heading = src.heading end
      end
    end
  end
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

function miz.patch(mission, world)
  -- Runtime and FARP objects are rewritten from the save. Editor-placed groups stay, and
  -- only their position is moved, so routes and loadouts are left alone. Dead editor groups
  -- are removed so a destroyed unit does not come back.
  local alive = {}
  for _, obj in ipairs(world.objects or {}) do
    if type(obj.name) == "string" then alive[obj.name] = obj end
  end
  local drop = {}
  for _, obj in ipairs(world.objects or {}) do
    if obj.origin ~= "baseline" then drop[obj.name] = true end
  end
  for name in pairs(world.baseline or {}) do
    if not alive[name] then drop[name] = true end
  end
  walkCountries(mission, function(_, country)
    for _, bucket in ipairs({ "vehicle", "ship", "static" }) do
      if country[bucket] and type(country[bucket].group) == "table" then
        country[bucket].group = denseGroups(country[bucket].group, drop)
      end
    end
  end)
  for _, obj in ipairs(world.objects or {}) do
    if obj.origin == "baseline" then
      local group = findGroup(mission, obj.name)
      if group then updateGroup(group, obj) end
    end
  end
  local ids = { n = maxId(mission) }
  for _, obj in ipairs(world.objects or {}) do
    local missing = obj.origin ~= "baseline" or not findGroup(mission, obj.name)
    if missing and type(obj.name) == "string" then
      local side = coalitionName(obj.coalition)
      local country = ensureCountry(mission, side, obj.country or 2)
      local bucket = bucketName(obj.kind)
      country[bucket] = country[bucket] or { group = {} }
      if type(country[bucket].group) ~= "table" then country[bucket].group = {} end
      local entry = obj.kind == "static" and staticGroup(obj, ids) or vehicleGroup(obj, ids)
      local groups = country[bucket].group
      groups[#groups + 1] = entry
    end
  end
  return mission
end

function miz.exportBytes(mizBytes, world)
  local entries, err = readZip(mizBytes)
  if not entries then return nil, err end
  local missionText, missionErr
  local out = {}
  for _, entry in ipairs(entries) do
    if entry.name == "mission" then
      missionText, missionErr = miz.entryText(entry)
    else
      out[#out + 1] = entry
    end
  end
  if not missionText then return nil, missionErr or "mission entry not found" end
  local mission, loadErr = miz.loadMission(missionText)
  if not mission then return nil, loadErr end
  miz.patch(mission, world)
  local encoded = "mission = " .. serialize(mission) .. "\n"
  table.insert(out, 1, storedRecord("mission", encoded))
  return writeZip(out)
end

function miz.exportFile(missionPath, worldPath, destPath)
  local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end
  local mizBytes = read(missionPath)
  if not mizBytes then return nil, "cannot read " .. tostring(missionPath) end
  local worldText = read(worldPath)
  if not worldText then return nil, "cannot read " .. tostring(worldPath) end
  local fn, err = loadstring("return " .. worldText)
  if not fn then return nil, err end
  if setfenv then setfenv(fn, {}) end
  local ok, world = pcall(fn)
  if not ok or type(world) ~= "table" then return nil, "world save unreadable" end
  local bytes, exportErr = miz.exportBytes(mizBytes, world)
  if not bytes then return nil, exportErr end
  local tmp = destPath .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then return nil, "cannot write " .. tmp end
  f:write(bytes)
  f:close()
  os.remove(destPath)
  if os.rename(tmp, destPath) == nil then return nil, "cannot replace " .. destPath end
  return true
end

if RH then RH.miz = miz end
return miz
