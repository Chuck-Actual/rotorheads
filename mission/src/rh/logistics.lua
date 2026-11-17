RH = RH or {}

local util = RH.util

-- FARPs, Logistics Centers (LCs), MASHes, blue outposts and blue zones.
-- FARPs hold a limited stock of generic crates. LCs (a FARP within 1 NM of an airfield) and ships have unlimited crates.
local logistics = {}
RH.logistics = logistics

local function fcfg() return RH.config.farp end
local function mcfg() return RH.config.mash end

-- FARPs ------------------------------------------------------------------------

function logistics.farps()
  local list = {}
  for _, name in ipairs(util.keys(RH.state.farps)) do table.insert(list, RH.state.farps[name]) end
  return list
end

function logistics.register(name, point, opts)
  opts = opts or {}
  local existing = RH.state.farps[name]
  if existing then return existing end
  local farp = {
    name = name,
    x = point.x,
    y = point.y,
    lc = opts.lc or false,
    built = opts.built or false,
    airbase = opts.airbase,
    crates = opts.lc and -1 or (opts.crates or fcfg().startingCrates),
  }
  RH.state.farps[name] = farp
  return farp
end

function logistics.discoverPlaced()
  local prefix = RH.config.prefixes.farp
  for _, zone in ipairs(RH.dcs.zonesWithPrefix(prefix)) do
    local airbase = logistics.airfieldNear(zone.point, fcfg().lcAirfieldRadius)
    logistics.register(zone.name, zone.point, { lc = airbase ~= nil, airbase = airbase and airbase.name })
  end
end

function logistics.airfieldNear(point, radius)
  local best, bestDist
  for _, ab in ipairs(RH.dcs.airbases()) do
    if ab.kind == "airdrome" then
      local d = util.distance(ab.point, point)
      if d <= radius and (not bestDist or d < bestDist) then best, bestDist = ab, d end
    end
  end
  return best
end

function logistics.farpAt(point, radius)
  radius = radius or fcfg().zoneRadius
  local best, bestDist
  for _, farp in pairs(RH.state.farps) do
    local d = util.distance(farp, point)
    if d <= radius and (not bestDist or d < bestDist) then best, bestDist = farp, d end
  end
  return best
end

function logistics.hasUnlimitedCrates(farp)
  return farp.lc or farp.crates == -1
end

function logistics.takeCrates(farp, n)
  if logistics.hasUnlimitedCrates(farp) then return true end
  if farp.crates < n then return false end
  farp.crates = farp.crates - n
  return true
end

function logistics.returnCrates(farp, n)
  if logistics.hasUnlimitedCrates(farp) then return 0 end
  local space = fcfg().maxCrates - farp.crates
  local added = math.max(0, math.min(space, n))
  farp.crates = farp.crates + added
  return added
end

-- Construction rules from the wiki:
--  * an LC is a FARP built within 1 NM of an airfield reference point, at most one per airfield;
--  * FARPs must be 15 NM from any FARP and 5 NM from any LC;
--  * FARPs must not be within 15 NM of an airfield that has no LC (it would block that LC forever);
--  * nothing can be built within 300 m of an existing FARP.
function logistics.validateFarpSite(point)
  local airfield = logistics.airfieldNear(point, fcfg().lcAirfieldRadius)
  for _, farp in pairs(RH.state.farps) do
    local d = util.distance(farp, point)
    if d < fcfg().noBuildRadiusFromFarp then
      return false, "too close to " .. farp.name
    end
  end

  if airfield then
    if airfield.coalition == "red" then return false, airfield.name .. " is still held by REDFOR" end
    for _, farp in pairs(RH.state.farps) do
      if farp.lc and farp.airbase == airfield.name then
        return false, airfield.name .. " already has a Logistics Center"
      end
    end
    return true, "lc", airfield
  end

  for _, farp in pairs(RH.state.farps) do
    local d = util.distance(farp, point)
    if farp.lc and d < fcfg().minDistanceLC then
      return false, string.format("%.1f NM from Logistics Center %s (needs 5 NM)", d / util.NM, farp.name)
    end
    if not farp.lc and d < fcfg().minDistanceFarp then
      return false, string.format("%.1f NM from FARP %s (needs 15 NM)", d / util.NM, farp.name)
    end
  end

  for _, ab in ipairs(RH.dcs.airbases()) do
    if ab.kind == "airdrome" and util.distance(ab.point, point) < fcfg().minDistanceFarp then
      local hasLC = false
      for _, farp in pairs(RH.state.farps) do
        if farp.lc and farp.airbase == ab.name then hasLC = true end
      end
      if not hasLC then
        return false, "within 15 NM of " .. ab.name .. ", which has no Logistics Center yet"
      end
    end
  end
  return true, "farp"
