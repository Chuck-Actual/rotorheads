RH = RH or {}

local util = RH.util

-- MOOSE CSAR setup plus the Rotorheads extras: lives returned on rescue, MASH capacity of 30,
-- MASH -> airfield transport tasks, stranded-crew CSARs, and the -extract marker.
local csar = { instance = nil, manifests = {} }
RH.csar = csar

local function pilotRecord(groupName)
  if not csar.instance then return nil end
  for _, p in pairs(csar.instance.downedPilots or {}) do
    if p.name == groupName then return p end
  end
end

function csar.isDownedPilot(groupName)
  return groupName ~= nil and pilotRecord(groupName) ~= nil
end

function csar.create()
  local inst = CSAR:New(coalition.side.BLUE, "RH_TPL_DOWNED_PILOT", "RH CSAR")
  inst.useprefix = false
  inst.allowFARPRescue = true
  inst.FARPRescueDistance = 500
  inst.mashprefix = { RH.config.prefixes.mash }
  inst.pilotRuntoExtractPoint = true
  inst.extractDistance = 500
  inst.loadDistance = 75
  inst.immortalcrew = true
  inst.invisiblecrew = false
  inst.PilotWeight = RH.config.troopWeight
  inst.coordtype = 2
  inst.enableForAI = false
  inst.csarOncrash = true
  inst.autosmoke = false
  inst.EnableMenuSmokeMASH = true
  inst.enableLoadSave = RH.dcs.filesEnabled()
  inst.saveinterval = RH.config.saveInterval
  inst.filepath = RH.dcs.saveDir()
  inst.filename = "csar.csv"

  for typeName, a in pairs(RH.config.airframes) do
    CSAR.AircraftType[typeName] = a.csar
  end

  csar.instance = inst
  csar.installHooks(inst)
  inst:__Start(2)
  if inst.enableLoadSave then inst:__Load(10) end
  return inst
end

function csar.installHooks(inst)
  function inst:OnAfterBoarded(From, Event, To, Heliname, Woundedgroupname, Description)
    local rec = pilotRecord(Woundedgroupname)
    local player = rec and (rec.player or rec.desc) or Description
    csar.manifests[Heliname] = csar.manifests[Heliname] or {}
    table.insert(csar.manifests[Heliname], player)
  end

  function inst:OnAfterRescued(From, Event, To, HeliUnit, HeliName, PilotsSaved)
    local manifest = csar.manifests[HeliName] or {}
    csar.manifests[HeliName] = nil
    local pos = HeliUnit and HeliUnit:GetVec2()
    local mashName = pos and RH.logistics.mashAt(pos, 600)
    if mashName then
      RH.logistics.admitPatients(mashName, #manifest)
      csar.refreshMashAvailability()
    end
    for _, player in ipairs(manifest) do
      if player and RH.state.lives[player] then RH.lives.restore(player, 1) end
    end
  end
end

-- A full MASH stops accepting rescues until a transport task empties it.
function csar.refreshMashAvailability()
  local inst = csar.instance
  if not inst or not inst.mash then return end
  for name in pairs(RH.state.mashes) do
    local group = GROUP:FindByName(name)
    if group then
      if RH.logistics.mashFull(name) then
        inst.mash:Remove(name, true)
      else
        inst.mash:Add(name, group)
      end
    end
  end
end

function csar.spawnStranded(pos, player, typeName)
  if not csar.instance then return end
  local zone = ZONE_RADIUS:New("RH_STRANDED_" .. math.random(1, 1e6), util.toVec2(pos), 30, true)
  csar.instance:SpawnCSARAtZone(zone, coalition.side.BLUE, player, false, false, player, typeName, true)
end

function csar.list()
  local out = {}
  if not csar.instance then return out end
  for _, p in pairs(csar.instance.downedPilots or {}) do
    if p.alive and p.group and p.group:IsAlive() then
      table.insert(out, { name = p.name, description = p.desc or p.player or "Downed pilot", pos = p.group:GetVec2() })
    end
  end
  return out
end

function csar.movePilotsTo(point, range, maxPilots)
  local moved = 0
  for _, p in ipairs(csar.list()) do
    if moved >= maxPilots then break end
    if util.distance(p.pos, point) <= range then
      local group = GROUP:FindByName(p.name)
      if group then
        group:RouteGroundTo(COORDINATE:NewFromVec2(point), 12, "Off Road", 1)
        moved = moved + 1
      end
    end
  end
  return moved
end

-- F10 > CSAR extras: MASH status and transport tasks.
function csar.addMenus(groupId, unitName)
  local root = missionCommands.addSubMenuForGroup(groupId, "MASH")
  missionCommands.addCommandForGroup(groupId, "Check MASH status", root, function()
    RH.dcs.messageToUnit(unitName, RH.logistics.mashStatus(), 20)
  end)
  missionCommands.addCommandForGroup(groupId, "Transport task: load patients", root, function()
    local unit = Unit.getByName(unitName)
    if not unit then return end
    local pos = util.toVec2(unit:getPoint())
    local mashName = RH.logistics.mashAt(pos, 300)
    if not mashName or unit:inAir() then
      RH.dcs.messageToUnit(unitName, "Land at a MASH to start a transport task.", 10)
      return
    end
    local cap = (RH.config.airframes[unit:getTypeName()] or {}).csar or 6
    local taken = RH.logistics.startTransport(unitName, mashName, cap)
    csar.refreshMashAvailability()
    RH.dcs.messageToUnit(unitName, string.format("%d patients loaded from %s. Fly them to an airfield.", taken, mashName), 15)
  end)
end

function csar.onLand(e)
  if not e.initiatorName or not RH.logistics.transports[e.initiatorName] then return end
  if e.placeKind == "airdrome" or e.placeKind == "ship" then
    local n = RH.logistics.completeTransport(e.initiatorName)
    RH.dcs.messageToUnit(e.initiatorName, string.format("%d patients delivered to %s. MASH capacity freed.", n, e.place or "the airfield"), 15)
  end
end

function csar.onBirth(e)
  if e.playerName and e.initiatorCoalition == "blue" and e.groupId and (e.initiatorCategory == "helicopter" or e.initiatorCategory == "plane") then
    csar.addMenus(e.groupId, e.initiatorName)
  end
end

function csar.start()
  csar.create()
  RH.events.on("land", csar.onLand)
  RH.events.on("birth", csar.onBirth)
end

return csar
