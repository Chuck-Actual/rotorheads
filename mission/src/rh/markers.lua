RH = RH or {}

local util = RH.util

-- F10 map marker commands:
--   -illumination        illumination flares over the mark for several minutes
--   -smoke,<color>       smoke at the mark (green, red, orange, blue, white); you must be within 15 km
--   -wpzone              deployed troops nearby walk to this mark instead of charging the enemy
--   -farp?               shows the 1 mile no-build circle around every FARP and Logistics Center
--   -extract             downed pilots within 4 km (up to 4) walk to this mark for pickup
local markers = { wpzones = {}, lastFarpQuery = -math.huge }
RH.markers = markers

local function cfg() return RH.config.markers end

function markers.parse(text)
  if type(text) ~= "string" then return nil end
  local t = util.trim(text):lower()
  if t:sub(1, 1) ~= "-" then return nil end
  if t == "-illumination" or t == "-illum" then return { cmd = "illumination" } end
  if t == "-wpzone" then return { cmd = "wpzone" } end
  if t == "-farp?" then return { cmd = "farp?" } end
  if t == "-extract" or t == "-extraction" then return { cmd = "extract" } end
  local color = t:match("^%-smoke%s*,%s*(%a+)$")
  if color then
    if cfg().smokeColors[color] then return { cmd = "smoke", color = color } end
    return { cmd = "invalid", reason = "unknown smoke color '" .. color .. "'. Use green, red, orange, blue or white." }
  end
  return nil
end

function markers.illuminate(point)
  local burst = 0
  local function drop()
    burst = burst + 1
    local p = util.randomPointInCircle(point, 300)
    RH.dcs.illumination(p, cfg().illuminationAltitude)
    if burst < cfg().illuminationBursts then RH.after(cfg().illuminationSpacing, drop) end
  end
  drop()
end

function markers.handle(e)
  local command = markers.parse(e.text)
  if not command then return end
  local point = util.toVec2(e.pos)
  local reply = function(msg)
    if e.initiatorName then RH.dcs.messageToUnit(e.initiatorName, msg, 10) else RH.dcs.message("blue", msg, 10) end
  end

  if command.cmd == "invalid" then
    reply(command.reason)
  elseif command.cmd == "illumination" then
    markers.illuminate(point)
    reply("Illumination rounds inbound on your mark.")
  elseif command.cmd == "smoke" then
    if e.initiatorPos and util.distance(e.initiatorPos, point) > cfg().smokeRange then
      reply("Smoke request denied: you must be within 15 km of the mark.")
      return
    end
    RH.dcs.smoke(point, cfg().smokeColors[command.color])
    reply(command.color:gsub("^%l", string.upper) .. " smoke deployed.")
  elseif command.cmd == "wpzone" then
    markers.wpzones[e.markId or (#markers.wpzones + 1)] = { point = point, coalition = e.coalition }
    reply("Waypoint zone set. Troops deployed within 1 NM will move here.")
  elseif command.cmd == "farp?" then
    local now = RH.dcs.now()
    if now - markers.lastFarpQuery < 60 then
      reply("FARP circles are already displayed.")
      return
    end
    markers.lastFarpQuery = now
    local n = RH.logistics.showFarpCircles()
    reply(string.format("Showing no-build circles around %d FARPs / LCs for 60 seconds.", n))
  elseif command.cmd == "extract" then
    local moved = RH.csar and RH.csar.movePilotsTo(point, cfg().extractRange, cfg().extractMaxPilots) or 0
    reply(string.format("%d downed pilot(s) are moving to the extraction point.", moved))
  end
end

function markers.onRemoved(e)
  if e.markId then markers.wpzones[e.markId] = nil end
end

function markers.wpzoneFor(point)
  local best, bestDist
  for _, wp in pairs(markers.wpzones) do
    local d = util.distance(wp.point, point)
    if d <= cfg().wpzoneRange and (not bestDist or d < bestDist) then best, bestDist = wp, d end
  end
  return best and best.point or nil
end

function markers.start()
  RH.events.on("markAdded", markers.handle)
  RH.events.on("markChanged", markers.handle)
  RH.events.on("markRemoved", markers.onRemoved)
end

return markers