end

function logistics.nextFarpName(kind, airfield)
  if kind == "lc" then return "LC " .. airfield.name end
  local n = 1
  for _, farp in pairs(RH.state.farps) do if farp.built and not farp.lc then n = n + 1 end end
  return string.format("FARP %02d", n)
end

-- Builds a FARP/LC at a validated point. Returns the FARP record or nil, reason.
function logistics.buildFarp(point, builtBy)
  local ok, kind, airfield = logistics.validateFarpSite(point)
  if not ok then return nil, kind end
  local name = logistics.nextFarpName(kind, airfield)
  local farp = logistics.register(name, point, { lc = kind == "lc", built = true, airbase = airfield and airfield.name, crates = 0 })
  RH.dcs.spawnFarp(farp)
  RH.dcs.message("blue", string.format("%s built %s. It will need crates and fuel delivered.", builtBy or "A pilot", name), 20)
  RH.dcs.notify("farp_built", { farp = name, kind = kind })
  if RH.ctld and RH.ctld.addFarpZone then RH.ctld.addFarpZone(farp) end
  return farp
end

function logistics.showFarpCircles()
  local ids = {}
  for _, farp in pairs(RH.state.farps) do
    local id = "farp?-" .. farp.name
    local radius = farp.lc and fcfg().minDistanceLC or fcfg().minDistanceFarp
    RH.dcs.drawCircle(id, "blue", farp, radius, { 0, 0.4, 1, 1 }, { 0, 0.4, 1, 0.12 }, farp.name)
    table.insert(ids, id)
  end
  RH.after(fcfg().displayCirclesFor, function()
    for _, id in ipairs(ids) do RH.dcs.removeDrawing(id) end
  end)
  return #ids
end

-- Blue zones ------------------------------------------------------------------

function logistics.blueZones()
  local zones = {}
  for _, z in ipairs(RH.dcs.zonesWithPrefix(RH.config.prefixes.blueZone)) do
    table.insert(zones, { name = z.name, point = z.point, radius = z.radius })
  end
  if RH.outposts then
    for _, o in ipairs(RH.outposts.list) do
      if RH.outposts.status(o) == "captured" then
        table.insert(zones, { name = o.name, point = o.point, radius = RH.config.outpost.contestedRadius * 2 })
      end
    end
  end
  for name, bo in pairs(RH.state.blueOutposts) do
    table.insert(zones, { name = name, point = { x = bo.x, y = bo.y }, radius = bo.radius })
  end
  return zones
end

function logistics.inBlueZone(point)
  for _, z in ipairs(logistics.blueZones()) do
    if util.distance(z.point, point) <= z.radius then return true end
  end
  return false
end

function logistics.buildBlueOutpost(point, builtBy)
  local n = util.count(RH.state.blueOutposts) + 1
  local name = string.format("Blue Outpost %02d", n)
  RH.state.blueOutposts[name] = { x = point.x, y = point.y, radius = 5000 }
  RH.dcs.drawCircle("blueoutpost-" .. name, "blue", point, 5000, { 0, 0.4, 1, 1 }, { 0, 0.4, 1, 0.08 }, name)
  RH.dcs.message("blue", string.format("%s established %s. The blue zone has grown.", builtBy or "A pilot", name), 15)
  return name
