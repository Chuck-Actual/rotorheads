RH = RH or {}

local util = RH.util

-- Writes Saved Games\DCS\rotorheads\livemap.json for the live map web app.
-- Red units only appear once a blue unit has been near them, and spotted positions linger for 30 minutes
-- so that resupply routes show up as trails, like on the original live map.
local livemap = { sightings = {}, sightingTTL = 1800, spotRange = 6000 }
RH.livemap = livemap

local function ll(point)
  local lat, lon = RH.dcs.toLatLon(point)
  return math.floor(lat * 1e5 + 0.5) / 1e5, math.floor(lon * 1e5 + 0.5) / 1e5
end

local function withLL(t, point)
  t.lat, t.lon = ll(point)
  return t
end

function livemap.recordSightings(now)
  local blue = RH.dcs.unitsInRadius("blue", nil, nil)
  local seen = {}
  for _, b in ipairs(blue) do
    for _, r in ipairs(RH.dcs.groundUnitsInRadius("red", b.pos, livemap.spotRange)) do
      if not seen[r.name] then
        seen[r.name] = true
        local key = string.format("%s@%d:%d", r.name, math.floor(r.pos.x / 500), math.floor(r.pos.y / 500))
        livemap.sightings[key] = { pos = r.pos, aa = r.isAA, typeName = r.typeName, seenAt = now }
      end
    end
  end
  for key, s in pairs(livemap.sightings) do
    if now - s.seenAt > livemap.sightingTTL then livemap.sightings[key] = nil end
  end
end

function livemap.snapshot()
  local now = RH.dcs.wallclock()
  livemap.recordSightings(now)
  local snap = {
    campaign = RH.config.campaignName,
    theatre = RH.dcs.theatre(),
    generatedAt = now,
    missionTime = math.floor(RH.dcs.now()),
    timeOfDay = math.floor(RH.dcs.absTime() % 86400),
    restartIn = math.max(0, math.floor(RH.config.restartHours * 3600 - RH.dcs.now())),
    factories = {}, outposts = {}, farps = {}, mashes = {}, blueZones = {},
    threats = {}, redAir = {}, players = {}, csar = {}, marks = {}, convoy = nil,
  }

  for _, f in ipairs(RH.factories and RH.factories.list or {}) do
    local status = RH.factories.status(f)
    if f.revealed or status ~= "active" then
      table.insert(snap.factories, withLL({ name = f.label, status = status }, f.point))
    end
  end
  for _, o in ipairs(RH.outposts and RH.outposts.list or {}) do
    table.insert(snap.outposts, withLL({
      name = o.label, status = RH.outposts.status(o), color = o.color, radius = RH.config.outpost.contestedRadius,
    }, o.point))
  end
  for _, farp in ipairs(RH.logistics.farps()) do
    table.insert(snap.farps, withLL({ name = farp.name, lc = farp.lc, crates = farp.crates, built = farp.built }, farp))
  end
  for _, name in ipairs(util.keys(RH.state.mashes)) do
    local m = RH.state.mashes[name]
    table.insert(snap.mashes, withLL({ name = name, patients = m.patients, capacity = RH.config.mash.capacity }, m))
  end
  for _, z in ipairs(RH.logistics.blueZones()) do
    table.insert(snap.blueZones, withLL({ name = z.name, radius = z.radius }, z.point))
  end
  for _, s in pairs(livemap.sightings) do
    table.insert(snap.threats, withLL({ kind = s.aa and "aa" or "ground", type = s.typeName, age = now - s.seenAt }, s.pos))
  end
  for _, a in ipairs(RH.dcs.redAircraft()) do
    table.insert(snap.redAir, withLL({ kind = a.kind, type = a.typeName, heading = a.heading }, a.pos))
  end
  for _, p in ipairs(RH.dcs.players()) do
    table.insert(snap.players, withLL({
      name = p.name, type = p.typeName, coalition = p.coalition, heading = p.heading, altitude = p.altitude,
      lives = RH.lives and not RH.lives.isUnlimited(p.typeName) and RH.lives.remaining(p.name) or nil,
    }, p.pos))
  end
  for _, c in ipairs(RH.csar and RH.csar.list() or {}) do
    table.insert(snap.csar, withLL({ name = c.name, description = c.description }, c.pos))
  end
  for _, m in ipairs(RH.dcs.marks()) do
    table.insert(snap.marks, withLL({ text = m.text }, m.pos))
  end
  local c = RH.convoy and RH.convoy.active
  if c then
    local pos = RH.dcs.groupPosition(c.trucks)
    if pos then
      snap.convoy = withLL({ from = c.origin, to = c.destination, underAttack = c.halted }, pos)
    end
  end
  return snap
end

function livemap.export()
  local snap = livemap.snapshot()
  RH.dcs.writeFile(RH.persistence.path("livemap.json"), util.toJSON(snap))
  return snap
end

function livemap.start()
  RH.every(RH.config.liveMapInterval, livemap.export, 20)
end

return livemap
