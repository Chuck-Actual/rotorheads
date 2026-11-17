RH = RH or {}

local util = RH.util

-- The only module that talks to the DCS scripting API and MOOSE directly.
-- Game logic calls RH.dcs.*; the test suite swaps this table for a fake.
local dcs = { spawners = {}, drawIds = {}, nextDrawId = 70000 }
RH.dcs = dcs

local SIDES = { [0] = "neutral", [1] = "red", [2] = "blue" }
local SIDE_IDS = { neutral = 0, red = 1, blue = 2, all = -1 }

local function vec3(p, alt)
  local v = util.toVec2(p)
  return { x = v.x, y = alt or land.getHeight({ x = v.x, y = v.y }), z = v.y }
end

-- Time, files ------------------------------------------------------------------

function dcs.now() return timer.getTime() end
function dcs.absTime() return timer.getAbsTime() end
function dcs.filesEnabled() return io ~= nil and lfs ~= nil and os ~= nil end
function dcs.wallclock()
  if os then return os.time() end
  return math.floor(timer.getAbsTime())
end
function dcs.theatre() return env.mission and env.mission.theatre or "Unknown" end

function dcs.schedule(fn, delay)
  timer.scheduleFunction(function(_, t)
    local nextAt = fn()
    return nextAt
  end, nil, timer.getTime() + delay)
end

function dcs.saveDir()
  if not dcs.filesEnabled() then return nil end
  local dir = lfs.writedir() .. RH.config.saveFolder
  lfs.mkdir(dir)
  return dir
end

function dcs.savePath(file)
  local dir = dcs.saveDir()
  if not dir then return nil end
  return dir .. "\\" .. file
end

function dcs.readFile(path)
  if not path or not io then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function dcs.writeFile(path, contents)
  if not path or not io then return false end
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return false end
  f:write(contents)
  f:close()
  os.remove(path)
  return os.rename(tmp, path) ~= nil
end

function dcs.notify(kind, data)
  local path = dcs.savePath("events.jsonl")
  if not path then return end
  local f = io.open(path, "a")
  if not f then return end
  f:write(util.toJSON({ t = os.time(), kind = kind, data = data }), "\n")
  f:close()
end

-- Events -----------------------------------------------------------------------

local EVENT_NAMES = {
  [world.event.S_EVENT_BIRTH] = "birth",
  [world.event.S_EVENT_DEAD] = "dead",
  [world.event.S_EVENT_UNIT_LOST] = "dead",
  [world.event.S_EVENT_PILOT_DEAD] = "pilotDead",
  [world.event.S_EVENT_EJECTION] = "ejection",
  [world.event.S_EVENT_CRASH] = "crash",
  [world.event.S_EVENT_PLAYER_LEAVE_UNIT] = "playerLeave",
  [world.event.S_EVENT_KILL] = "kill",
  [world.event.S_EVENT_SHOT] = "shot",
  [world.event.S_EVENT_LAND] = "land",
  [world.event.S_EVENT_MARK_ADDED] = "markAdded",
  [world.event.S_EVENT_MARK_CHANGE] = "markChanged",
  [world.event.S_EVENT_MARK_REMOVED] = "markRemoved",
}

local UNIT_CATEGORIES = { [0] = "plane", [1] = "helicopter", [2] = "ground", [3] = "ship", [4] = "structure" }

local function describe(obj)
  if not obj or not obj.isExist or not obj:isExist() then return nil end
  local info = { name = obj:getName(), typeName = obj:getTypeName(), coalition = SIDES[obj:getCoalition()] }
  local cat = Object.getCategory(obj)
  if cat == Object.Category.UNIT then
    info.category = UNIT_CATEGORIES[obj:getDesc().category]
    info.playerName = obj.getPlayerName and obj:getPlayerName() or nil
    local g = obj:getGroup()
    info.groupName = g and g:getName()
    info.groupId = g and g:getID()
    info.inAir = obj:inAir()
  elseif cat == Object.Category.STATIC then
    info.category = "static"
  end
  local ok, p = pcall(obj.getPoint, obj)
  if ok and p then info.pos = p end
  return info
end