end

-- MASH ------------------------------------------------------------------------

function logistics.validateMashSite(point)
  if not logistics.inBlueZone(point) then return false, "a MASH must be inside a blue zone" end
  for name, m in pairs(RH.state.mashes) do
    local d = util.distance(m, point)
    if d < mcfg().minSeparation then
      return false, string.format("%.1f km from %s (needs 16 km)", d / 1000, name)
    end
  end
  return true
end

function logistics.registerMash(name, point)
  local existing = RH.state.mashes[name]
  if existing then
    -- The mission-editor zone wins over a saved position, so moving the zone moves the tent.
    existing.x, existing.y = point.x, point.y
    return existing
  end
  RH.state.mashes[name] = { x = point.x, y = point.y, patients = 0 }
  return RH.state.mashes[name]
end

function logistics.buildMash(point, builtBy)
  local ok, reason = logistics.validateMashSite(point)
  if not ok then return nil, reason end
  local name = string.format("MASH %02d", util.count(RH.state.mashes) + 1)
  logistics.registerMash(name, point)
  RH.dcs.spawnMash(name, point)
  RH.dcs.message("blue", string.format("%s built %s.", builtBy or "A pilot", name), 15)
  return name
end

function logistics.mashAt(point, radius)
  for name, m in pairs(RH.state.mashes) do
    if util.distance(m, point) <= (radius or 500) then return name, m end
  end
end

-- Adds patients to a MASH up to capacity. Returns how many were admitted.
function logistics.admitPatients(mashName, count)
  local m = RH.state.mashes[mashName]
  if not m then return 0 end
  local admitted = math.max(0, math.min(count, mcfg().capacity - m.patients))
  m.patients = m.patients + admitted
  return admitted
end

function logistics.mashFull(mashName)
  local m = RH.state.mashes[mashName]
  if not m or mcfg().capacity >= 9999 then return false end
  return m.patients >= mcfg().capacity
end

function logistics.mashStatus()
  local lines = {}
  local unlimited = mcfg().capacity >= 9999
  for _, name in ipairs(util.keys(RH.state.mashes)) do
    local m = RH.state.mashes[name]
    if unlimited then
      table.insert(lines, string.format("%s: %d patients (unlimited)", name, m.patients))
    else
      table.insert(lines, string.format("%s: %d/%d patients", name, m.patients, mcfg().capacity))
    end
  end
  if #lines == 0 then return "No MASH has been built yet." end
  return table.concat(lines, "\n")
end

-- Transport task: load patients from a MASH and fly them to an airfield to free capacity.
logistics.transports = {}

function logistics.startTransport(unitName, mashName, capacity)
  local m = RH.state.mashes[mashName]
  if not m or m.patients == 0 then return 0 end
  local onboard = logistics.transports[unitName] or 0
  local take = math.min(m.patients, capacity - onboard)
  if take <= 0 then return 0 end
  m.patients = m.patients - take
  logistics.transports[unitName] = onboard + take
  return take
end

function logistics.completeTransport(unitName)
  local n = logistics.transports[unitName] or 0
  logistics.transports[unitName] = nil
  return n
end

function logistics.start()
  logistics.discoverPlaced()
  for _, z in ipairs(RH.dcs.zonesWithPrefix(RH.config.prefixes.mash)) do
    logistics.registerMash(z.name, z.point)
  end
  for name, m in pairs(RH.state.mashes) do
    RH.dcs.spawnMash(name, m)
  end
  for _, farp in pairs(RH.state.farps) do
    if farp.built then RH.dcs.spawnFarp(farp) end
  end
  for name, bo in pairs(RH.state.blueOutposts) do
    RH.dcs.drawCircle("blueoutpost-" .. name, "blue", bo, bo.radius, { 0, 0.4, 1, 1 }, { 0, 0.4, 1, 0.08 }, name)
  end
end

return logistics
