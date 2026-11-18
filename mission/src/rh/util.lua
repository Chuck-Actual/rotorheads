RH = RH or {}

local util = {}
RH.util = util

util.NM = 1852

function util.log(fmt, ...)
  local msg = "[RH] " .. string.format(fmt, ...)
  if env and env.info then
    env.info(msg)
  else
    print(msg)
  end
end

-- Accepts either Vec2 {x, y} or Vec3 {x, y, z}; a Vec3 is projected to the ground plane.
function util.toVec2(p)
  if p.z ~= nil then
    return { x = p.x, y = p.z }
  end
  return { x = p.x, y = p.y }
end

-- YE72 is the 100 km square plus the first easting digit and the first northing digit.
function util.mgrsSquare(mgrs)
  if type(mgrs) ~= "table" or type(mgrs.MGRSDigraph) ~= "string" or mgrs.MGRSDigraph == "" then return nil end
  local function digit(value)
    if type(value) == "number" then
      local meters = math.floor(value)
      if meters < 0 then meters = 0 end
      if meters >= 100000 then meters = meters % 100000 end
      return string.sub(string.format("%05d", meters), 1, 1)
    end
    local text = tostring(value or "")
    if text == "" then return nil end
    return string.sub(text, 1, 1)
  end
  local east, north = digit(mgrs.Easting), digit(mgrs.Northing)
  if not east or not north then return nil end
  return mgrs.MGRSDigraph .. east .. north
end

function util.distance(a, b)
  local p, q = util.toVec2(a), util.toVec2(b)
  local dx, dy = p.x - q.x, p.y - q.y
  return math.sqrt(dx * dx + dy * dy)
end

function util.offset(p, bearingRad, meters)
  local v = util.toVec2(p)
  return { x = v.x + math.cos(bearingRad) * meters, y = v.y + math.sin(bearingRad) * meters }
end

function util.randomPointInCircle(center, radius, rnd)
  rnd = rnd or math.random
  local r = radius * math.sqrt(rnd())
  local a = rnd() * 2 * math.pi
  return util.offset(center, a, r)
end

function util.startsWith(s, prefix)
  return type(s) == "string" and s:sub(1, #prefix) == prefix
end

function util.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

function util.count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function util.contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

function util.shallowCopy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function util.formatDuration(seconds)
  seconds = math.max(0, math.floor(seconds))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  if h > 0 then
    return string.format("%dh %02dm", h, m)
  end
  return string.format("%dm %02ds", m, seconds % 60)
end

-- Lua-literal serializer used for save files. Output can be read back with loadstring("return " .. s).
function util.serialize(value, indent)
  indent = indent or ""
  local t = type(value)
  if t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then return "0" end
    if value == math.floor(value) and math.abs(value) < 1e15 then
      return string.format("%d", value)
    end
    return string.format("%.6f", value)
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "string" then
    return string.format("%q", value)
  elseif t == "table" then
    local nextIndent = indent .. "  "
    local parts = {}
    local n = #value
    for i = 1, n do
      parts[#parts + 1] = nextIndent .. util.serialize(value[i], nextIndent)
    end
    for _, k in ipairs(util.keys(value)) do
      local isArrayKey = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
      if not isArrayKey then
        local key
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          key = k
        else
          key = "[" .. util.serialize(k) .. "]"
        end
        parts[#parts + 1] = nextIndent .. key .. " = " .. util.serialize(value[k], nextIndent)
      end
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return "nil"
end

function util.deserialize(s)
  if not s or s == "" then return nil end
  local chunk, err = loadstring("return " .. s)
  if not chunk then return nil, err end
  if setfenv then setfenv(chunk, {}) end
  local ok, result = pcall(chunk)
  if not ok then return nil, result end
  return result
end

local function jsonEscape(s)
  return (s:gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
    return map[c] or string.format("\\u%04x", c:byte())
  end))
end

local function isArray(t)
  local n = #t
  if n == 0 then return next(t) == nil end
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then return false end
  end
  return true
end

-- Minimal JSON encoder for the live map export. Empty tables encode as [].
function util.toJSON(value)
  local t = type(value)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(value) end
  if t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then return "null" end
    if value == math.floor(value) and math.abs(value) < 1e15 then return string.format("%d", value) end
    return string.format("%.6f", value)
  end
  if t == "string" then return '"' .. jsonEscape(value) .. '"' end
  if t == "table" then
    local parts = {}
    if isArray(value) then
      for i = 1, #value do parts[i] = util.toJSON(value[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for _, k in ipairs(util.keys(value)) do
      parts[#parts + 1] = '"' .. jsonEscape(tostring(k)) .. '":' .. util.toJSON(value[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

return util