function dcs.normalize(event)
  local id = EVENT_NAMES[event.id]
  if not id then return nil end
  local e = { id = id, time = event.time }
  local ok, init = pcall(describe, event.initiator)
  init = ok and init or nil
  if init then
    e.initiatorName, e.initiatorType, e.initiatorCoalition = init.name, init.typeName, init.coalition
    e.initiatorCategory, e.playerName, e.groupId = init.category, init.playerName, init.groupId
    e.pos, e.initiatorPos, e.onGround = init.pos, init.pos, init.inAir == false
  elseif event.initiator and event.initiator.getName then
    local okName, name = pcall(event.initiator.getName, event.initiator)
    if okName then e.initiatorName = name end
  end
  if id == "kill" then
    local okT, target = pcall(describe, event.target)
    if okT and target then
      e.targetName, e.targetType, e.targetCoalition, e.targetCategory = target.name, target.typeName, target.coalition, target.category
      e.targetIsCsarPilot = RH.csar and RH.csar.isDownedPilot and RH.csar.isDownedPilot(target.groupName) or false
    end
  elseif id == "shot" then
    e.weapon = event.weapon
  elseif id == "land" and event.place then
    local okP, placeName = pcall(event.place.getName, event.place)
    if okP then e.place = placeName end
    local okD, desc = pcall(event.place.getDesc, event.place)
    if okD and desc then
      e.placeKind = ({ [0] = "airdrome", [1] = "helipad", [2] = "ship" })[desc.category]
    end
  elseif id == "markAdded" or id == "markChanged" or id == "markRemoved" then
    e.text, e.pos, e.markId, e.coalition = event.text, event.pos, event.idx, SIDES[event.coalition] or "all"
  end
  return e
end

function dcs.installEventHandler(dispatch)
  world.addEventHandler({
    onEvent = function(_, event)
      local ok, e = pcall(dcs.normalize, event)
      if ok and e then dispatch(e) end
    end,
  })
end

-- Zones and statics -------------------------------------------------------------

function dcs.zonesWithPrefix(prefix)
  local out = {}
  for _, z in ipairs(env.mission.triggers.zones or {}) do
    if util.startsWith(z.name, prefix) then
      table.insert(out, { name = z.name, point = { x = z.x, y = z.y }, radius = z.radius or 0 })
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function dcs.zoneExists(name)
  return trigger.misc.getZone(name) ~= nil or Group.getByName(name) ~= nil
end

function dcs.nearestZone(prefix, point)
  local best, bestDist
  for _, z in ipairs(dcs.zonesWithPrefix(prefix)) do
    local d = util.distance(z.point, point)
    if not bestDist or d < bestDist then best, bestDist = z, d end
  end
  return best
end

function dcs.staticObjects()
  local out = {}
  if not coalition or not coalition.getStaticObjects then return out end
  for _, side in ipairs({ coalition.side.BLUE, coalition.side.NEUTRAL, coalition.side.RED }) do
    local ok, list = pcall(coalition.getStaticObjects, side)
    if ok and list then
      for _, s in ipairs(list) do
        if s and s:isExist() then
          local p = s:getPoint()
          local desc = s.getDesc and s:getDesc() or nil
          table.insert(out, {
            name = s:getName(),
            typeName = s:getTypeName(),
            display = desc and (desc.displayName or desc.typeName) or "",
            x = p.x,
            y = p.z,
          })
        end
      end
    end
  end
  return out
end

function dcs.staticsInZone(zone, side)
  local out = {}
  local radius = zone.radius > 0 and zone.radius or 500
  for _, s in ipairs(coalition.getStaticObjects(SIDE_IDS[side])) do
    local p = s:getPoint()
    if util.distance(p, zone.point) <= radius then
      local tpl = _DATABASE and _DATABASE.GetStaticUnitTemplate and _DATABASE:GetStaticUnitTemplate(s:getName())
      table.insert(out, {
        name = s:getName(),
        country = s:getCountry(),
        data = tpl and UTILS.DeepCopy(tpl) or { type = s:getTypeName(), x = p.x, y = p.z, heading = 0 },
      })
    end
  end
  return out
end

function dcs.isStaticAlive(name)
  local s = StaticObject.getByName(name)
  return s ~= nil and s:isExist() and s:getLife() > 0
