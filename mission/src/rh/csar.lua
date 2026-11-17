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
  -- An airfield landing must not drop the pilot. Only the MASH zone does that.
  inst.allowFARPRescue = false
  inst.mashprefix = { RH.config.prefixes.mash }
  inst.pilotRuntoExtractPoint = true
  inst.extractDistance = 500
  -- The pilot has to reach the helicopter. Landing on top of him no longer skips the run.
  inst.loadDistance = 30
  inst.FARPRescueDistance = RH.config.mash.radius
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
  -- Run to the helicopter at a jog, and keep a countdown on screen until he climbs in.
  -- MOOSE picks the pilot up immediately when you land within about 80 m, so this replaces that check.
  local stockCheck = inst._CheckCloseWoundedGroup
  function inst:_OrderGroupToMoveToPoint(leader, destination)
    if not leader or not destination then return end
    leader:SetAIOn()
    leader:RouteToVec2(destination:GetVec2(), 8)
  end
  function inst:_CheckCloseWoundedGroup(distance, heliUnit, heliName, woundedGroup, woundedGroupName)
    if heliUnit:InAir() then
      return stockCheck(self, distance, heliUnit, heliName, woundedGroup, woundedGroupName)
    end
    if distance >= (self.extractDistance or 500) then return false end
    local key = heliUnit:GetName() .. "_" .. woundedGroupName
    local _, pilotable = self:_CheckNameInDownedPilots(woundedGroupName)
    local pilotName = (pilotable and pilotable.desc) or "The pilot"
    local left = self.landedStatus[key]
    if left == nil then
      -- 25 m is about 5 seconds, 50 m is 10, 100 m is 20. The check runs every 5 seconds.
      left = math.max(5, math.floor(distance / 5))
      woundedGroup:OptionAlarmStateGreen()
      self:_OrderGroupToMoveToPoint(woundedGroup, heliUnit:GetCoordinate())
    else
      left = left - 5
    end
    if left < 0 then left = 0 end
    self.landedStatus[key] = left
    if left > 0 then
      self:_DisplayMessageToSAR(heliUnit, string.format("%s is running to the helicopter. Boarding in %d seconds.", pilotName, left), 5, false)
      return false
    end
    self.landedStatus[key] = nil
    self:_PickupUnit(heliUnit, pilotName, woundedGroup, woundedGroupName)
    return true
  end

  -- Drop the pilot only inside the MASH zone. Landing at the airfield keeps him aboard.
  function inst:_ScheduledSARFlight(heliname, groupname, isairport, noreschedule)
    local heli = self:_GetSARHeli(heliname)
    if not heli then
      self.inTransitGroups[heliname] = nil
      return
    end
    local onboard = self.inTransitGroups[heliname]
    if not onboard or not onboard[groupname] then return end
    if not heli:InAir() and RH.logistics.mashAt(heli:GetVec2(), RH.config.mash.radius) then
      self:_RescuePilots(heli)
      return
    end
    if not noreschedule then
      self:ScheduleOnce(5, self._ScheduledSARFlight, self, heliname, groupname, false, false)
    end
  end

  local addMenu = inst._AddMedevacMenuItem
  csar.mapMenu = {}
  function inst:_AddMedevacMenuItem(...)
    addMenu(self, ...)
    for _, group in pairs(self.allheligroupset:GetSetObjects() or {}) do
      local name = group:GetName()
      if self.addedTo[name] and not csar.mapMenu[name] then
        csar.mapMenu[name] = true
        local root = MENU_GROUP:New(group, "CSAR")
        MENU_GROUP_COMMAND:New(group, "Show on map", root, csar.showOnMap)
        MENU_GROUP_COMMAND:New(group, "Disembark", root, function() csar.disembark(group) end)
      end
    end
  end

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
    local mashName = pos and RH.logistics.mashAt(pos, RH.config.mash.radius)
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

function csar.disembark(group)
  local unit = group and group.GetFirstUnitAlive and group:GetFirstUnitAlive()
  if not unit or not unit:IsAlive() then return end
  local heliName = unit:GetName()
  local inst = csar.instance
  local onboard = inst and inst.inTransitGroups[heliName]
  if not onboard or not next(onboard) then
    RH.dcs.messageToUnit(heliName, "No rescued pilots aboard.", 8)
    return
  end
  if unit:InAir() then
    RH.dcs.messageToUnit(heliName, "Land before the pilots can get out.", 8)
    return
  end
  local heading = unit:GetHeading() or 0
  local drop = unit:GetCoordinate():Translate(20, (heading + 180) % 360)
  local n = 0
  for _, rec in pairs(onboard) do
    n = n + 1
    local zone = ZONE_RADIUS:New("RH_DISEMBARK_" .. math.random(1, 1000000), drop:GetVec2(), 15, true)
    inst:SpawnCSARAtZone(zone, coalition.side.BLUE, rec.desc or rec.player or "Downed pilot", false, true, rec.player or rec.desc, rec.originalUnit, true)
  end
  inst.inTransitGroups[heliName] = nil
  inst:_UpdateUnitCargoMass(heliName)
  csar.manifests[heliName] = nil
  RH.dcs.messageToUnit(heliName, string.format("%d pilot%s stepped out and can be picked up again.", n, n == 1 and "" or "s"), 12)
end

function csar.showOnMap()
  local pilots = csar.list()
  if #pilots == 0 then
    RH.dcs.message("blue", "No downed pilots to mark.", 10)
    return
  end
  for _, p in ipairs(pilots) do
    local id = "csar-mark-" .. p.name
    RH.dcs.drawCircle(id, "blue", p.pos, 250, { 0, 0.45, 1, 1 }, { 0, 0.45, 1, 0.28 }, p.description)
    RH.after(30, function() RH.dcs.removeDrawing(id) end)
  end
  RH.dcs.message("blue", string.format("%d downed pilot%s marked in blue for 30 seconds.", #pilots, #pilots == 1 and "" or "s"), 10)
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
