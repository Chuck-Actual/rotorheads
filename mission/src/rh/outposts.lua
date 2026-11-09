RH = RH or {}

local util = RH.util

-- REDFOR outposts (three stacked red containers). Destroying one opens a contested zone (yellow circle).
-- Blue-only presence turns it blue, red-only presence turns it red. After a hidden timer the zone resolves:
-- blue -> outpost captured and its area of operations stops being reinforced; red -> outpost repaired.
local outposts = { list = {}, staticOwner = {}, areaOwner = {} }
RH.outposts = outposts

local COLORS = {
  yellow = { line = { 1, 0.85, 0, 1 }, fill = { 1, 0.85, 0, 0.15 } },
  blue = { line = { 0, 0.4, 1, 1 }, fill = { 0, 0.4, 1, 0.15 } },
  red = { line = { 1, 0, 0, 1 }, fill = { 1, 0, 0, 0.15 } },
}

local function cfg() return RH.config.outpost end

local function outpostState(name)
  RH.state.outposts[name] = RH.state.outposts[name] or { status = "intact" }
  return RH.state.outposts[name]
end

function outposts.discover()
  local prefix = RH.config.prefixes.outpost
  outposts.list, outposts.staticOwner, outposts.areaOwner = {}, {}, {}
  for _, zone in ipairs(RH.dcs.zonesWithPrefix(prefix)) do
    local o = {
      name = zone.name,
      label = zone.name:sub(#prefix + 1),
      point = zone.point,
      statics = RH.dcs.staticsInZone(zone, "red"),
      color = nil,
      timerEndsAt = nil,
    }
    table.insert(outposts.list, o)
    for _, s in ipairs(o.statics) do outposts.staticOwner[s.name] = o end
  end
  util.log("outposts: %d red outposts", #outposts.list)
end

function outposts.status(o)
  return outpostState(o.name).status
end

function outposts.applySavedState()
  for _, o in ipairs(outposts.list) do
    local st = outpostState(o.name)
    if st.status == "captured" then
      for _, s in ipairs(o.statics) do RH.dcs.destroyStatic(s.name) end
      outposts.drawCaptured(o)
    else
      st.status = "intact"
    end
  end
end

function outposts.drawCaptured(o)
  RH.dcs.drawCircle("outpost-" .. o.name, "all", o.point, cfg().contestedRadius, COLORS.blue.line, COLORS.blue.fill,
    "Captured outpost " .. o.label)
end

-- An AO belongs to the nearest outpost within 20 km; capturing that outpost takes the AO off the REDFOR front.
function outposts.areaCaptured(area)
  local owner = outposts.areaOwner[area.name]
  if owner == nil then
    local best, bestDist = false, 20000
    for _, o in ipairs(outposts.list) do
      local d = util.distance(o.point, area.point)
      if d < bestDist then best, bestDist = o, d end
    end
    outposts.areaOwner[area.name] = best
    owner = best
  end
  return owner and outposts.status(owner) == "captured" or false
end

function outposts.allStaticsDead(o)
  if #o.statics == 0 then return false end
  for _, s in ipairs(o.statics) do
    if RH.dcs.isStaticAlive(s.name) then return false end
  end
  return true
end

function outposts.setColor(o, color)
  if o.color == color then return end
  o.color = color
  local c = COLORS[color]
  RH.dcs.drawCircle("outpost-" .. o.name, "all", o.point, cfg().contestedRadius, c.line, c.fill, "Contested outpost " .. o.label)
  if color == "yellow" then
    o.timerEndsAt = nil
  else
    o.timerEndsAt = RH.dcs.now() + math.random(cfg().holdTimeMin, cfg().holdTimeMax)
  end
end

function outposts.markDestroyed(o)
  local st = outpostState(o.name)
  if st.status ~= "intact" then return end
  st.status = "contested"
  o.color = nil
  outposts.setColor(o, "yellow")
  RH.dcs.message("all", string.format("REDFOR outpost %s destroyed. Clear the zone and hold it with ground units to capture it.", o.label), 20)
  if RH.redair then RH.redair.respondToOutpostLoss(o.point) end
  RH.dcs.notify("outpost_destroyed", { outpost = o.label })
end

function outposts.evaluateColor(o)
  local radius = cfg().contestedRadius
  local red = #RH.dcs.groundUnitsInRadius("red", o.point, radius)
  local blue = #RH.dcs.groundUnitsInRadius("blue", o.point, radius)
  if blue > 0 and red == 0 then return "blue" end
  if red > 0 and blue == 0 then return "red" end
  return "yellow"
end

function outposts.resolve(o)
  local st = outpostState(o.name)
  if o.color == "blue" then
    st.status = "captured"
    o.timerEndsAt = nil
    outposts.drawCaptured(o)
    RH.dcs.message("all", string.format("Outpost %s captured! The REDFOR front has been pushed back.", o.label), 20)
    RH.dcs.notify("outpost_captured", { outpost = o.label })
  elseif o.color == "red" then
    st.status = "intact"
    o.color = nil
    o.timerEndsAt = nil
    for _, s in ipairs(o.statics) do RH.dcs.respawnStatic(s) end
    RH.dcs.removeDrawing("outpost-" .. o.name)
    RH.dcs.message("all", string.format("REDFOR has repaired outpost %s.", o.label), 15)
  end
end

function outposts.tick()
  local now = RH.dcs.now()
  for _, o in ipairs(outposts.list) do
    local status = outposts.status(o)
    if status == "intact" and outposts.allStaticsDead(o) then
      outposts.markDestroyed(o)
    elseif status == "contested" then
      outposts.setColor(o, outposts.evaluateColor(o))
      if o.timerEndsAt and now >= o.timerEndsAt then outposts.resolve(o) end
    end
  end
end

function outposts.onDead(event)
  local o = event.initiatorName and outposts.staticOwner[event.initiatorName]
  if o and outposts.status(o) == "intact" and outposts.allStaticsDead(o) then
    outposts.markDestroyed(o)
  end
end

function outposts.start()
  outposts.discover()
  outposts.applySavedState()
  RH.events.on("dead", outposts.onDead)
  RH.every(cfg().evaluateInterval, outposts.tick, 15)
end

return outposts