end

function dcs.respawnStatic(info)
  local data = UTILS.DeepCopy(info.data)
  data.name = info.name
  data.dead = false
  data.unitId = nil
  coalition.addStaticObject(info.country, data)
end

function dcs.destroyStatic(name)
  local s = StaticObject.getByName(name)
  if s and s:isExist() then s:destroy() end
end

-- Units and groups ---------------------------------------------------------------

local function unitInfo(u)
  local p = u:getPoint()
  return {
    name = u:getName(),
    typeName = u:getTypeName(),
    pos = { x = p.x, y = p.z },
    pos3 = { x = p.x, y = p.y + 2, z = p.z },
    isAA = u:hasAttribute("Air Defence"),
  }
end

local function collect(side, point, radius, groundOnly)
  local out = {}
  local sideId = SIDE_IDS[side]
  if not point then
    local cats = groundOnly and { Group.Category.GROUND } or { Group.Category.GROUND, Group.Category.HELICOPTER, Group.Category.AIRPLANE }
    for _, cat in ipairs(cats) do
      for _, g in ipairs(coalition.getGroups(sideId, cat)) do
        for _, u in ipairs(g:getUnits()) do
          if u:isExist() and u:getLife() > 0 then table.insert(out, unitInfo(u)) end
        end
      end
    end
    return out
  end
  local volume = { id = world.VolumeType.SPHERE, params = { point = vec3(point), radius = radius } }
  world.searchObjects(Object.Category.UNIT, volume, function(u)
    if u:getCoalition() == sideId and u:getLife() > 0 then
      local cat = u:getDesc().category
      if not groundOnly or cat == Unit.Category.GROUND_UNIT then table.insert(out, unitInfo(u)) end
    end
    return true
  end)
  return out
end

function dcs.groundUnitsInRadius(side, point, radius) return collect(side, point, radius, true) end
function dcs.unitsInRadius(side, point, radius) return collect(side, point, radius, false) end

local function spawner(template, alias)
  local key = template .. "|" .. alias
  if not dcs.spawners[key] then
    if not GROUP:FindByName(template) then
      util.log("missing template group %s", template)
      return nil
    end
    dcs.spawners[key] = SPAWN:NewWithAlias(template, alias)
  end
  return dcs.spawners[key]
end

function dcs.spawnGroup(template, point, alias)
  local sp = spawner(template, alias)
  if not sp then return nil end
  local g = sp:SpawnFromVec2(util.toVec2(point))
  return g and g:GetName()
end

local function airSpawn(template, alias, from, altitude)
  local sp = spawner(template, alias)
  if not sp then return nil end
  return sp:SpawnFromVec3(vec3(from, land.getHeight(util.toVec2(from)) + altitude))
end

function dcs.routeGroup(groupName, point, onRoad)
  local g = GROUP:FindByName(groupName)
  if not g or not g:IsAlive() then return end
  local to = COORDINATE:NewFromVec2(util.toVec2(point))
  if onRoad then g:RouteGroundOnRoad(to, 40, 1, "Off Road") else g:RouteGroundTo(to, 20, "Off Road", 1) end
end

function dcs.holdGroup(groupName)
  local g = GROUP:FindByName(groupName)
  if g and g:IsAlive() then g:SetTask(g:TaskHold(), 1) end
end

function dcs.groupAliveCount(groupName)
  local g = Group.getByName(groupName)
  if not g or not g:isExist() then return 0 end
  local n = 0
  for _, u in ipairs(g:getUnits()) do
    if u:isExist() and u:getLife() > 0 then n = n + 1 end
  end
  return n
end

function dcs.groupPosition(groupName)
  local g = Group.getByName(groupName)
  if not g or not g:isExist() then return nil end
  for _, u in ipairs(g:getUnits()) do
    if u:isExist() then return util.toVec2(u:getPoint()) end
  end
end

function dcs.groupLanded(groupName)
  local g = Group.getByName(groupName)
  if not g or not g:isExist() then return false end
  local u = g:getUnit(1)
  return u ~= nil and u:isExist() and not u:inAir()
end

