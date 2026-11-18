RH = RH or {}

local util = RH.util

-- Enemy factories feed reinforcement convoys to the areas of operation (AOs) they supply.
-- Factory lifecycle: active -> destroyed (slower spawns, red smoke, Mi-26 repair flights) -> captured at the next restart
-- if at least four blue ground units hold the ruins when the campaign is saved.
local factories = { list = {}, byName = {}, areas = {}, staticOwner = {} }
RH.factories = factories

local function cfg() return RH.config.factory end

local function factoryState(name)
  RH.state.factories[name] = RH.state.factories[name] or { status = "active" }
  return RH.state.factories[name]
end

function factories.discover()
  local prefixes = RH.config.prefixes
  factories.list, factories.byName, factories.staticOwner = {}, {}, {}
  for _, zone in ipairs(RH.dcs.zonesWithPrefix(prefixes.factory)) do
    local f = {
      name = zone.name,
      label = zone.name:sub(#prefixes.factory + 1),
      point = zone.point,
      radius = zone.radius,
      statics = RH.dcs.staticsInZone(zone, "red"),
      convoys = {},
      repairFlight = nil,
      revealed = false,
      nextSpawnAt = 0,
      nextRepairFlightAt = 0,
      nextSmokeAt = 0,
    }
    table.insert(factories.list, f)
    factories.byName[f.name] = f
    for _, s in ipairs(f.statics) do factories.staticOwner[s.name] = f end
  end

  factories.areas = {}
  for _, zone in ipairs(RH.dcs.zonesWithPrefix(prefixes.area)) do
    table.insert(factories.areas, {
      name = zone.name,
      point = zone.point,
      radius = zone.radius > 0 and zone.radius or RH.config.area.radius,
      groups = {},
    })
  end
  util.log("factories: %d factories, %d areas of operation", #factories.list, #factories.areas)
end

function factories.status(f)
  return factoryState(f.name).status
end

-- Applied once after loading the save: destroyed factories are rebuilt on restart, captured ones stay gone.
function factories.applySavedState()
  for _, f in ipairs(factories.list) do
    local st = factoryState(f.name)
    if st.captureHeld and st.status ~= "captured" then
      st.status = "captured"
      RH.dcs.message("all", string.format("Factory %s has been captured by BLUFOR.", f.label), 20)
    end
    st.captureHeld = nil
    if st.status == "captured" then
      for _, s in ipairs(f.statics) do RH.dcs.destroyStatic(s.name) end
    elseif st.status == "destroyed" then
      st.status = "active"
    end
  end
end

function factories.areaHeld(area)
  if RH.outposts and RH.outposts.areaCaptured and RH.outposts.areaCaptured(area) then return false end
  return true
end

function factories.supplierFor(area)
  local best, bestDist
  for _, f in ipairs(factories.list) do
    if factories.status(f) ~= "captured" then
      local d = util.distance(f.point, area.point)
      if not bestDist or d < bestDist then best, bestDist = f, d end
    end
  end
  return best
end

local function pruneGroups(groups)
  local alive = {}
  for _, g in ipairs(groups) do
    if RH.dcs.groupAliveCount(g) > 0 then table.insert(alive, g) end
  end
  return alive
end

function factories.spawnGarrisons()
  local tpl = RH.config.templates.garrison
  for _, area in ipairs(factories.areas) do
    if factories.areaHeld(area) and factories.supplierFor(area) then
      for i = 1, RH.config.area.garrisonGroups do
        local p = util.randomPointInCircle(area.point, area.radius * 0.8)
        local g = RH.dcs.spawnGroup(tpl[math.random(#tpl)], p, "Garrison " .. area.name)
        if g then table.insert(area.groups, g) end
      end
    end
  end
end

function factories.reinforce(f, now)
  if now < f.nextSpawnAt then return end
  local status = factories.status(f)
  if status == "captured" then return end
  f.convoys = pruneGroups(f.convoys)
  local interval = status == "destroyed" and cfg().reinforceIntervalDamaged or cfg().reinforceInterval
  f.nextSpawnAt = now + interval
  if #f.convoys >= cfg().maxConvoysPerFactory then return end

  local target
  for _, area in ipairs(factories.areas) do
    area.groups = pruneGroups(area.groups)
    if factories.areaHeld(area) and factories.supplierFor(area) == f and #area.groups < RH.config.area.garrisonGroups then
      if not target or #area.groups < #target.groups then target = area end
    end
  end
  if not target then return end

  local tpl = RH.config.templates.reinforcements
  local spawnPoint = util.randomPointInCircle(f.point, math.max(100, f.radius * 0.5))
  local g = RH.dcs.spawnGroup(tpl[math.random(#tpl)], spawnPoint, "Convoy " .. f.label)
  if not g then return end
  RH.dcs.routeGroup(g, util.randomPointInCircle(target.point, target.radius * 0.7), true)
  table.insert(f.convoys, g)
  table.insert(target.groups, g)
end

function factories.allStaticsDead(f)
  if #f.statics == 0 then return false end
  for _, s in ipairs(f.statics) do
    if RH.dcs.isStaticAlive(s.name) then return false end
  end
  return true
end

function factories.markDestroyed(f)
  local st = factoryState(f.name)
  if st.status ~= "active" then return end
  st.status = "destroyed"
  f.nextRepairFlightAt = RH.dcs.now() + cfg().repairFlightInterval
  f.nextSmokeAt = 0
  RH.dcs.message("all", string.format("Factory %s destroyed! Capture it with %d ground units within %dm before it is repaired.",
    f.label, cfg().captureUnitsRequired, cfg().captureRadius), 20)
  RH.dcs.notify("factory_destroyed", { factory = f.label })
end

function factories.repair(f)
  local st = factoryState(f.name)
  if st.status ~= "destroyed" then return end
  for _, s in ipairs(f.statics) do RH.dcs.respawnStatic(s) end
  st.status = "active"
  st.captureHeld = nil
  RH.dcs.spawnGroup(RH.config.templates.factoryTroops, util.randomPointInCircle(f.point, 150), "Factory troops " .. f.label)
  RH.dcs.message("all", string.format("REDFOR Mi-26 reached factory %s. The factory has been repaired.", f.label), 15)
end

function factories.blueUnitsAtRuins(f)
  return #RH.dcs.groundUnitsInRadius("blue", f.point, cfg().captureRadius)
end

function factories.updateDestroyed(f, now)
  local st = factoryState(f.name)
  st.captureHeld = factories.blueUnitsAtRuins(f) >= cfg().captureUnitsRequired

  if now >= f.nextSmokeAt then
    RH.dcs.smoke(f.point, RH.config.markers.smokeColors.red)
    f.nextSmokeAt = now + cfg().smokeInterval
  end

  if f.repairFlight then
    local g = f.repairFlight
    if RH.dcs.groupAliveCount(g) == 0 then
      f.repairFlight = nil
    else
      local pos = RH.dcs.groupPosition(g)
      if pos and util.distance(pos, f.point) <= cfg().repairLandingRadius and RH.dcs.groupLanded(g) then
        f.repairFlight = nil
        factories.repair(f)
        RH.after(120, function() RH.dcs.destroyGroup(g) end)
      end
    end
  elseif now >= f.nextRepairFlightAt then
    local base = RH.dcs.nearestZone(RH.config.prefixes.redHeliBase, f.point)
    if base then
      f.repairFlight = RH.dcs.spawnHeloLanding(RH.config.templates.repairHelo, base.point, f.point, "Mi-26 " .. f.label)
      if f.repairFlight then
        RH.dcs.message("blue", string.format("Intel: REDFOR Mi-26 inbound to repair factory %s.", f.label), 15)
      end
    end
    f.nextRepairFlightAt = now + cfg().repairFlightInterval
  end
end

function factories.updateVisibility(f)
  if f.revealed or factories.status(f) == "captured" then return end
  if #RH.dcs.unitsInRadius("blue", f.point, cfg().visibilityRange) > 0 then
    f.revealed = true
    RH.dcs.drawCircle("factory-" .. f.name, "blue", f.point, 600, { 1, 0, 0, 1 }, { 1, 0, 0, 0.15 }, "Factory " .. f.label)
    RH.dcs.message("blue", string.format("Factory %s spotted.", f.label), 10)
  end
end

function factories.tick()
  local now = RH.dcs.now()
  for _, f in ipairs(factories.list) do
    local status = factories.status(f)
    if status ~= "captured" then
      if status == "active" and factories.allStaticsDead(f) then factories.markDestroyed(f) end
      if factories.status(f) == "destroyed" then factories.updateDestroyed(f, now) end
      factories.updateVisibility(f)
      factories.reinforce(f, now)
    end
  end
end

function factories.onDead(event)
  local name = event.initiatorName
  if not name then return end
  local f = factories.staticOwner[name]
  if f and factories.status(f) == "active" and factories.allStaticsDead(f) then
    factories.markDestroyed(f)
  end
end

function factories.start()
  factories.discover()
  factories.applySavedState()
  factories.spawnGarrisons()
  RH.events.on("dead", factories.onDead)
  RH.every(30, factories.tick, 10)
end

return factories
