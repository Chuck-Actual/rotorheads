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
  if existing then
    -- The mission-editor zone wins over a saved position, so moving the zone moves the FARP.
    existing.x, existing.y = point.x, point.y
    if opts.zoneRadius then existing.zoneRadius = opts.zoneRadius end
    if opts.editor then existing.editor = true end
    if opts.label then existing.label = opts.label end
    return existing
  end
  local farp = {
    name = name,
    x = point.x,
    y = point.y,
    lc = opts.lc or false,
    built = opts.built or false,
    editor = opts.editor or false,
    label = opts.label,
    airbase = opts.airbase,
    zoneRadius = opts.zoneRadius,
    pending = opts.pending or false,
    crates = opts.crates or (opts.lc and -1 or fcfg().startingCrates),
    liquids = opts.liquids,
    ammoItems = opts.ammoItems,
  }
  RH.state.farps[name] = farp
  return farp
end

function logistics.discoverPlaced()
  local prefix = RH.config.prefixes.farp
  for _, zone in ipairs(RH.dcs.zonesWithPrefix(prefix)) do
    local airbase = logistics.airfieldNear(zone.point, fcfg().lcAirfieldRadius)
    logistics.register(zone.name, zone.point, {
      lc = airbase ~= nil and airbase.coalition ~= "red",
      airbase = airbase and airbase.name,
      zoneRadius = zone.radius,
    })
  end
  logistics.refreshPlacedCenters()
end

local PLACEHOLDER_NAMES = {
  ALPHA = true, BRAVO = true, CHARLIE = true, DELTA = true,
  ECHO = true, FOXTROT = true, GOLF = true, HOTEL = true,
}

function logistics.labelIsPlaceholder(label)
  if type(label) ~= "string" or label == "" then return true end
  local rest = label:gsub("^FARP ", "")
  if PLACEHOLDER_NAMES[rest] then return true end
  if string.match(rest, "^%d+$") then return true end
  return false
end

function logistics.farpNameInUse(label, except)
  for _, farp in pairs(RH.state.farps) do
    if farp ~= except and (farp.label == label or farp.name == label) then return true end
  end
  return false
end