function dcs.destroyGroup(groupName)
  local g = Group.getByName(groupName)
  if g and g:isExist() then g:destroy() end
end

function dcs.destroyUnit(unitName)
  local u = Unit.getByName(unitName)
  if u and u:isExist() then u:destroy() end
end

function dcs.destroyWeapon(weapon)
  if weapon and weapon.isExist and weapon:isExist() then weapon:destroy() end
end

function dcs.spawnHeloLanding(template, from, to, alias)
  local g = airSpawn(template, alias, from, 150)
  if not g then return nil end
  local dest = COORDINATE:NewFromVec2(util.toVec2(to))
  local route = {
    COORDINATE:NewFromVec2(util.toVec2(from)):SetAltitude(150):WaypointAirTurningPoint("RADIO", 220, {}, "Depart"),
    dest:SetAltitude(150):WaypointAirTurningPoint("RADIO", 220, { g:TaskLandAtVec2(util.toVec2(to), 900) }, "Land"),
  }
  g:Route(route, 1)
  return g:GetName()
end

function dcs.spawnAttackHelo(template, from, target, alias)
  local g = airSpawn(template, alias, from, 100)
  if not g then return nil end
  local dest = COORDINATE:NewFromVec2(util.toVec2(target)):SetAltitude(100)
  local engage = g:EnRouteTaskEngageTargetsInZone(util.toVec2(target), 6000, { "Helicopters", "Ground Units" })
  g:Route({ dest:WaypointAirTurningPoint("RADIO", 250, { engage }, "Attack") }, 1)
  return g:GetName()
end

function dcs.spawnInterceptor(template, from, targetUnitName, alias)
  local target = Unit.getByName(targetUnitName)
  if not target then return nil end
  local g = airSpawn(template, alias, from, 6000)
  if not g then return nil end
  local dest = COORDINATE:NewFromVec3(target:getPoint()):SetAltitude(6000)
  local engage = g:EnRouteTaskEngageTargets(60000, { "Planes" })
  g:Route({ dest:WaypointAirTurningPoint("BARO", 900, { engage }, "Intercept") }, 1)
  return g:GetName()
end

-- Players, airbases, sensors -------------------------------------------------------

function dcs.players()
  local out = {}
  for _, side in ipairs({ 1, 2 }) do
    for _, u in ipairs(coalition.getPlayers(side)) do
      if u:isExist() then
        local p = u:getPoint()
        local pos = u:getPosition()
        table.insert(out, {
          name = u:getPlayerName(),
          unitName = u:getName(),
          typeName = u:getTypeName(),
          category = UNIT_CATEGORIES[u:getDesc().category],
          coalition = SIDES[side],
          pos = { x = p.x, y = p.z },
          pos3 = p,
          altitude = math.floor(p.y),
          heading = math.floor(math.deg(math.atan2(pos.x.z, pos.x.x)) % 360),
          onGround = not u:inAir(),
        })
      end
    end
  end
  return out
end

function dcs.redAircraft()
  local out = {}
  for _, cat in ipairs({ Group.Category.HELICOPTER, Group.Category.AIRPLANE }) do
    for _, g in ipairs(coalition.getGroups(1, cat)) do
      for _, u in ipairs(g:getUnits()) do
        if u:isExist() and u:inAir() then
          local t = u:getTypeName()
          local kind = cat == Group.Category.AIRPLANE and "fighter" or "helo"
          if t:find("Mi%-28") then kind = "havoc" elseif t:find("Mi%-26") then kind = "halo" end
          local p, pos = u:getPoint(), u:getPosition()
          table.insert(out, {
            kind = kind, typeName = t, pos = { x = p.x, y = p.z },
            heading = math.floor(math.deg(math.atan2(pos.x.z, pos.x.x)) % 360),
          })
        end
      end
    end
  end
  return out
end

local function longestRunway(airbase)
  if not airbase.getRunways then return 0 end
  local ok, runways = pcall(function() return airbase:getRunways() end)
  if not ok or type(runways) ~= "table" then return 0 end
  local longest = 0
  for _, runway in pairs(runways) do
    local len = runway.length or runway.Length or 0
    if type(len) == "number" and len > longest then longest = len end
  end
  return longest
