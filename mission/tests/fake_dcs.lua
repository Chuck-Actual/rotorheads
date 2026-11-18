-- In-memory stand-in for RH.dcs so campaign logic can be tested outside DCS.
local util = RH.util

local fake = {}

function fake.new()
  local w = {
    t = 0, wall = 1700000000,
    zones = {}, statics = {}, groups = {}, units = {}, players = {}, airbases = {},
    messages = {}, unitMessages = {}, drawings = {}, files = {}, notifications = {}, smokes = {},
    illuminations = {}, destroyedUnits = {}, destroyedWeapons = {}, farpsSpawned = {}, mashesSpawned = {},
    jobs = {}, spawnCount = 0, missingTemplates = {},
  }
  local dcs = {}

  function dcs.now() return w.t end
  function dcs.absTime() return 8 * 3600 + w.t end
  function dcs.wallclock() return w.wall end
  function dcs.filesEnabled() return true end
  function dcs.theatre() return "Syria" end
  function dcs.schedule(fn, delay) table.insert(w.jobs, { at = w.t + delay, fn = fn }) end
  function dcs.installEventHandler() end
  function dcs.saveDir() return "save" end
  function dcs.savePath(file) return "save/" .. file end
  function dcs.readFile(path) return w.files[path] end
  function dcs.writeFile(path, s) w.files[path] = s return true end
  function dcs.notify(kind, data) table.insert(w.notifications, { kind = kind, data = data }) end

  function dcs.zonesWithPrefix(prefix)
    local out = {}
    for _, z in ipairs(w.zones) do
      if util.startsWith(z.name, prefix) then table.insert(out, z) end
    end
    return out
  end
  function dcs.zoneExists(name)
    for _, z in ipairs(w.zones) do if z.name == name then return true end end
    return false
  end
  function dcs.nearestZone(prefix, point)
    local best, bd
    for _, z in ipairs(dcs.zonesWithPrefix(prefix)) do
      local d = util.distance(z.point, point)
      if not bd or d < bd then best, bd = z, d end
    end
    return best
  end

  function dcs.staticObjects()
    local out = {}
    for name, s in pairs(w.statics) do
      if s.alive then
        table.insert(out, {
          name = name,
          typeName = s.typeName or "",
          display = s.display or "",
          side = s.side,
          x = s.point.x,
          y = s.point.y,
        })
      end
    end
    return out
  end
  function dcs.staticsInZone(zone, side)
    local out = {}
    for name, s in pairs(w.statics) do
      if s.side == side and util.distance(s.point, zone.point) <= (zone.radius > 0 and zone.radius or 500) then
        table.insert(out, { name = name, country = 0, data = {} })
      end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end
  function dcs.isStaticAlive(name) return w.statics[name] ~= nil and w.statics[name].alive end
  function dcs.respawnStatic(info) w.statics[info.name].alive = true end
  function dcs.destroyStatic(name) if w.statics[name] then w.statics[name].alive = false end end

  local function unitsOf(side, point, radius, groundOnly)
    local out = {}
    for _, u in ipairs(w.units) do
      if u.side == side and u.alive ~= false and (not groundOnly or u.ground)
        and (not point or util.distance(u.pos, point) <= radius) then
        table.insert(out, { name = u.name, typeName = u.typeName or "Unit", pos = u.pos, isAA = u.isAA })
      end
    end
    for name, g in pairs(w.groups) do
      if g.side == side and g.alive > 0 and (not point or util.distance(g.pos, point) <= radius) then
        table.insert(out, { name = name .. "-1", typeName = g.template, pos = g.pos, isAA = false })
      end
    end
    return out
  end
  function dcs.groundUnitsInRadius(side, point, radius) return unitsOf(side, point, radius, true) end
  function dcs.unitsInRadius(side, point, radius) return unitsOf(side, point, radius, false) end

  function dcs.spawnGroup(template, point, alias)
    if w.missingTemplates[template] then return nil end
    w.spawnCount = w.spawnCount + 1
    local name = string.format("%s#%03d", alias, w.spawnCount)
    local side = template:find("RED") and "red" or (template:find("TRUCK") and "neutral" or "blue")
    w.groups[name] = { template = template, alias = alias, pos = util.toVec2(point), alive = 4, side = side, kind = "ground" }
    return name
  end
  function dcs.routeGroup(name, point) if w.groups[name] then w.groups[name].routedTo = util.toVec2(point); w.groups[name].held = false end end
  function dcs.holdGroup(name) if w.groups[name] then w.groups[name].held = true end end
  function dcs.groupAliveCount(name) return w.groups[name] and w.groups[name].alive or 0 end
  function dcs.groupPosition(name) return w.groups[name] and w.groups[name].pos end
  function dcs.groupLanded(name) return w.groups[name] and w.groups[name].landed or false end
  function dcs.destroyGroup(name) if w.groups[name] then w.groups[name].alive = 0 end end
  function dcs.destroyUnit(name) table.insert(w.destroyedUnits, name) end
  function dcs.destroyWeapon(weapon) table.insert(w.destroyedWeapons, weapon) end

  local function spawnAir(template, from, alias, kind)
    local name = dcs.spawnGroup(template, from, alias)
    if name then w.groups[name].kind = kind; w.groups[name].side = "red" end
    return name
  end
  function dcs.spawnHeloLanding(template, from, to, alias)
    local n = spawnAir(template, from, alias, "halo")
    if n then w.groups[n].routedTo = util.toVec2(to) end
    return n
  end
  function dcs.spawnAttackHelo(template, from, target, alias) return spawnAir(template, from, alias, "havoc") end
  function dcs.spawnInterceptor(template, from, target, alias) return spawnAir(template, from, alias, "fighter") end

  function dcs.players() return w.players end
  function dcs.redAircraft()
    local out = {}
    for _, g in pairs(w.groups) do
      if g.alive > 0 and (g.kind == "havoc" or g.kind == "halo" or g.kind == "fighter") then
        table.insert(out, { kind = g.kind, typeName = g.template, pos = g.pos, heading = 0 })
      end
    end
    return out
  end
  function dcs.airbases() return w.airbases end
  function dcs.nearBase(pos, radius)
    for _, ab in ipairs(w.airbases) do if util.distance(ab.point, pos) <= radius then return true end end
    for _, f in pairs(RH.state.farps) do if util.distance(f, pos) <= radius then return true end end
    return false
  end
  function dcs.lineOfSight() return true end
  function dcs.toLatLon(p) return 35 + p.x / 111000, 36 + p.y / 91000 end
  function dcs.marks() return {} end

  function dcs.smoke(point, color) table.insert(w.smokes, { point = point, color = color }) end
  function dcs.bigSmoke(point) table.insert(w.smokes, { point = point, color = "black" }) end
  function dcs.illumination(point) table.insert(w.illuminations, point) end
  function dcs.drawCircle(id, side, point, radius, line, fill, text)
    w.drawings[id] = { side = side, point = point, radius = radius, line = line, fill = fill, text = text }
  end
  function dcs.drawLabel(id, side, point, text, fontSize, markId)
    local prev = w.drawings[id]
    local kept = markId or (prev and prev.markId)
    if not kept then
      dcs.nextDrawId = (dcs.nextDrawId or 70000) + 1
      kept = dcs.nextDrawId
    end
    w.drawings[id] = { side = side, point = point, text = text, fontSize = fontSize, markId = kept, kind = "label" }
  end
  function dcs.removeDrawing(id) w.drawings[id] = nil end
  function dcs.message(side, text) table.insert(w.messages, { side = side, text = text }) end
  function dcs.messageToUnit(unit, text) table.insert(w.unitMessages, { unit = unit, text = text }) end
  function dcs.spawnFarp(farp) table.insert(w.farpsSpawned, farp.name) end
  function dcs.spawnMash(name) table.insert(w.mashesSpawned, name) end

  -- Test helpers -----------------------------------------------------------------

  function w.advance(seconds, step)
    step = step or 1
    local target = w.t + seconds
    while w.t < target do
      w.t = math.min(target, w.t + step)
      local due = {}
      local keep = {}
      for _, job in ipairs(w.jobs) do
        if job.at <= w.t then table.insert(due, job) else table.insert(keep, job) end
      end
      w.jobs = keep
      table.sort(due, function(a, b) return a.at < b.at end)
      for _, job in ipairs(due) do
        local nextAt = job.fn()
        if nextAt then table.insert(w.jobs, { at = nextAt, fn = job.fn }) end
      end
    end
  end

  function w.lastMessage()
    local m = w.messages[#w.messages]
    return m and m.text or ""
  end

  function w.anyMessage(pattern)
    for _, m in ipairs(w.messages) do if m.text:find(pattern) then return true end end
    for _, m in ipairs(w.unitMessages) do if m.text:find(pattern) then return true end end
    return false
  end

  function w.addUnit(side, pos, opts)
    opts = opts or {}
    local u = { name = opts.name or ("u" .. (#w.units + 1)), side = side, pos = pos, ground = opts.ground ~= false, isAA = opts.isAA, typeName = opts.typeName }
    table.insert(w.units, u)
    return u
  end

  w.dcs = dcs
  return w
end

return fake
