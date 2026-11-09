RH = RH or {}

local util = RH.util

-- REDFOR air reactions:
--  * Mi-28 Havoc when an outpost is destroyed or a blue attack helicopter is spotted by red ground units.
--  * MiG-29 / F-4 when a blue fixed-wing aircraft is airborne and detected. Fighters only hunt blue fixed wing.
local redair = { helos = {}, fighters = {}, areaCooldowns = {}, lastFighterAt = -math.huge }
RH.redair = redair

local function cfg() return RH.config.redAir end

local function prune(list)
  local alive = {}
  for _, g in ipairs(list) do
    if RH.dcs.groupAliveCount(g) > 0 then table.insert(alive, g) end
  end
  return alive
end

local function cooldownKey(point)
  return string.format("%d:%d", math.floor(point.x / 10000), math.floor(point.y / 10000))
end

function redair.launchHavoc(target, reason)
  redair.helos = prune(redair.helos)
  if #redair.helos >= cfg().maxAttackHelos then return nil end
  local key = cooldownKey(target)
  local now = RH.dcs.now()
  if redair.areaCooldowns[key] and now < redair.areaCooldowns[key] then return nil end
  local base = RH.dcs.nearestZone(RH.config.prefixes.redHeliBase, target)
  if not base then return nil end
  local g = RH.dcs.spawnAttackHelo(RH.config.templates.attackHelo, base.point, target, "Havoc")
  if g then
    table.insert(redair.helos, g)
    redair.areaCooldowns[key] = now + cfg().areaCooldown
    RH.dcs.message("blue", "Warning: REDFOR Mi-28 Havoc launched (" .. reason .. ").", 15)
  end
  return g
end

function redair.respondToOutpostLoss(point)
  return redair.launchHavoc(point, "outpost destroyed")
end

function redair.launchFighter(targetPlayer)
  redair.fighters = prune(redair.fighters)
  local now = RH.dcs.now()
  if #redair.fighters >= cfg().maxFighters or now - redair.lastFighterAt < cfg().fighterCooldown then return nil end
  local base = RH.dcs.nearestZone(RH.config.prefixes.redAirBase, targetPlayer.pos)
  if not base then return nil end
  local tpl = RH.config.templates.fighters
  local g = RH.dcs.spawnInterceptor(tpl[math.random(#tpl)], base.point, targetPlayer.unitName, "Red CAP")
  if g then
    table.insert(redair.fighters, g)
    redair.lastFighterAt = now
    RH.dcs.message("blue", "Warning: REDFOR fighters scrambled against blue fixed wing.", 15)
  end
  return g
end

function redair.isAttackHelo(typeName)
  return util.contains(cfg().attackHeloTypes, typeName)
end

-- A player counts as spotted when a red ground unit within detection range has line of sight to them.
function redair.spotted(player)
  for _, red in ipairs(RH.dcs.groundUnitsInRadius("red", player.pos, cfg().detectionRange)) do
    if RH.dcs.lineOfSight(red.pos3 or red.pos, player.pos3 or player.pos) then return true end
  end
  return false
end

function redair.tick()
  for _, p in ipairs(RH.dcs.players()) do
    if p.coalition == "blue" and not p.onGround then
      if p.category == "plane" then
        if redair.spotted(p) then redair.launchFighter(p) end
      elseif p.category == "helicopter" and redair.isAttackHelo(p.typeName) then
        if redair.spotted(p) then redair.launchHavoc(p.pos, "attack helicopter spotted") end
      end
    end
  end
end

function redair.start()
  RH.every(cfg().checkInterval, redair.tick, 60)
end

-- Paratroopers: random red infantry dropped around the map after every restart.
local paratroopers = {}
RH.paratroopers = paratroopers

function paratroopers.spawn()
  local zones = RH.dcs.zonesWithPrefix(RH.config.prefixes.paraZone)
  if #zones == 0 and RH.factories then zones = RH.factories.areas end
  if #zones == 0 then return 0 end
  local tpl = RH.config.templates.paratroopers
  local spawned = 0
  for i = 1, RH.config.paratroopers.groupsPerRestart do
    local zone = zones[math.random(#zones)]
    local radius = (zone.radius and zone.radius > 0) and zone.radius or 3000
    if RH.dcs.spawnGroup(tpl[math.random(#tpl)], util.randomPointInCircle(zone.point, radius), "Paratroopers") then
      spawned = spawned + 1
    end
  end
  util.log("paratroopers: %d groups dropped", spawned)
  return spawned
end

return redair
