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

local PAD_NAMES = { "ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL" }

-- The editor pads are named static1-4 and static1-5. On the map they read FARP ALPHA and FARP BRAVO.
function logistics.padLabel(name, index)
  if util.startsWith(name, RH.config.prefixes.farp) then
    return "FARP " .. name:sub(#RH.config.prefixes.farp + 1):gsub("_", " ")
  end
  if util.startsWith(name, "FARP") then return name end
  return "FARP " .. (PAD_NAMES[index] or tostring(index))
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
    -- A tent found first keeps the stock. The pad's ALPHA/BRAVO name is the one on the map.
    if existing.editor and not logistics.isTent(point) then
      existing.label = logistics.padLabel(name, index)
    end
    return nil
  end
  local airfield = logistics.airfieldNear(point, fcfg().lcAirfieldRadius)
  local lc = airfield ~= nil and airfield.coalition ~= "red"
  return logistics.register(name, point, {
    editor = true,
    label = logistics.padLabel(name, index),
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
    local index = 0
    for _ in pairs(RH.state.farps) do index = index + 1 end
    local name = tent.name ~= "" and tent.name or "FARP"
    registerEditorSite(name, tent, index + 1)
  end
end

-- The editor FARP already has the tent and the pad. It still needs the Humvee the rearm
-- window uses, and the pad warehouse needs fuel or defuel answers "unable to comply".
function logistics.equipEditorFarps()
  for _, farp in pairs(RH.state.farps) do
    if farp.editor and not farp.lc and not farp.pending then
      local tent = logistics.nearestTent(farp, 250)
      local spot = util.offset(tent or farp, math.rad(tent and 180 or 270), tent and 25 or 45)
      local humvee = farp.name .. " Humvee"
      if RH.dcs.objectExists and RH.dcs.spawnVehicle and not RH.dcs.objectExists(humvee) then
        RH.dcs.spawnVehicle(humvee, "Hummer", spot, 90)
      end
      if RH.dcs.airbases and RH.dcs.writePadStock then
        local pad, padDist
        for _, ab in ipairs(RH.dcs.airbases()) do
          if ab.kind == "helipad" and ab.coalition ~= "red" then
            local d = util.distance(ab.point, farp)
            if d <= 400 and (not padDist or d < padDist) then pad, padDist = ab, d end
          end
        end
        if pad then
          local stock = logistics.ensurePadStock(pad.name)
          RH.dcs.writePadStock(pad.name, stock)
        end
      end
      if RH.dcs.writePadStock then
        for _, site in ipairs(logistics.editorPads()) do
          if util.distance(site, farp) <= 400 then
            RH.dcs.writePadStock(site.name, logistics.ensurePadStock(site.name))
          end
        end
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
  local anchor = logistics.nearestTent(farp, 250) or farp
  return util.offset(anchor, math.pi / 2, 45)
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
    RH.dcs.drawLabel("farp-stock-" .. farp.name, "all", logistics.labelPoint(farp), logistics.mapLabelText(farp), 18)
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
  local n = 1
  for _, farp in pairs(RH.state.farps) do
    if not farp.lc and (farp.built or farp.pending) then n = n + 1 end
  end
  return string.format("FARP %02d", n)
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
  })
  RH.dcs.drawCircle("pending-" .. name, "blue", farp, 600, { 0, 0.7, 1, 1 }, { 0, 0.7, 1, 0.15 }, name .. " (next restart)")
  RH.dcs.smoke(farp, RH.config.markers.smokeColors.green)
  if RH.persistence and RH.persistence.save then RH.persistence.save() end
  RH.dcs.message("blue", string.format(
    "%s marked %s and saved it. Restart the mission to build the pad, tent, Humvee, fuel depot, and ammo dump. The Mission Editor copy is RH_Editor.miz, written beside your mission when you leave.",
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
  if RH.dcs.captureFarpStock then
    for name in pairs(logistics.sessionSpawned or {}) do
      local farp = RH.state.farps[name]
      if farp then RH.dcs.captureFarpStock(farp) end
    end
  end
  logistics.capturePads()
end

-- One load for the editor pads (static1-4 and static1-5). Later restarts write the
-- saved figures back and do not add another 10 tons or another 40 missiles.
logistics.padHold = {}

function logistics.openingPadStock()
  return {
    fuelKg = 10000,
    missiles = {
      ["weapons.missiles.AGM_114K"] = 40,
      ["weapons.missiles.AGM_114L"] = 40,
      ["weapons.missiles.Vikhr_M"] = 40,
    },
  }
end

function logistics.ensurePadStock(name)
  RH.state.padStock = RH.state.padStock or {}
  local saved = RH.state.padStock[name]
  if type(saved) == "table" and saved.granted and type(saved.fuelKg) == "number" and type(saved.missiles) == "table" then
    return saved, false
  end
  local stock = logistics.openingPadStock()
  stock.granted = true
  RH.state.padStock[name] = stock
  return stock, true
end

function logistics.syncPads()
  if not RH.dcs.farpPads or not RH.dcs.writePadStock then return end
  local fresh = {}
  for _, name in ipairs(RH.dcs.farpPads()) do
    local stock, granted = logistics.ensurePadStock(name)
    RH.dcs.writePadStock(name, stock)
    if logistics.padHold[name] == nil then logistics.padHold[name] = RH.dcs.now() + 25 end
    if granted then fresh[#fresh + 1] = name end
  end
  if #fresh > 0 then
    RH.dcs.message("blue", "One-time FARP stock, 10 tons of fuel and 40 AGM-114K, AGM-114L, and Vikhr: " .. table.concat(fresh, ", "), 30)
  end
end

function logistics.capturePads()
  if not RH.dcs.readPadStock then return end
  RH.state.padStock = RH.state.padStock or {}
  for name, saved in pairs(RH.state.padStock) do
    if type(saved) == "table" and saved.granted and not (logistics.padHold[name] and RH.dcs.now() < logistics.padHold[name]) then
      local live = RH.dcs.readPadStock(name, saved.missiles)
      if live then
        live.granted = true
        RH.state.padStock[name] = live
      end
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
  logistics.dropStackedFarps()
  logistics.discoverEditorPads()
  for _, z in ipairs(RH.dcs.zonesWithPrefix(RH.config.prefixes.mash)) do
    logistics.registerMash(z.name, z.point)
  end
  for name, m in pairs(RH.state.mashes) do
    RH.dcs.spawnMash(name, m)
  end
  logistics.spawnBuilt()
  logistics.equipEditorFarps()
  logistics.syncPads()
  if RH.after then
    local function catchLatePads()
      logistics.discoverEditorPads()
      logistics.equipEditorFarps()
      logistics.syncPads()
      logistics.refreshMapLabels()
      if RH.ctld and RH.ctld.refreshZones then RH.ctld.refreshZones() end
    end
    RH.after(2, catchLatePads)
    RH.after(10, catchLatePads)
  end
  logistics.refreshMapLabels()
  RH.every(30, logistics.refreshMapLabels)
  -- Fuel and ammo change while people are flying. Write them down often, not only every five minutes.
  RH.every(30, function()
    if RH.persistence and RH.persistence.save then RH.persistence.save() end
  end)
  for name, bo in pairs(RH.state.blueOutposts) do
    RH.dcs.drawCircle("blueoutpost-" .. name, "blue", bo, bo.radius, { 0, 0.4, 1, 1 }, { 0, 0.4, 1, 0.08 }, name)
  end
end

return logistics