end

function dcs.airbases()
  local out = {}
  for _, ab in ipairs(world.getAirbases()) do
    local p = ab:getPoint()
    local name = ab:getName()
    local kind = ({ [0] = "airdrome", [1] = "helipad", [2] = "ship" })[ab:getDesc().category] or "helipad"
    -- HS02 and the other helicopter pads are stored as airdromes, but they are not logistics airfields.
    local logistics = kind == "airdrome"
    local runway = longestRunway(ab)
    if runway > 0 and runway < 1000 then logistics = false end
    if string.match(name, "^HS%d") then logistics = false end
    table.insert(out, {
      name = name,
      point = { x = p.x, y = p.z },
      kind = kind,
      coalition = SIDES[ab:getCoalition()],
      logistics = logistics,
    })
  end
  return out
end

function dcs.nearBase(pos, radius)
  for _, ab in ipairs(dcs.airbases()) do
    if ab.coalition ~= "red" and util.distance(ab.point, pos) <= (ab.kind == "airdrome" and radius * 4 or radius) then return true end
  end
  for _, farp in pairs(RH.state.farps) do
    if util.distance(farp, pos) <= radius then return true end
  end
  return false
end

function dcs.lineOfSight(a, b)
  local p = a.z and a or vec3(a, land.getHeight(util.toVec2(a)) + 2)
  local q = b.z and b or vec3(b, land.getHeight(util.toVec2(b)) + 2)
  return land.isVisible(p, q)
end

function dcs.toLatLon(point)
  local lat, lon = coord.LOtoLL(vec3(point, 0))
  return lat, lon
end

function dcs.marks()
  local out = {}
  for _, m in ipairs(world.getMarkPanels() or {}) do
    if m.text and m.text ~= "" and (m.coalition == -1 or m.coalition == 2) then
      table.insert(out, { text = m.text, pos = util.toVec2(m.pos) })
    end
  end
  return out
end

-- Effects, drawings, messages --------------------------------------------------------

function dcs.smoke(point, color)
  trigger.action.smoke(vec3(point), color)
end

function dcs.bigSmoke(point, _kind)
  local name = "rh-smoke-" .. math.random(1, 1e6)
  trigger.action.effectSmokeBig(vec3(point), 7, 0.6, name)
  RH.after(600, function() trigger.action.effectSmokeStop(name) end)
end

function dcs.illumination(point, altitude)
  local ground = land.getHeight(util.toVec2(point))
  trigger.action.illuminationBomb(vec3(point, ground + altitude), 1000000)
end

function dcs.removeDrawing(id)
  local ids = dcs.drawIds[id]
  if not ids then return end
  for _, n in ipairs(ids) do trigger.action.removeMark(n) end
  dcs.drawIds[id] = nil
end

function dcs.drawCircle(id, side, point, radius, lineColor, fillColor, text)
  dcs.removeDrawing(id)
  local sideId = SIDE_IDS[side] or -1
  local circleId, textId = dcs.nextDrawId, dcs.nextDrawId + 1
  dcs.nextDrawId = dcs.nextDrawId + 2
  trigger.action.circleToAll(sideId, circleId, vec3(point), radius, lineColor, fillColor, 1, true, "")
  local ids = { circleId }
  if text then
    local labelPoint = { x = util.toVec2(point).x + radius * 0.7, y = util.toVec2(point).y }
    trigger.action.textToAll(sideId, textId, vec3(labelPoint), { 1, 1, 1, 1 }, { 0, 0, 0, 0.4 }, 12, true, text)
    table.insert(ids, textId)
  end
  dcs.drawIds[id] = ids
end

function dcs.message(side, text, duration)
  if side == "all" then
    trigger.action.outText(text, duration or 10)
  else
    trigger.action.outTextForCoalition(SIDE_IDS[side], text, duration or 10)
  end
end

function dcs.messageToUnit(unitName, text, duration)
  local u = Unit.getByName(unitName)
  if u and u:isExist() then
    trigger.action.outTextForUnit(u:getID(), text, duration or 10)
  end
end

-- Construction -------------------------------------------------------------------