-- One unused name from the bank. Decommissioning the FARP drops the record, which frees the name.
function logistics.pickFarpName(except)
  local free = {}
  for _, name in ipairs(fcfg().names or {}) do
    local label = "FARP " .. name
    if not logistics.farpNameInUse(label, except) then free[#free + 1] = label end
  end
  if #free == 0 then return nil end
  return free[math.random(#free)]
end

function logistics.isBankName(label)
  if type(label) ~= "string" then return false end
  for _, name in ipairs(fcfg().names or {}) do
    if label == "FARP " .. name then return true end
  end
  return false
end

-- Existing FARPs in the save get a bank name too. A logistics center keeps its own name.
function logistics.assignFarpNames()
  for _, farp in pairs(RH.state.farps) do
    farp.loadZoneReady = nil
    if not farp.lc and not logistics.isBankName(farp.label) then
      local picked = logistics.pickFarpName(farp)
      if picked then farp.label = picked end
    end
  end
end

function logistics.editorPads()
  local pads = {}
  if not RH.dcs.staticObjects then return pads end
  for _, static in ipairs(RH.dcs.staticObjects()) do
    local kind = static.typeName or ""
    if (kind == "FARP" or kind == "Invisible FARP" or kind == "SINGLE_HELIPAD") and static.side ~= "red" then
      table.insert(pads, static)
    end
  end
  table.sort(pads, function(a, b) return (a.name or "") < (b.name or "") end)
  return pads
end

function logistics.isTent(static)
  local name = string.lower(static.name or "")
  local kind = string.lower((static.typeName or "") .. " " .. (static.display or ""))
  if string.find(kind, "tent04", 1, true) or string.find(kind, "m92", 1, true) then return false end
  if string.find(name, "mash", 1, true) then return false end
  if string.find(kind, "farp tent", 1, true) or string.find(kind, "palatka", 1, true) then return true end
  if string.sub(name, -5) == " tent" then return true end
  return false
end

function logistics.nearestTent(point, radius)
  local best, bestDist
  if not RH.dcs.staticObjects then return nil end
  for _, static in ipairs(RH.dcs.staticObjects()) do
    if logistics.isTent(static) then
      local d = util.distance(static, point)
      if d <= radius and (not bestDist or d < bestDist) then best, bestDist = static, d end
    end
  end
  return best
end

local function registerEditorSite(name, point, index)
  if not name or name == "" then return nil end
  local existing = logistics.farpAt(point, 200)
  if existing then
    if existing.editor and not existing.lc and logistics.labelIsPlaceholder(existing.label) then
      existing.label = logistics.pickFarpName(existing) or existing.label
    end
    return nil
  end
  local airfield = logistics.airfieldNear(point, fcfg().lcAirfieldRadius)
  local lc = airfield ~= nil and airfield.coalition ~= "red"
  return logistics.register(name, point, {
    editor = true,
    label = lc and nil or logistics.pickFarpName(),
    lc = lc,
    airbase = airfield and airfield.name,
    crates = lc and -1 or nil,
  })
end

-- A pad or tent with no RH_FARP_ zone still holds crate stock. It is already in the mission, so it is not rebuilt.
function logistics.discoverEditorPads()
  for i, pad in ipairs(logistics.editorPads()) do
    registerEditorSite(pad.name, pad, i)
  end
  if not RH.dcs.staticObjects then return end
  local tents = {}
  for _, static in ipairs(RH.dcs.staticObjects()) do
    if logistics.isTent(static) then tents[#tents + 1] = static end
  end
  table.sort(tents, function(a, b) return (a.name or "") < (b.name or "") end)
  for _, tent in ipairs(tents) do
    if not logistics.pieceOfKnownFarp(tent.name) then
      local index = 0
      for _ in pairs(RH.state.farps) do index = index + 1 end
      local name = tent.name ~= "" and tent.name or "FARP"
      registerEditorSite(name, tent, index + 1)
    end
  end
end

-- "FARP Pinto Tent" belongs to FARP Pinto even after the pad is moved away from it in the editor.
function logistics.pieceOfKnownFarp(name)
  if type(name) ~= "string" then return false end
  for farpName, farp in pairs(RH.state.farps) do
    if not farp.editor and name ~= farpName and logistics.pieceNames(farpName)[name] then return true end
  end
  return false
end

-- East of the tent, between the tent and the pad. Bearing 90 is east in this map.
function logistics.humveePoint(farp)
  local tent = logistics.nearestTent(farp, 400)
  if tent then return util.offset(tent, math.rad(90), 25) end
  return util.offset(farp, math.rad(270), 45)
end

function logistics.isServiceHumvee(unit)
  local name = unit.name or ""
  if string.find(name, "RH_TPL_", 1, true) or string.find(name, "#", 1, true) then return false end
  local kind = unit.typeName or ""
  if kind == "Hummer" or kind == "M1025 HMMWV" then return true end
  return string.sub(name, -7) == " Humvee"
end

-- One service Humvee per FARP. The keeper is the one already sitting just east of the tent.
function logistics.oneHumvee(farp)
  if not farp or farp.lc or farp.pending then return end
  local point = logistics.humveePoint(farp)
  local named = (farp.name or "FARP") .. " Humvee"
  local keep
  if RH.dcs.groundUnitsInRadius then
    local bestDist
    for _, unit in ipairs(RH.dcs.groundUnitsInRadius("blue", farp, 150) or {}) do
      local pos = unit.pos or unit
      if logistics.isServiceHumvee(unit) and util.distance(pos, point) <= 120 then
        local d = util.distance(pos, point)
        local nearer = not bestDist or d < bestDist - 0.5
        local sameSpot = bestDist and math.abs(d - bestDist) <= 0.5 and unit.name == named
        if nearer or sameSpot then keep, bestDist = unit.name, d end
      end
    end
    for _, unit in ipairs(RH.dcs.groundUnitsInRadius("blue", farp, 150) or {}) do
      local pos = unit.pos or unit
      if unit.name ~= keep and logistics.isServiceHumvee(unit) and util.distance(pos, point) <= 120 then
        if RH.dcs.destroyNamed then RH.dcs.destroyNamed(unit.name) end
        if RH.dcs.destroyUnit then RH.dcs.destroyUnit(unit.name) end
      end
    end
  end
  if not keep and RH.dcs.objectExists and RH.dcs.spawnVehicle and not RH.dcs.objectExists(named) then
    RH.dcs.spawnVehicle(named, "Hummer", point, 90)
  end
end

function logistics.trimHumvees()
  for _, farp in pairs(RH.state.farps or {}) do
    logistics.oneHumvee(farp)
  end
end

-- The editor FARP already has the tent and the pad. It still needs the Humvee the rearm window uses.
function logistics.equipEditorFarps()
  for _, farp in pairs(RH.state.farps) do
    if farp.editor and not farp.lc and not farp.pending then
      logistics.oneHumvee(farp)
      if RH.dcs.airbases and RH.dcs.writePadStock then
        local pad, padDist
        for _, ab in ipairs(RH.dcs.airbases()) do
          if ab.kind == "helipad" and ab.coalition ~= "red" then
            local d = util.distance(ab.point, farp)
            if d <= 400 and (not padDist or d < padDist) then pad, padDist = ab, d end
          end
        end
        if pad then logistics.writeLimitedStock(pad.name) end
      end
      for _, site in ipairs(logistics.editorPads()) do
        if util.distance(site, farp) <= 400 then logistics.writeLimitedStock(site.name) end
      end
    end
  end
end

-- A mission-editor logistics tent on an airfield is that airfield's Logistics Center.
-- Player-built FARPs are left alone. An existing save is promoted when the tent is close enough.
function logistics.refreshPlacedCenters()
  local radius = fcfg().placedLcRadius or fcfg().lcAirfieldRadius
  for _, farp in pairs(RH.state.farps) do
    if not farp.built and not farp.pending and not farp.editor then
      local points = { { x = farp.x, y = farp.y } }
      for _, lp in ipairs(farp.loadPoints or {}) do table.insert(points, lp) end
      for _, p in ipairs(points) do
        local ab = logistics.airfieldNear(p, radius)
        if ab and ab.coalition ~= "red" then
          farp.lc = true
          farp.airbase = ab.name
          farp.crates = -1
          break
        end
      end
    end
  end
end

function logistics.airfieldNear(point, radius)
  local best, bestDist
  for _, ab in ipairs(RH.dcs.airbases()) do
    if ab.kind == "airdrome" and ab.logistics ~= false then
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
    local covered = d <= radius
    if not covered then
      for _, lp in ipairs(farp.loadPoints or {}) do
        if util.distance(lp, point) <= fcfg().loadRadius then covered = true break end
      end
    end
    if covered and (not bestDist or d < bestDist) then best, bestDist = farp, d end
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
  logistics.refreshMapLabels()
  return true
end

function logistics.isGeneralSupply(name)
  return type(name) == "string" and name:sub(1, #"General supply") == "General supply"
end

-- A normal crate returned at a tent is worth 1. A general-supply crate is worth 5, per the wiki.
function logistics.crateWorth(name)
  if logistics.isGeneralSupply(name) then return fcfg().generalSupplyWorth or RH.config.kits.generalSupply.worth or 5 end
  return 1
end

function logistics.displayName(farp)
  if type(farp) == "table" and farp.label then return farp.label end
  local name = type(farp) == "table" and farp.name or farp or ""
  local prefix = RH.config.prefixes.farp
  if util.startsWith(name, prefix) then return "FARP " .. name:sub(#prefix + 1):gsub("_", " ") end
  return name
end

function logistics.labelPoint(farp)
  local anchor = farp
  if RH.dcs.staticObjects then
    for _, static in ipairs(RH.dcs.staticObjects()) do
      if static.name == farp.name then anchor = static break end
    end
  end
  if anchor == farp then anchor = logistics.nearestTent(farp, 400) or farp end
  return util.offset(anchor, math.pi / 2, 25)
end

function logistics.mapLabelText(farp)
  local name = logistics.displayName(farp)
  if farp.pending then return name .. "\nbuilds on next restart" end
  local crates = logistics.hasUnlimitedCrates(farp) and "unlimited" or tostring(farp.crates or 0)
  return string.format("%s\nCrates: %s", name, crates)
end

function logistics.refreshMapLabels()
  if not RH.dcs.drawLabel then return end
  for _, farp in ipairs(logistics.farps()) do
    farp.stockMark = nil
    if farp.x and farp.y then
      local ok, err = pcall(RH.dcs.drawLabel, "farp-stock-" .. farp.name, "blue", logistics.labelPoint(farp), logistics.mapLabelText(farp), 18)
      if not ok then util.log("FARP label %s failed: %s", tostring(farp.name), tostring(err)) end
    end
  end
end

function logistics.returnCrates(farp, n)
  if logistics.hasUnlimitedCrates(farp) then return 0 end
  local space = fcfg().maxCrates - farp.crates
  local added = math.max(0, math.min(space, n))
  farp.crates = farp.crates + added
  logistics.refreshMapLabels()
  return added
end

local function airfieldHasLC(airfieldName)
  for _, farp in pairs(RH.state.farps) do
    if farp.lc and farp.airbase == airfieldName then return true end
  end
  return false
end

-- Construction, testing rules:
--  * the first site within 1 NM of a real friendly airfield becomes that airfield's Logistics Center;
--  * helicopter pads such as HS02 are not airfields and cannot be a Logistics Center;
--  * every other site must be at least 1 mile from every FARP and every Logistics Center;
--  * a site within 1 NM of a real airfield that still has no Logistics Center is refused.
function logistics.validateFarpSite(point)
  local airfield = logistics.airfieldNear(point, fcfg().lcAirfieldRadius)
  if airfield and airfield.coalition == "red" then
    return false, airfield.name .. " is still held by REDFOR"
  end
  if airfield and not airfieldHasLC(airfield.name) then
    return true, "lc", airfield
  end

  local mile = fcfg().minSeparation
  for _, farp in pairs(RH.state.farps) do
    local d = util.distance(farp, point)
    if d < mile then
      local what = farp.lc and "Logistics Center" or "FARP"
      return false, string.format("%.2f miles from %s %s (needs 1 mile)", d / mile, what, farp.name)
    end
  end

  for _, ab in ipairs(RH.dcs.airbases()) do
    if ab.kind == "airdrome" and ab.logistics ~= false and util.distance(ab.point, point) < fcfg().minDistanceFarp and not airfieldHasLC(ab.name) then
      return false, "within 1 NM of " .. ab.name .. ", which has no Logistics Center yet"
    end
  end
  return true, "farp"
end

function logistics.nextFarpName(kind, airfield)
  if kind == "lc" then return "LC " .. airfield.name end
  local picked = logistics.pickFarpName()
  if picked then return picked end
  local n = 1
  while logistics.farpNameInUse("FARP " .. n) do n = n + 1 end
  return "FARP " .. n
end

-- Marks the site. DCS cannot stand up a working FARP in the running mission, so it appears on the next restart.
function logistics.buildFarp(point, builtBy)
  local ok, kind, airfield = logistics.validateFarpSite(point)
  if not ok then return nil, kind end
  local name = logistics.nextFarpName(kind, airfield)
  local farp = logistics.register(name, point, {
    lc = kind == "lc",
    built = false,
    pending = true,
    airbase = airfield and airfield.name,
    crates = kind == "lc" and -1 or 0,
    label = kind == "lc" and nil or name,
  })
  RH.dcs.drawCircle("pending-" .. name, "blue", farp, 600, { 0, 0.7, 1, 1 }, { 0, 0.7, 1, 0.15 }, name .. " (next restart)")
  RH.dcs.smoke(farp, RH.config.markers.smokeColors.green)
  if RH.persistence and RH.persistence.save then RH.persistence.save() end
  RH.dcs.message("blue", string.format(
    "%s marked %s and saved it. It is written into the next campaign file as a real FARP: pad, tent, Humvee, fuel depot, and ammo dump. It is up after the next restart.",
    builtBy or "A pilot", name), 30)
  RH.dcs.notify("farp_marked", { farp = name, kind = kind })
  return farp
end

-- Spawn every FARP that was marked on an earlier run. Fuel and ammo come from the save, which is empty the first time.
function logistics.farpNear(point, radius)
  local best, bestDist
  for _, farp in pairs(RH.state.farps) do
    if (farp.pending or farp.built) and not farp.lc then
      local d = util.distance(farp, point)
      if d <= radius and (not bestDist or d < bestDist) then best, bestDist = farp, d end
    end
  end
  return best
end

function logistics.pieceNames(farpName)
  local names = { [farpName] = true }
  for _, piece in ipairs(fcfg().services or {}) do
    names[farpName .. " " .. piece.label] = true
  end
  return names
end

-- A pad or tent already in the mission, ignoring pieces this farp would spawn itself.
function logistics.editorSiteAt(point, ignoreNames, radius)
  radius = radius or 400
  ignoreNames = ignoreNames or {}
  if not RH.dcs.staticObjects then return nil end
  for _, static in ipairs(RH.dcs.staticObjects()) do
    if not ignoreNames[static.name or ""] then
      local kind = static.typeName or ""
      local display = string.lower(kind .. " " .. (static.display or ""))
      local pad = kind == "FARP" or kind == "Invisible FARP" or kind == "SINGLE_HELIPAD"
      local tent = string.find(display, "farp tent", 1, true) or string.find(display, "palatka", 1, true)
      if (pad or tent) and static.side ~= "red" and util.distance(static, point) <= radius then
        return static
      end
    end
  end
end

-- FARP 01 was marked on top of the editor FARP, then spawned again at the next start.
-- Drop that copy. The editor pad keeps the crate count.
function logistics.dropStackedFarps()
  local dropped = {}
  for name, farp in pairs(RH.state.farps) do
    if (farp.pending or farp.built) and not farp.lc and not farp.editor then
      if logistics.editorSiteAt(farp, logistics.pieceNames(name), 400) then
        dropped[#dropped + 1] = name
      end
    end
  end
  table.sort(dropped)
  for _, name in ipairs(dropped) do
    local pieces = logistics.pieceNames(name)
    RH.state.farps[name] = nil
    local saved = RH.state.world
    if saved and saved.objects then
      local kept = {}
      for _, obj in ipairs(saved.objects) do
        if not pieces[obj.name] then kept[#kept + 1] = obj end
      end
      saved.objects = kept
    end
    if RH.dcs.destroyNamed then
      for pieceName in pairs(pieces) do RH.dcs.destroyNamed(pieceName) end
    end
    if RH.dcs.removeDrawing then
      RH.dcs.removeDrawing("farp-stock-" .. name)
      RH.dcs.removeDrawing("pending-" .. name)
    end
  end
  if #dropped > 0 and RH.persistence and RH.persistence.save then RH.persistence.save() end
  return dropped
end

-- In a save copy every built FARP is already a pad in the file. One that is missing was deleted in the editor.
-- A marked FARP with no pad still spawns, so a crash before the next export does not lose it.
function logistics.dropDeletedFarps()
  if not (RH.world and RH.world.hostingSaveCopy) or not RH.dcs.objectExists then return {} end
  local removed = {}
  local where = {}
  for _, static in ipairs(RH.dcs.staticObjects and RH.dcs.staticObjects() or {}) do
    if static.name then where[static.name] = static end
  end
  for name, farp in pairs(RH.state.farps) do
    if farp.built and not farp.pending and not farp.editor then
      if not RH.dcs.objectExists(name) then
        removed[#removed + 1] = name
      elseif where[name] and where[name].x and where[name].y then
        -- A pad moved in the editor takes its load zone and map label with it.
        farp.x, farp.y = where[name].x, where[name].y
      end
    end
  end
  table.sort(removed)
  for _, name in ipairs(removed) do
    RH.state.farps[name] = nil
    if RH.state.padStock then RH.state.padStock[name] = nil end
    for pieceName in pairs(logistics.pieceNames(name)) do
      if pieceName ~= name and RH.dcs.destroyNamed then RH.dcs.destroyNamed(pieceName) end
    end
    if RH.dcs.removeDrawing then RH.dcs.removeDrawing("farp-stock-" .. name) end
    util.log("%s was removed in the Mission Editor, so it is no longer a FARP", name)
  end
  return removed
end

function logistics.spawnBuilt()
  logistics.sessionSpawned = {}
  local marked = {}
  for _, farp in pairs(RH.state.farps) do
    if farp.pending or farp.built then table.insert(marked, farp) end
  end
  if #marked == 0 then
    RH.dcs.message("blue", "No marked FARP in the save.", 20)
    return
  end
  for _, farp in ipairs(marked) do
    local ok, err = pcall(RH.dcs.spawnFarp, farp)
    if ok then
      logistics.sessionSpawned[farp.name] = true
      farp.pending = false
      farp.built = true
      RH.dcs.removeDrawing("pending-" .. farp.name)
      local stock = logistics.hasWarehouseStock(farp) and "Fuel and ammo restored from the save." or "No fuel or ammo yet."
      RH.dcs.message("blue", farp.name .. " is up. Dynamic spawn. " .. stock, 25)
    else
      util.log("spawn %s failed: %s", farp.name, tostring(err))
      RH.dcs.message("blue", string.format("%s is in the save but did not spawn: %s", farp.name, tostring(err)), 30)
    end
  end
end

function logistics.captureStocks()
  logistics.capturePads()
end

-- Fuel and air-to-ground missiles are the only warehouse counts that carry across a restart.
-- A logistics center is left on the mission's unlimited warehouse.
logistics.padHold = {}

function logistics.padIsLimited(name)
  local farp = RH.state.farps and RH.state.farps[name]
  if farp and farp.lc then return false end
  return true
end

function logistics.ensurePadStock(name)
  RH.state.padStock = RH.state.padStock or {}
  local saved = RH.state.padStock[name]
  if type(saved) == "table" and saved.granted and type(saved.fuelKg) == "number" and type(saved.missiles) == "table" then
    return saved, false
  end
  local farp = RH.state.farps and RH.state.farps[name]
  if farp and type(farp.liquids) == "table" then
    local fuel = farp.liquids[0] or farp.liquids["0"]
    if type(fuel) == "number" and fuel >= 0 and fuel < 1000000 then
      local stock = { fuelKg = fuel, missiles = farp.ammoItems or {}, granted = true }
      RH.state.padStock[name] = stock
      return stock, false
    end
  end
  local stock = { fuelKg = 0, missiles = {}, granted = true }
  RH.state.padStock[name] = stock
  return stock, true
end

function logistics.stockToWrite(name)
  local stock = logistics.ensurePadStock(name)
  local missiles = {}
  for item, amount in pairs(stock.missiles or {}) do missiles[item] = amount end
  if type(RH.state.warehouseWipe) == "table" then
    for item, amount in pairs(RH.state.warehouseWipe) do
      if missiles[item] == nil then missiles[item] = amount end
    end
  end
  return { fuelKg = stock.fuelKg, missiles = missiles }
end

-- One launch clears every saved FARP tank. Later deliveries stay, including across the next restart.
function logistics.clearCarriedStock()
  if RH.state.warehouseReset == 1 then return end
  local wipe = {
    ["weapons.missiles.AGM_114K"] = 0,
    ["weapons.missiles.AGM_114L"] = 0,
    ["weapons.missiles.Vikhr_M"] = 0,
  }
  for _, saved in pairs(RH.state.padStock or {}) do
    if type(saved) == "table" and type(saved.missiles) == "table" then
      for item in pairs(saved.missiles) do wipe[item] = 0 end
    end
  end
  for _, farp in pairs(RH.state.farps or {}) do
    if type(farp) == "table" and not farp.lc then
      if type(farp.ammoItems) == "table" then
        for item in pairs(farp.ammoItems) do wipe[item] = 0 end
      end
      farp.liquids = nil
      farp.ammoItems = nil
    end
  end
  RH.state.padStock = {}
  RH.state.warehouseWipe = wipe
  RH.state.warehouseReset = 1
end

function logistics.writeLimitedStock(name)
  if not logistics.padIsLimited(name) or not RH.dcs.writePadStock then return end
  local stock = logistics.stockToWrite(name)
  RH.dcs.writePadStock(name, stock)
  if RH.dcs.restockPad then RH.dcs.restockPad(name) end
  if logistics.padHold[name] == nil then logistics.padHold[name] = RH.dcs.now() + 25 end
end

function logistics.syncPads()
  if not RH.dcs.farpPads then return end
  for _, name in ipairs(RH.dcs.farpPads()) do
    logistics.writeLimitedStock(name)
  end
end

function logistics.storePadReading(name, live)
  live.missiles = live.missiles or {}
  live.granted = true
  RH.state.padStock = RH.state.padStock or {}
  RH.state.padStock[name] = live
  local farp = RH.state.farps and RH.state.farps[name]
  if farp and not farp.lc then
    farp.liquids = { [0] = live.fuelKg }
    farp.ammoItems = live.missiles
  end
end

function logistics.capturePads()
  if not RH.dcs.readPadStock then return end
  local names = {}
  for name in pairs(RH.state.padStock or {}) do names[name] = true end
  for name in pairs(logistics.sessionSpawned or {}) do names[name] = true end
  if RH.dcs.farpPads then
    for _, name in ipairs(RH.dcs.farpPads()) do names[name] = true end
  end
  for name in pairs(names) do
    local held = logistics.padHold[name] and RH.dcs.now() < logistics.padHold[name]
    if logistics.padIsLimited(name) and not held then
      local saved = RH.state.padStock and RH.state.padStock[name]
      local tracked = saved and saved.missiles
      if not tracked and RH.state.farps[name] then tracked = RH.state.farps[name].ammoItems end
      local live = RH.dcs.readPadStock(name, tracked)
      if live then logistics.storePadReading(name, live) end
    end
  end
end

-- Aircraft air-to-air only. Anything else in the missile list is air-to-ground, a decoy, or a SAM.
local airToAir = {
  ["weapons.missiles.9M39_IGLA"] = true,
  ["weapons.missiles.AIM-7E"] = true,
  ["weapons.missiles.AIM-7E-2"] = true,
  ["weapons.missiles.AIM-7F"] = true,
  ["weapons.missiles.AIM-7MH"] = true,
  ["weapons.missiles.AIM-7P"] = true,
  ["weapons.missiles.AIM-9E"] = true,
  ["weapons.missiles.AIM-9J"] = true,
  ["weapons.missiles.AIM-9JULI"] = true,
  ["weapons.missiles.AIM-9L"] = true,
  ["weapons.missiles.AIM-9P"] = true,
  ["weapons.missiles.AIM-9P3"] = true,
  ["weapons.missiles.AIM-9P5"] = true,
  ["weapons.missiles.AIM_120"] = true,
  ["weapons.missiles.AIM_120C"] = true,
  ["weapons.missiles.AIM_54"] = true,
  ["weapons.missiles.AIM_54A_Mk47"] = true,
  ["weapons.missiles.AIM_54A_Mk60"] = true,
  ["weapons.missiles.AIM_54C_Mk47"] = true,
  ["weapons.missiles.AIM_54C_Mk60"] = true,
  ["weapons.missiles.AIM_7"] = true,
  ["weapons.missiles.AIM_9"] = true,
  ["weapons.missiles.AIM_9X"] = true,
  ["weapons.missiles.CATM_9M"] = true,
  ["weapons.missiles.CHAP_AIM92"] = true,
  ["weapons.missiles.FIM_92C"] = true,
  ["weapons.missiles.GAR-8"] = true,
  ["weapons.missiles.HB-AIM-7E"] = true,
  ["weapons.missiles.HB-AIM-7E-2"] = true,
  ["weapons.missiles.Igla_1E"] = true,
  ["weapons.missiles.Igla_S"] = true,
  ["weapons.missiles.MICA_R"] = true,
  ["weapons.missiles.MICA_T"] = true,
  ["weapons.missiles.MMagicII"] = true,
  ["weapons.missiles.Matra Super 530D"] = true,
  ["weapons.missiles.Mistral"] = true,
  ["weapons.missiles.OH58D_FIM_92"] = true,
  ["weapons.missiles.PL-12"] = true,
  ["weapons.missiles.PL-5EII"] = true,
  ["weapons.missiles.PL-8A"] = true,
  ["weapons.missiles.PL-8B"] = true,
  ["weapons.missiles.P_24R"] = true,
  ["weapons.missiles.P_24T"] = true,
  ["weapons.missiles.P_27P"] = true,
  ["weapons.missiles.P_27PE"] = true,
  ["weapons.missiles.P_27T"] = true,
  ["weapons.missiles.P_27TE"] = true,
  ["weapons.missiles.P_33E"] = true,
  ["weapons.missiles.P_40R"] = true,
  ["weapons.missiles.P_40T"] = true,
  ["weapons.missiles.P_60"] = true,
  ["weapons.missiles.P_73"] = true,
  ["weapons.missiles.P_77"] = true,
  ["weapons.missiles.R-13M"] = true,
  ["weapons.missiles.R-13M1"] = true,
  ["weapons.missiles.R-3R"] = true,
  ["weapons.missiles.R-3S"] = true,
  ["weapons.missiles.R-55"] = true,
  ["weapons.missiles.R-60"] = true,
  ["weapons.missiles.RS2US"] = true,
  ["weapons.missiles.R_530F_EM"] = true,
  ["weapons.missiles.R_530F_IR"] = true,
  ["weapons.missiles.R_550"] = true,
  ["weapons.missiles.R_550_M1"] = true,
  ["weapons.missiles.Rb 24"] = true,
  ["weapons.missiles.Rb 24J"] = true,
  ["weapons.missiles.Rb 74"] = true,
  ["weapons.missiles.SD-10"] = true,
  ["weapons.missiles.Strela-2"] = true,
  ["weapons.missiles.Strela-2M"] = true,
  ["weapons.missiles.Strela-3"] = true,
  ["weapons.missiles.Super_530D"] = true,
  ["weapons.missiles.Super_530F"] = true,
}

function logistics.isAirToAirMissile(item)
  return airToAir[item] == true
end

-- Guns, rounds, rockets, pylons, pods, and air-to-air missiles are on the shelf.
-- Every other missile stays off it. APKs and Hercules gear stay off it too.
function logistics.farpSupplyCount(category, item)
  if type(item) ~= "string" then return nil end
  local upper = string.upper(item)
  if string.find(upper, "APK", 1, true) or string.find(upper, "C130", 1, true) then return nil end
  if category == "missiles" or string.find(item, "weapons.missiles.", 1, true) then
    if not logistics.isAirToAirMissile(item) then return nil end
  end
  local supply = fcfg().supply or {}
  return supply[category]
end

-- Hauled air-to-ground missiles, bombs, and torpedoes are the only counts worth saving.
function logistics.keepHauledWeapon(item)
  if type(item) ~= "string" then return false end
  if string.find(string.upper(item), "APK", 1, true) then return false end
  if string.find(item, "weapons.missiles.", 1, true) then
    return not logistics.isAirToAirMissile(item)
  end
  return string.find(item, "weapons.bombs.", 1, true) ~= nil
    or string.find(item, "weapons.torpedoes.", 1, true) ~= nil
end

-- Helicopters are restocked. Fixed wing is cleared so it cannot dynamic-spawn at a FARP.
function logistics.farpAirframeCount(typeName)
  local info = (RH.config.airframes or {})[typeName]
  if type(info) ~= "table" or info.fixedWing then return 0 end
  return fcfg().airframes or 999
end

function logistics.hasWarehouseStock(farp)
  for _, n in pairs(farp.liquids or {}) do
    if type(n) == "number" and n > 0 then return true end
  end
  for _, n in pairs(farp.ammoItems or {}) do
    if type(n) == "number" and n > 0 then return true end
  end
  return false
end

function logistics.stockText(farp)
  if farp.pending then return "marked, builds on next restart with no fuel or ammo" end
  if not farp.built then
    return (logistics.hasUnlimitedCrates(farp) and "unlimited" or tostring(farp.crates)) .. " crates"
  end
  local fuel = 0
  for _, n in pairs(farp.liquids or {}) do
    if type(n) == "number" and n > fuel then fuel = n end
  end
  local ammo = 0
  for _, n in pairs(farp.ammoItems or {}) do ammo = ammo + n end
  return string.format("fuel %d, ammo %d", fuel, ammo)
end

function logistics.showFarpCircles()
  local ids = {}
  for _, farp in pairs(RH.state.farps) do
    local id = "farp?-" .. farp.name
    local radius = fcfg().minSeparation
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

-- Script hospital tents are named "MASH … tent" and use the M92 Tent04. The logistics tent is a FARP tent.
function logistics.isMashTent(static)
  local name = string.lower((static and static.name) or "")
  if string.find(name, "mash", 1, true) then return true end
  local kind = string.lower(((static and static.typeName) or "") .. " " .. ((static and static.display) or ""))
  local hospital = string.find(kind, "tent04", 1, true) or string.find(kind, "m92", 1, true)
  return hospital and string.sub(name, -5) == " tent"
end

function logistics.mashSiteNear(point)
  local reach = mcfg().nearSite or 500
  local function close(pos)
    return pos and pos.x ~= nil and util.distance(pos, point) <= reach
  end
  for _, farp in pairs(RH.state.farps or {}) do
    if close(farp) then return farp end
    for _, spot in ipairs(farp.loadPoints or {}) do
      if close(spot) then return farp end
    end
  end
end

function logistics.validateMashSite(point)
  if logistics.mashSiteNear(point) then return true end
  local reach = mcfg().nearSite or 500
  return false, string.format("You are not within %d m of a FARP or Logistics Center.", reach)
end

function logistics.registerMash(name, point, playerBuilt)
  local existing = RH.state.mashes[name]
  if existing then
    existing.x, existing.y = point.x, point.y
    if playerBuilt then existing.player = true end
    return existing
  end
  RH.state.mashes[name] = { x = point.x, y = point.y, patients = 0, player = playerBuilt and true or nil }
  return RH.state.mashes[name]
end

function logistics.buildMash(point, builtBy)
  local ok, reason = logistics.validateMashSite(point)
  if not ok then return nil, reason end
  local name = string.format("MASH %02d", util.count(RH.state.mashes) + 1)
  local mash = logistics.registerMash(name, point, true)
  RH.dcs.spawnMash(name, point)
  logistics.refreshMashLabels()
  RH.dcs.message("blue", string.format("%s built %s.", builtBy or "A pilot", logistics.mashCallsign(mash)), 15)
  return name
end

function logistics.nearestPlayerMash(point, radius)
  radius = radius or mcfg().packRadius or 100
  local bestName, best, bestDist
  for name, mash in pairs(RH.state.mashes or {}) do
    if mash.player then
      local d = util.distance(mash, point)
      if d <= radius and (not bestDist or d < bestDist) then
        bestName, best, bestDist = name, mash, d
      end
    end
  end
  return bestName, best, bestDist
end

-- Take one player MASH out of the campaign and delete its hospital tent. The crates are CTLD's job.
function logistics.packMash(name)
  local mash = RH.state.mashes and RH.state.mashes[name]
  if not mash or not mash.player then return nil end
  local tentName = name .. " tent"
  RH.state.mashes[name] = nil
  local saved = RH.state.world
  if saved and saved.objects then
    local objects = {}
    for _, obj in ipairs(saved.objects) do
      if obj.name ~= tentName then objects[#objects + 1] = obj end
    end
    saved.objects = objects
  end
  if saved and saved.baseline then saved.baseline[tentName] = nil end
  if RH.dcs.staticObjects and RH.dcs.destroyStatic then
    for _, static in ipairs(RH.dcs.staticObjects()) do
      local sameTent = static.name == tentName
      local leftover = logistics.isMashTent(static) and util.distance(static, mash) <= 30
      if sameTent or leftover then RH.dcs.destroyStatic(static.name) end
    end
  elseif RH.dcs.destroyStatic then
    RH.dcs.destroyStatic(tentName)
  end
  if RH.dcs.removeDrawing then RH.dcs.removeDrawing("mash-" .. name) end
  return mash
end

function logistics.mashCallsign(mash)
  if not mash then return "MASH" end
  local grid = mash.grid
  if not grid and RH.dcs.mgrsGrid then grid = RH.dcs.mgrsGrid(mash) end
  if type(grid) == "string" and grid ~= "" then return "MASH " .. grid end
  return "MASH"
end

function logistics.mashLabelPoint(mash)
  return util.offset(mash, math.pi / 2, 12)
end

function logistics.refreshMashLabels()
  if not RH.dcs.drawLabel then return end
  for name, mash in pairs(RH.state.mashes or {}) do
    if mash.player and mash.x then
      local ok, err = pcall(RH.dcs.drawLabel, "mash-" .. name, "blue", logistics.mashLabelPoint(mash), "MASH", 16, nil, { 0.25, 0.62, 1, 1 })
      if not ok then util.log("MASH label %s failed: %s", tostring(name), tostring(err)) end
    end
  end
end

-- Editor zones and the save from the old MASH tent are not hospitals. Only a player build is.
function logistics.spawnPlayerMashes()
  local keep = {}
  for name, mash in pairs(RH.state.mashes or {}) do
    if mash.player then keep[name] = mash end
  end
  RH.state.mashes = keep
  local saved = RH.state.world
  if saved and saved.objects then
    local objects = {}
    for _, obj in ipairs(saved.objects) do
      if not logistics.isMashTent(obj) then objects[#objects + 1] = obj end
    end
    saved.objects = objects
  end
  if saved and saved.baseline then
    for objName in pairs(saved.baseline) do
      if logistics.isMashTent({ name = objName }) then saved.baseline[objName] = nil end
    end
  end
  if RH.dcs.staticObjects and RH.dcs.destroyStatic then
    for _, static in ipairs(RH.dcs.staticObjects()) do
      if logistics.isMashTent(static) then RH.dcs.destroyStatic(static.name) end
    end
  end
  for name, mash in pairs(RH.state.mashes) do
    RH.dcs.spawnMash(name, mash)
  end
  logistics.refreshMashLabels()
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
  if not m then return false end
  return m.patients >= mcfg().capacity
end

function logistics.mashStatus(from)
  local rows = {}
  local cap = mcfg().capacity
  for _, m in pairs(RH.state.mashes or {}) do
    table.insert(rows, { mash = m, distance = from and util.distance(from, m) or nil })
  end
  table.sort(rows, function(a, b)
    if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
    return logistics.mashCallsign(a.mash) < logistics.mashCallsign(b.mash)
  end)
  if #rows == 0 then return "No MASH has been built yet." end
  local lines = {}
  for _, row in ipairs(rows) do
    local call = logistics.mashCallsign(row.mash)
    local count = string.format("%d/%d pilots", row.mash.patients or 0, cap)
    if row.distance then
      table.insert(lines, string.format("%s - %.1f km - %s", call, row.distance / 1000, count))
    else
      table.insert(lines, string.format("%s - %s", call, count))
    end
  end
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
  logistics.dropDeletedFarps()
  logistics.dropStackedFarps()
  logistics.discoverEditorPads()
  logistics.assignFarpNames()
  logistics.clearCarriedStock()
  logistics.spawnPlayerMashes()
  logistics.spawnBuilt()
  logistics.equipEditorFarps()
  logistics.trimHumvees()
  logistics.syncPads()
  if RH.after then
    local function catchLatePads()
      logistics.discoverEditorPads()
      logistics.equipEditorFarps()
      logistics.trimHumvees()
      logistics.syncPads()
      logistics.refreshMapLabels()
      logistics.refreshMashLabels()
      if RH.ctld and RH.ctld.refreshZones then RH.ctld.refreshZones() end
    end
    RH.after(2, catchLatePads)
    RH.after(10, catchLatePads)
    RH.after(20, function() RH.state.warehouseWipe = nil end)
  end
  logistics.refreshMapLabels()
  logistics.refreshMashLabels()
  RH.every(30, function()
    logistics.refreshMapLabels()
    logistics.refreshMashLabels()
  end)
  -- Fuel and ammo change while people are flying. Write them down often, not only every five minutes.
  RH.every(30, function()
    if RH.persistence and RH.persistence.save then RH.persistence.save() end
  end)
  for name, bo in pairs(RH.state.blueOutposts) do
    RH.dcs.drawCircle("blueoutpost-" .. name, "blue", bo, bo.radius, { 0, 0.4, 1, 1 }, { 0, 0.4, 1, 0.08 }, name)
  end
end

return logistics
