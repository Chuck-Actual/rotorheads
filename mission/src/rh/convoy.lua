RH = RH or {}

local util = RH.util

-- Side mission: escort a supply convoy (2 neutral trucks + a blue Humvee) between two FARPs/LCs.
-- Insurgents ambush it at random; the convoy halts until they are dead. On arrival each surviving truck
-- delivers up to 5 crates to the destination FARP.
local convoy = { active = nil, nextStartAt = 0 }
RH.convoy = convoy

local function cfg() return RH.config.convoy end

function convoy.pickRoute()
  local farps = RH.logistics.farps()
  local need = cfg().trucks * cfg().cratesPerTruck
  local origins, destinations = {}, {}
  for _, f in ipairs(farps) do
    if RH.logistics.hasUnlimitedCrates(f) or f.crates >= need * 2 then table.insert(origins, f) end
    if not RH.logistics.hasUnlimitedCrates(f) and f.crates < RH.config.farp.maxCrates then table.insert(destinations, f) end
  end
  if #origins == 0 or #destinations == 0 then return nil end
  table.sort(destinations, function(a, b) return a.crates < b.crates end)
  for _, dest in ipairs(destinations) do
    local best, bestDist
    for _, o in ipairs(origins) do
      local d = util.distance(o, dest)
      if o ~= dest and d > 5000 and d < 80000 and (not bestDist or d < bestDist) then best, bestDist = o, d end
    end
    if best then return best, dest end
  end
  return nil
end

function convoy.begin()
  local origin, dest = convoy.pickRoute()
  if not origin then
    convoy.nextStartAt = RH.dcs.now() + cfg().restartDelay
    return nil
  end
  local load = cfg().trucks * cfg().cratesPerTruck
  RH.logistics.takeCrates(origin, load)
  local start = util.offset(origin, math.random() * 2 * math.pi, 200)
  local trucks = RH.dcs.spawnGroup(RH.config.templates.convoyTruck, start, "Supply convoy")
  local escort = RH.dcs.spawnGroup(RH.config.templates.convoyEscort, util.offset(start, 0, 40), "Convoy escort")
  if not trucks then
    RH.logistics.returnCrates(origin, load)
    convoy.nextStartAt = RH.dcs.now() + cfg().restartDelay
    return nil
  end
  local destPoint = { x = dest.x, y = dest.y }
  RH.dcs.routeGroup(trucks, destPoint, true)
  if escort then RH.dcs.routeGroup(escort, destPoint, true) end
  convoy.active = {
    origin = origin.name,
    destination = dest.name,
    destPoint = destPoint,
    trucks = trucks,
    escort = escort,
    ambush = nil,
    halted = false,
    nextAmbushAt = RH.dcs.now() + math.random(cfg().ambushIntervalMin, cfg().ambushIntervalMax),
    drawnAt = nil,
  }
  RH.dcs.message("blue", string.format("Side mission: escort the supply convoy from %s to %s. Look for the yellow circle on the F10 map.",
    origin.name, dest.name), 20)
  convoy.redraw()
  return convoy.active
end

function convoy.redraw()
  local c = convoy.active
  if not c then return end
  local pos = RH.dcs.groupPosition(c.trucks)
  if not pos then return end
  if c.drawnAt and util.distance(c.drawnAt, pos) < 2000 then return end
  c.drawnAt = pos
  local center = util.randomPointInCircle(pos, cfg().displayRadius * 0.4)
  RH.dcs.drawCircle("convoy", "blue", center, cfg().displayRadius, { 1, 0.85, 0, 1 }, { 1, 0.85, 0, 0.1 }, "Escort convoy")
end

function convoy.finish(success, delivered)
  local c = convoy.active
  if not c then return end
  RH.dcs.removeDrawing("convoy")
  if success then
    RH.dcs.message("blue", string.format("Convoy arrived at %s and delivered %d crates. Good work, escorts!", c.destination, delivered), 20)
  else
    RH.dcs.message("blue", "The supply convoy was destroyed.", 15)
  end
  local trucks, escort = c.trucks, c.escort
  RH.after(60, function()
    RH.dcs.destroyGroup(trucks)
    if escort then RH.dcs.destroyGroup(escort) end
  end)
  convoy.active = nil
  convoy.nextStartAt = RH.dcs.now() + cfg().restartDelay
end

function convoy.springAmbush(c, pos)
  local heading = math.atan2(c.destPoint.y - pos.y, c.destPoint.x - pos.x)
  local ahead = util.offset(pos, heading, math.random(cfg().ambushDistanceMin, cfg().ambushDistanceMax))
  local spot = util.offset(ahead, heading + math.pi / 2 * (math.random() < 0.5 and 1 or -1), 150)
  local tpl = RH.config.templates.insurgents
  c.ambush = RH.dcs.spawnGroup(tpl[math.random(#tpl)], spot, "Insurgents")
  if not c.ambush then return end
  RH.dcs.bigSmoke(util.randomPointInCircle(spot, 200), "black")
  RH.dcs.holdGroup(c.trucks)
  if c.escort then RH.dcs.holdGroup(c.escort) end
  c.halted = true
  RH.dcs.message("blue", "Convoy under attack! Insurgents near the black smoke. Watch your fire around the trucks.", 15)
end

function convoy.tick()
  local now = RH.dcs.now()
  local c = convoy.active
  if not c then
    if now >= convoy.nextStartAt then convoy.begin() end
    return
  end

  local alive = RH.dcs.groupAliveCount(c.trucks)
  if alive == 0 then return convoy.finish(false, 0) end
  local pos = RH.dcs.groupPosition(c.trucks)

  if pos and util.distance(pos, c.destPoint) <= cfg().arrivalRadius then
    local farp = RH.state.farps[c.destination]
    local delivered = farp and RH.logistics.returnCrates(farp, alive * cfg().cratesPerTruck) or 0
    return convoy.finish(true, delivered)
  end

  if c.halted then
    if not c.ambush or RH.dcs.groupAliveCount(c.ambush) == 0 then
      c.halted = false
      c.ambush = nil
      RH.dcs.routeGroup(c.trucks, c.destPoint, true)
      if c.escort then RH.dcs.routeGroup(c.escort, c.destPoint, true) end
      c.nextAmbushAt = now + math.random(cfg().ambushIntervalMin, cfg().ambushIntervalMax)
      RH.dcs.message("blue", "Ambush cleared. The convoy is moving again.", 10)
    end
  elseif pos and now >= c.nextAmbushAt then
    convoy.springAmbush(c, pos)
  end
  convoy.redraw()
end

function convoy.start()
  convoy.nextStartAt = RH.dcs.now() + 120
  RH.every(15, convoy.tick, 30)
end

return convoy