function dcs.spawnVehicle(name, typeName, point, headingDeg)
  local vec = util.toVec2(point)
  local heading = math.rad(headingDeg or 0)
  local groupData = {
    visible = false,
    hidden = false,
    task = "Ground Nothing",
    name = name,
    x = vec.x,
    y = vec.y,
    start_time = 0,
    route = { points = { { x = vec.x, y = vec.y, type = "Off Road", action = "Off Road", speed = 0 } } },
    units = {
      {
        type = typeName,
        name = name,
        skill = "Average",
        x = vec.x,
        y = vec.y,
        heading = heading,
        playerCanDrive = false,
        transportable = { randomTransportable = false },
      },
    },
  }
  return coalition.addGroup(country.id.USA, Group.Category.GROUND, groupData)
end

function dcs.spawnFarp(farp)
  local pad = COORDINATE:NewFromVec2(util.toVec2(farp))
  local helipad = SPAWNSTATIC:NewFromType("FARP", "Heliports", country.id.USA)
  helipad:InitShape("FARPS")
  -- Dynamic spawn on, hot start off. The warehouse is created empty and then filled from the save.
  helipad:InitFARP(CALLSIGN.FARP.Berlin, farp.freq or 127.5, radio.modulation.AM, true, false)
  helipad:SpawnFromCoordinate(pad, 0, farp.name)
  for _, piece in ipairs(RH.config.farp.services or {}) do
    local spot = pad:Translate(piece.dist or 40, piece.bearing or 0)
    local objectName = farp.name .. " " .. piece.label
    local ok, err = pcall(function()
      if piece.kind == "vehicle" then
        dcs.spawnVehicle(objectName, piece.typeName, spot:GetVec2(), piece.bearing)
      else
        local obj = SPAWNSTATIC:NewFromType(piece.typeName, piece.category or "Fortifications", country.id.USA)
        if piece.shape then obj:InitShape(piece.shape) end
        obj:SpawnFromCoordinate(spot, piece.bearing or 0, objectName)
      end
    end)
    if not ok then util.log("FARP piece %s failed: %s", objectName, tostring(err)) end
  end
  if not STORAGE or not STORAGE.New then return end
  local ok, wh = pcall(STORAGE.New, STORAGE, farp.name)
  if not ok or not wh then return end
  for key, amount in pairs(farp.liquids or {}) do
    local id = STORAGE.Liquid and STORAGE.Liquid[key]
    if id and type(amount) == "number" and amount > 0 and wh.SetLiquid then wh:SetLiquid(id, amount) end
  end
  for item, amount in pairs(farp.ammoItems or {}) do
    if type(amount) == "number" and amount > 0 and wh.SetItem then wh:SetItem(item, amount) end
  end
end

-- Read the live warehouse so the next restart spawns the same fuel and ammo.
function dcs.captureFarpStock(farp)
  if not STORAGE or not STORAGE.New then return false end
  local ok, wh = pcall(STORAGE.New, STORAGE, farp.name)
  if not ok or not wh or not wh.GetLiquidAmount then return false end
  local liquids = {}
  for key, id in pairs(STORAGE.Liquid or {}) do
    local okN, n = pcall(function() return wh:GetLiquidAmount(id) end)
    if okN and type(n) == "number" then liquids[key] = n end
  end
  if next(liquids) then farp.liquids = liquids end
  local items = {}
  local weapons = ENUMS and ENUMS.Storage and ENUMS.Storage.weapons
  if weapons and wh.GetItemAmount then
    for _, group in pairs(weapons) do
      if type(group) == "table" then
        for _, item in pairs(group) do
          if type(item) == "string" then
            local okN, n = pcall(function() return wh:GetItemAmount(item) end)
            if okN and type(n) == "number" and n > 0 then items[item] = n end
          end
        end
      end
    end
  end
  farp.ammoItems = items
  return true
end

function dcs.spawnMash(name, point)
  local c = COORDINATE:NewFromVec2(util.toVec2(point))
  local tent = SPAWNSTATIC:NewFromType("Tent04", "Fortifications", country.id.USA)
  tent:InitShape("M92_Tent04")
  tent:SpawnFromCoordinate(c, 0, name .. " tent")
end

return dcs
