RH = RH or {}

local util = RH.util

-- MOOSE CSAR setup plus the Rotorheads extras: lives returned on rescue, MASH capacity of 30,
-- MASH -> airfield transport tasks, stranded-crew CSARs, and the -extract marker.
local csar = { instance = nil, manifests = {}, duty = {} }
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
  inst.extractDistance = RH.config.csar.landRadius
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
  -- The rescue loop in MOOSE only looks again every 20 seconds, which left the pilot standing
  -- at the helicopter long after the countdown. This timer owns the run and boards him when it hits zero.
  csar.runs = {}
  function inst:_OrderGroupToMoveToPoint(leader, destination)
    if not leader or not destination then return end
    leader:SetAIOn()
    leader:RouteToVec2(destination:GetVec2(), 8)
  end
  function inst:_CheckCloseWoundedGroup(distance, heliUnit, heliName, woundedGroup, woundedGroupName)
    if heliUnit:InAir() or distance > RH.config.csar.landRadius then return false end
    local key = heliName .. "_" .. woundedGroupName
    if csar.runs[key] then return false end
    local _, pilot = self:_CheckNameInDownedPilots(woundedGroupName)
    if pilot then csar.beginRun(self, heliUnit, pilot, distance) end
    return false
  end

  -- A hidden pilot has no group. Keep him on the books. Deleting the model must not count as killed.
  function inst:_CheckDownedPilotTable()
    local keep = {}
    for index, entry in pairs(self.downedPilots or {}) do
      if entry.alive then
        if not csar.groupAlive(entry.group) then
          entry.group = nil
          entry.rhHidden = true
        end
        keep[index] = entry
      end
    end
    self.downedPilots = keep
  end

  -- A fresh alias every time. Spawning several pilots in one moment was reusing a name, so only one soldier appeared.
  csar.spawnSerial = 0
  function inst:_SpawnPilotInField(country, point, frequency, wetfeet)
    csar.spawnSerial = csar.spawnSerial + 1
    if point and point.IsSurfaceTypeWater and (point:IsSurfaceTypeWater() or wetfeet) then point.y = 0 end
    local template = (self.usewetfeet and wetfeet) and self.wetfeettemplate or self.template
    local alias = string.format("RH Pilot %d", csar.spawnSerial)
    local group = SPAWN:NewWithAlias(template, alias):InitCoalition(self.coalition):InitCountry(country):InitDelayOff():SpawnFromCoordinate(point)
    return group, alias
  end

  local stockTrack = inst._CreateDownedPilotTrack
  function inst:_CreateDownedPilotTrack(...)
    stockTrack(self, ...)
    for _, pilot in pairs(self.downedPilots or {}) do
      if pilot.alive then csar.positionOf(pilot) end
    end
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
    -- InAir() without an argument treats a helicopter under 60 m as landed. That dropped the pilots
    -- while still flying into the zone. DCS inAir() is false only when the wheels are on the ground.
    if csar.onGround(heli) and RH.logistics.mashAt(heli:GetVec2(), RH.config.mash.radius) then
      self:_RescuePilots(heli)
      return
    end
    if not noreschedule then
      self:ScheduleOnce(5, self._ScheduledSARFlight, self, heliname, groupname, false, false)
    end
  end

  -- MOOSE deletes the previous pilot for this player before spawning the new one. Hide those
  -- records so the last few deaths all stay on the map.
  local stockHandler = inst._EventHandler
  function inst:_EventHandler(event)
    local player = event and event.IniPlayerName
    local crash = event and (event.id == EVENTS.PilotDead or event.id == EVENTS.Ejection)
    local hidden = {}
    if crash and player then
      for _, pilot in pairs(self.downedPilots or {}) do
        if pilot.alive and pilot.player == player then
          hidden[pilot] = player
          pilot.player = "\1" .. tostring(pilot.name)
        end
      end
    end
    local ok, err = pcall(stockHandler, self, event)
    for pilot, name in pairs(hidden) do
      if type(pilot.player) == "string" and string.sub(pilot.player, 1, 1) == "\1" then pilot.player = name end
    end
    if crash and player then csar.trimPlayerPilots(player) end
    if not ok then error(err) end
  end

  local stockStatus = inst._CheckWoundedGroupStatus
  function inst:_CheckWoundedGroupStatus(heliname, woundedgroupname)
    if not csar.unitOnDuty(heliname) then return end
    return stockStatus(self, heliname, woundedgroupname)
  end

  local stockAll = inst._DisplayToAllSAR
  function inst:_DisplayToAllSAR(message, side, messagetime, toSrs, toScreen)
    local original = self.csarUnits
    local onDuty = {}
    for name in pairs(original or {}) do
      if csar.unitOnDuty(name) then onDuty[name] = name end
    end
    self.csarUnits = onDuty
    local ok, err = pcall(stockAll, self, message, side, messagetime, toSrs, toScreen)
    self.csarUnits = original
    if not ok then error(err) end
  end

  function inst:_AddMedevacMenuItem()
    local groups = self.allheligroupset and self.allheligroupset:GetSetObjects() or {}
    for _, group in pairs(groups) do
      local unit = group.GetFirstUnitAlive and group:GetFirstUnitAlive()
      if unit and unit:IsAlive() and unit:IsPlayer() then
        local cap = self.AircraftType[unit:GetTypeName()]
        if cap == nil or cap > 0 then
          local unitName = unit:GetName()
          self.csarUnits = self.csarUnits or {}
          self.csarUnits[unitName] = unitName
          if self.addedTo[group:GetName()] == nil then
            self.addedTo[group:GetName()] = true
            csar.buildMenu(self, group, unitName)
          end
        end
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

  inst:ScheduleOnce(2, csar.watch, inst)
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

function csar.boardSeconds(distance)
  local seconds = math.floor((distance or 0) / 5)
  if seconds < 5 then seconds = 5 end
  local cap = RH.config.csar.boardMaxSeconds or 60
  if seconds > cap then seconds = cap end
  return seconds
end

function csar.groupAlive(group)
  if not group or not group.IsAlive then return false end
  local ok, alive = pcall(function() return group:IsAlive() end)
  return ok and alive == true
end

function csar.onGround(unit)
  if not unit or not unit.GetDCSObject then return false end
  local dcs = unit:GetDCSObject()
  if not dcs or not dcs.inAir then return false end
  return dcs:inAir() == false
end

function csar.positionOf(pilot)
  if not pilot then return nil end
  if csar.groupAlive(pilot.group) then
    local ok, v = pcall(function() return pilot.group:GetVec2() end)
    if ok and v then pilot.rhPos = { x = v.x, y = v.y } end
  end
  return pilot.rhPos
end

function csar.runFor(groupName)
  for key, run in pairs(csar.runs or {}) do
    if run.groupName == groupName then return key, run end
  end
end

function csar.hidePilot(inst, pilot)
  if not pilot or pilot.rhHidden or csar.runFor(pilot.name) then return end
  -- Leave the soldier in the world if we cannot put him back later.
  if not csar.captureTemplate(inst) then return end
  local pos = csar.positionOf(pilot)
  if not pos then return end
  if csar.groupAlive(pilot.group) then
    pilot.group:Destroy(false)
  end
  pilot.group = nil
  pilot.rhHidden = true
end

function csar.captureTemplate(inst)
  if csar.pilotTemplate then return true end
  local entry = _DATABASE and _DATABASE.Templates and _DATABASE.Templates.Groups[inst.template]
  if not entry or not entry.Template then return false end
  csar.pilotTemplate = UTILS.DeepCopy(entry.Template)
  csar.pilotCountry = entry.Template.CountryID or inst.countryblue
  csar.pilotCategory = entry.Template.CategoryID or Group.Category.GROUND
  return true
end

function csar.showPilot(inst, pilot)
  if not pilot then return end
  if csar.groupAlive(pilot.group) then
    pilot.rhHidden = false
    return pilot.group
  end
  local pos = pilot.rhPos
  if not pos then return end
  -- A spawn can report "not alive" for a moment. Keep that group instead of throwing it away.
  if pilot.group and pilot.rhShownAt and timer.getTime() - pilot.rhShownAt < 5 then
    return pilot.group
  end
  pilot.group = nil
  local group, err = csar.spawnAt(inst, pos, pilot.wetfeet)
  if not group then
    pilot.rhHidden = true
    local key = tostring(pilot.index or pilot.name)
    csar.spawnWarned = csar.spawnWarned or {}
    if not csar.spawnWarned[key] then
      csar.spawnWarned[key] = true
      RH.util.log("csar spawn failed: %s", tostring(err))
      RH.dcs.message("blue", "CSAR could not put the pilot back on the ground: " .. tostring(err), 15)
    end
    return nil
  end
  if inst._AddSpecialOptions then inst:_AddSpecialOptions(group) end
  pilot.group = group
  pilot.name = group:GetName() or pilot.name
  pilot.rhHidden = false
  pilot.alive = true
  pilot.rhShownAt = timer.getTime()
  return group
end

function csar.spawnAt(inst, pos, wetfeet)
  if not csar.captureTemplate(inst) then return nil, "downed-pilot template was not found" end
  csar.spawnSerial = (csar.spawnSerial or 0) + 1
  local id = csar.spawnSerial
  local tpl = UTILS.DeepCopy(csar.pilotTemplate)
  local gname = string.format("RH Pilot %d", id)
  local anchor = tpl.units and tpl.units[1]
  if not anchor then return nil, "template has no units" end
  local bx, by = anchor.x or 0, anchor.y or 0
  tpl.name = gname
  tpl.groupId = nil
  tpl.lateActivation = false
  tpl.CoalitionID = nil
  tpl.CountryID = nil
  tpl.CategoryID = nil
  tpl.x = pos.x
  tpl.y = pos.y
  if tpl.route and tpl.route.points and tpl.route.points[1] then
    tpl.route.points[1].x = pos.x
    tpl.route.points[1].y = pos.y
  end
  for i, unit in ipairs(tpl.units) do
    unit.name = string.format("RH Pilot %d-%d", id, i)
    unit.unitId = nil
    unit.x = pos.x + ((unit.x or bx) - bx)
    unit.y = pos.y + ((unit.y or by) - by)
    if wetfeet then unit.alt = 0 end
  end
  local countryId = csar.pilotCountry or inst.countryblue or country.id.USA
  local category = csar.pilotCategory or Group.Category.GROUND
  local ok, err = pcall(coalition.addGroup, countryId, category, tpl)
  if not ok then return nil, err end
  local group = GROUP:FindByName(gname)
  if not group and _DATABASE and _DATABASE.AddGroup then
    group = _DATABASE:AddGroup(gname)
  end
  if not group then return nil, "group was not created" end
  return group
end

-- Any blue player helicopter, including the one you took after crashing the first.
-- The old slot list still had the wreck, so the new aircraft was invisible to the rescue check.
function csar.playerHelicopters()
  local list = {}
  if not SET_GROUP then return list end
  local set = SET_GROUP:New():FilterCoalitions("blue"):FilterCategories("helicopter"):FilterOnce()
  for _, group in pairs(set:GetSet() or {}) do
    local unit = group.GetFirstUnitAlive and group:GetFirstUnitAlive()
    if unit and unit:IsAlive() and unit.IsPlayer and unit:IsPlayer() then
      local player = unit.GetPlayerName and unit:GetPlayerName()
      table.insert(list, { unit = unit, name = unit:GetName(), onDuty = player ~= nil and csar.duty[player] == true })
    end
  end
  return list
end

function csar.nearestDutyHeli(inst, pos)
  local best, bestDist, told
  for _, heli in ipairs(csar.playerHelicopters()) do
    local d = util.distance(pos, heli.unit:GetVec2())
    if not bestDist or d < bestDist then
      best, bestDist, told = heli, d, heli.onDuty
    end
  end
  if best and not told then return nil, bestDist, best end
  if best then return best.unit, bestDist, best end
  return nil, nil, nil
end

function csar.syncPilots(inst)
  if not inst then return end
  for _, pilot in pairs(inst.downedPilots or {}) do
    if pilot.alive then
      local pos = csar.positionOf(pilot)
      local heli, dist, closest = pos and csar.nearestDutyHeli(inst, pos)
      local reveal = RH.config.csar.revealRadius or 2000
      local hide = RH.config.csar.hideRadius or 2500
      if not csar.groupAlive(pilot.group) then
        if not (pilot.group and pilot.rhShownAt and timer.getTime() - pilot.rhShownAt < 5) then
          pilot.group = nil
          pilot.rhHidden = true
        end
      end
      if closest and not closest.onDuty and dist and dist <= reveal then
        local nag = "duty-" .. tostring(closest.name) .. "-" .. tostring(pilot.index or pilot.name)
        csar.heard = csar.heard or {}
        if not csar.heard[nag] then
          csar.heard[nag] = true
          RH.dcs.messageToUnit(closest.name, "Report on duty to see this pilot and pick him up.", 10)
        end
      end
      if pilot.rhHidden then
        if heli and dist and dist <= reveal then csar.showPilot(inst, pilot) end
      elseif not dist or dist > hide then
        csar.hidePilot(inst, pilot)
      end
      if not pilot.rhHidden and heli and csar.onGround(heli) and dist and dist <= RH.config.csar.landRadius then
        local key = heli:GetName() .. "_" .. pilot.name
        if not csar.runs[key] then csar.beginRun(inst, heli, pilot, dist) end
      end
      if heli and dist and dist <= 5000 then
        local heardKey = heli:GetName() .. "#" .. tostring(pilot.index or pilot.name)
        csar.heard = csar.heard or {}
        if not csar.heard[heardKey] then
          csar.heard[heardKey] = true
          inst:_DisplayMessageToSAR(heli, string.format("%s hears you, %.1f km out. Land within 1 km and he will run to the helicopter.", pilot.desc or "The pilot", dist / 1000), 10, false)
        end
      elseif dist and dist > 6000 and closest then
        if csar.heard then csar.heard[closest.name .. "#" .. tostring(pilot.index or pilot.name)] = nil end
      end
    end
  end
end

function csar.watch(inst)
  if csar.instance ~= inst then return end
  local ok, err = pcall(csar.syncPilots, inst)
  if not ok then RH.util.log("csar watch: %s", tostring(err)) end
  csar.menuTick = (csar.menuTick or 0) + 1
  if csar.menuTick % 2 == 0 then
    local mok, merr = pcall(csar.refreshSignalMenus)
    if not mok then RH.util.log("csar menu: %s", tostring(merr)) end
  end
  inst:ScheduleOnce(2, csar.watch, inst)
end

function csar.beginRun(inst, heli, pilot, distance)
  local group = pilot.group
  if not group or not group:IsAlive() then return end
  local heliName = heli:GetName()
  local key = heliName .. "_" .. pilot.name
  if csar.runs[key] then return end
  local seconds = csar.boardSeconds(distance)
  csar.runToken = (csar.runToken or 0) + 1
  local token = csar.runToken
  csar.runs[key] = {
    token = token, deadline = timer.getTime() + seconds, paused = false,
    groupName = pilot.name, heliName = heliName, pilotIndex = pilot.index, lastAnnounced = seconds,
  }
  group:OptionAlarmStateGreen()
  inst:_OrderGroupToMoveToPoint(group, heli:GetCoordinate())
  inst:_DisplayMessageToSAR(heli, string.format("%s is running to the helicopter. Boarding in %d seconds.", pilot.desc or "The pilot", seconds), 5, false)
  inst:ScheduleOnce(1, csar.runTick, inst, key, token)
end

function csar.runTick(inst, key, token)
  local run = csar.runs[key]
  if not run or run.token ~= token or csar.instance ~= inst then return end
  local heli = inst:_GetSARHeli(run.heliName)
  local _, pilot = inst:_CheckNameInDownedPilots(run.groupName)
  if not pilot and run.pilotIndex then
    for _, p in pairs(inst.downedPilots or {}) do
      if p.index == run.pilotIndex and p.alive then pilot = p break end
    end
  end
  local group = pilot and pilot.group
  if not heli or not heli:IsAlive() or not pilot or not pilot.alive or not group or not group:IsAlive() then
    csar.runs[key] = nil
    return
  end
  local dist = util.distance(heli:GetVec2(), group:GetVec2())
  local pilotName = pilot.desc or "The pilot"
  if heli:InAir() or dist > RH.config.csar.landRadius then
    if not run.paused then
      run.paused = true
      if group.RouteStop then group:RouteStop() end
      inst:_DisplayMessageToSAR(heli, string.format("%s stopped. Land within 1 km and he will start again.", pilotName), 6, false)
    end
    if dist > (RH.config.csar.hideRadius or 2500) then
      csar.runs[key] = nil
      return
    end
    inst:ScheduleOnce(1, csar.runTick, inst, key, token)
    return
  end
  if run.paused then
    local seconds = csar.boardSeconds(dist)
    run.deadline = timer.getTime() + seconds
    run.paused = false
    run.lastAnnounced = seconds
    run.groupName = pilot.name
    group:OptionAlarmStateGreen()
    inst:_OrderGroupToMoveToPoint(group, heli:GetCoordinate())
    inst:_DisplayMessageToSAR(heli, string.format("%s is running to the helicopter. Boarding in %d seconds.", pilotName, seconds), 5, false)
    inst:ScheduleOnce(1, csar.runTick, inst, key, token)
    return
  end
  local left = math.ceil(run.deadline - timer.getTime())
  if left <= 0 then
    csar.runs[key] = nil
    inst.landedStatus[key] = nil
    inst:_PickupUnit(heli, pilotName, group, pilot.name)
    return
  end
  if left ~= run.lastAnnounced and (left <= 5 or left % 10 == 0) then
    run.lastAnnounced = left
    inst:_DisplayMessageToSAR(heli, string.format("%s is running to the helicopter. Boarding in %d seconds.", pilotName, left), 4, false)
  end
  inst:ScheduleOnce(1, csar.runTick, inst, key, token)
end

function csar.list()
  local out = {}
  if not csar.instance then return out end
  for _, p in pairs(csar.instance.downedPilots or {}) do
    if p.alive then
      local pos = csar.positionOf(p)
      if pos then
        table.insert(out, { name = p.name, description = p.desc or p.player or "Downed pilot", pos = pos })
      end
    end
  end
  return out
end

function csar.playerOf(unitName)
  local unit = UNIT and UNIT.FindByName and UNIT:FindByName(unitName)
  local player = unit and unit.GetPlayerName and unit:GetPlayerName()
  if player and player ~= "" then return player end
  return nil
end

function csar.unitOnDuty(unitName)
  local player = csar.playerOf(unitName)
  return player ~= nil and csar.duty[player] == true
end

function csar.setDuty(unitName, on)
  local player = csar.playerOf(unitName) or unitName
  csar.duty[player] = on and true or nil
  if on then
    RH.dcs.messageToUnit(unitName, "You are on CSAR duty. You will hear pilots you fly over, and you can pick them up.", 12)
  else
    RH.dcs.messageToUnit(unitName, "You are off CSAR duty. Pilot calls will stay quiet.", 12)
  end
end

function csar.requireDuty(unitName)
  if csar.unitOnDuty(unitName) then return true end
  RH.dcs.messageToUnit(unitName, "Report on duty under CSAR before running a rescue.", 8)
  return false
end

function csar.trimPlayerPilots(player)
  local inst = csar.instance
  if not inst then return end
  local mine = {}
  for _, pilot in pairs(inst.downedPilots or {}) do
    if pilot.alive and pilot.player == player then table.insert(mine, pilot) end
  end
  table.sort(mine, function(a, b) return (a.index or 0) < (b.index or 0) end)
  local keep = RH.config.csar.keepPerPlayer or 3
  while #mine > keep do
    local old = table.remove(mine, 1)
    if old.group and old.group.Destroy then old.group:Destroy(false) end
    old.alive = false
    inst:_RemoveNameFromDownedPilots(old.name, true)
  end
end

function csar.buildMenu(inst, group, unitName)
  local root = MENU_GROUP:New(group, "CSAR")
  MENU_GROUP_COMMAND:New(group, "Report on duty", root, csar.setDuty, unitName, true)
  MENU_GROUP_COMMAND:New(group, "Report off duty", root, csar.setDuty, unitName, false)
  MENU_GROUP_COMMAND:New(group, "Show on map", root, function()
    if csar.requireDuty(unitName) then csar.showOnMap() end
  end)
  MENU_GROUP_COMMAND:New(group, "Disembark", root, function()
    if csar.requireDuty(unitName) then csar.disembark(group) end
  end)
  MENU_GROUP_COMMAND:New(group, "List active CSAR", root, function()
    if csar.requireDuty(unitName) then csar.reportActive(unitName) end
  end)
  MENU_GROUP_COMMAND:New(group, "Check onboard", root, function()
    if csar.requireDuty(unitName) then inst:_CheckOnboard(unitName) end
  end)
  local smokeMenu = MENU_GROUP:New(group, "Request smoke", root)
  local flareMenu = MENU_GROUP:New(group, "Request flare", root)
  csar.signalMenus = csar.signalMenus or {}
  table.insert(csar.signalMenus, { group = group, menu = smokeMenu, unitName = unitName, kind = "smoke" })
  table.insert(csar.signalMenus, { group = group, menu = flareMenu, unitName = unitName, kind = "flare" })
  csar.fillSignalMenu(group, smokeMenu, unitName, "smoke")
  csar.fillSignalMenu(group, flareMenu, unitName, "flare")

  local mash = MENU_GROUP:New(group, "MASH", root)
  MENU_GROUP_COMMAND:New(group, "Check MASH status", mash, function()
    RH.dcs.messageToUnit(unitName, RH.logistics.mashStatus(), 20)
  end)
  MENU_GROUP_COMMAND:New(group, "Transport task: load patients", mash, function()
    csar.loadPatients(unitName)
  end)
  MENU_GROUP_COMMAND:New(group, "Smoke closest MASH", mash, function()
    inst:_ReqsmokeMash(unitName)
  end)
end

function csar.pilotsNear(unitName, radius)
  local heli = UNIT and UNIT.FindByName and UNIT:FindByName(unitName)
  if not heli or not heli:IsAlive() then return {} end
  local pos = heli:GetVec2()
  local out = {}
  for _, pilot in pairs((csar.instance and csar.instance.downedPilots) or {}) do
    if pilot.alive then
      local pp = csar.positionOf(pilot)
      if pp then
        local d = util.distance(pos, pp)
        if d <= radius then table.insert(out, { pilot = pilot, distance = d }) end
      end
    end
  end
  table.sort(out, function(a, b) return a.distance < b.distance end)
  return out
end

function csar.refreshSignalMenus()
  for _, slot in ipairs(csar.signalMenus or {}) do
    if csar.groupAlive(slot.group) then
      csar.fillSignalMenu(slot.group, slot.menu, slot.unitName, slot.kind)
    end
  end
end

function csar.fillSignalMenu(group, menu, unitName, kind)
  if menu.RemoveSubMenus then menu:RemoveSubMenus() end
  if not csar.unitOnDuty(unitName) then
    MENU_GROUP_COMMAND:New(group, "Report on duty first", menu, function()
      csar.setDuty(unitName, true)
    end)
    return
  end
  local near = csar.pilotsNear(unitName, RH.config.csar.signalRadius or 10000)
  if #near == 0 then
    MENU_GROUP_COMMAND:New(group, "None within 10 km", menu, function() end)
    return
  end
  for _, item in ipairs(near) do
    local who = item.pilot.desc or item.pilot.player or "Downed pilot"
    if #who > 18 then who = string.sub(who, 1, 18) end
    local label = string.format("%s %.1fkm", who, item.distance / 1000)
    local pilotIndex = item.pilot.index
    MENU_GROUP_COMMAND:New(group, label, menu, function()
      csar.signalPilot(unitName, pilotIndex, kind)
    end)
  end
end

function csar.reportActive(unitName)
  local heli = UNIT and UNIT.FindByName and UNIT:FindByName(unitName)
  local pilots = csar.list()
  if not heli or #pilots == 0 then
    RH.dcs.messageToUnit(unitName, "No active CSAR.", 10)
    return
  end
  local pos = heli:GetVec2()
  table.sort(pilots, function(a, b) return util.distance(pos, a.pos) < util.distance(pos, b.pos) end)
  local lines = { "Active CSAR:" }
  for _, p in ipairs(pilots) do
    table.insert(lines, string.format("%s - %.1f km", p.description, util.distance(pos, p.pos) / 1000))
  end
  RH.dcs.messageToUnit(unitName, table.concat(lines, "\n"), 20)
end

function csar.signalPilot(unitName, pilotIndex, kind)
  if not csar.requireDuty(unitName) then return end
  local inst = csar.instance
  local heli = inst and inst:_GetSARHeli(unitName)
  local pilot
  for _, p in pairs(inst and inst.downedPilots or {}) do
    if p.alive and p.index == pilotIndex then pilot = p break end
  end
  if not heli or not pilot then
    RH.dcs.messageToUnit(unitName, "That pilot is no longer there.", 8)
    return
  end
  local pos = csar.positionOf(pilot)
  if not pos then return end
  local dist = util.distance(heli:GetVec2(), pos)
  if dist > (RH.config.csar.signalRadius or 10000) then
    RH.dcs.messageToUnit(unitName, "That pilot is more than 10 km away.", 8)
    return
  end
  local coord = COORDINATE:NewFromVec2(pos)
  local clock = inst:_GetClockDirection(heli, { GetCoordinate = function() return coord end })
  local who = pilot.desc or pilot.player or "The pilot"
  if kind == "flare" then
    coord:FlareRed(clock or 0)
    inst:_DisplayMessageToSAR(heli, string.format("%s fired a red flare at your %s o'clock, %.1f km.", who, tostring(clock), dist / 1000), 10, false)
  else
    coord:SmokeBlue()
    inst:_DisplayMessageToSAR(heli, string.format("%s popped blue smoke at your %s o'clock, %.1f km.", who, tostring(clock), dist / 1000), 10, false)
  end
end

function csar.loadPatients(unitName)
  local unit = Unit.getByName(unitName)
  if not unit then return end
  local pos = util.toVec2(unit:getPoint())
  local mashName = RH.logistics.mashAt(pos, RH.config.mash.radius)
  if not mashName or unit:inAir() then
    RH.dcs.messageToUnit(unitName, "Land at a MASH to start a transport task.", 10)
    return
  end
  local cap = (RH.config.airframes[unit:getTypeName()] or {}).csar or 6
  local taken = RH.logistics.startTransport(unitName, mashName, cap)
  csar.refreshMashAvailability()
  RH.dcs.messageToUnit(unitName, string.format("%d patients loaded from %s. Fly them to an airfield.", taken, mashName), 15)
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
  if not csar.onGround(unit) then
    RH.dcs.messageToUnit(heliName, "Land before the pilots can get out.", 8)
    return
  end
  local heading = unit:GetHeading() or 0
  local waiting = {}
  for _, rec in pairs(onboard) do table.insert(waiting, rec) end
  for i, rec in ipairs(waiting) do
    -- Spread them out behind the tail. The same point was stacking every soldier into one model.
    local drop = unit:GetCoordinate():Translate(18 + (i - 1) * 12, (heading + 180 + (i - 1) * 25) % 360)
    local zone = ZONE_RADIUS:New("RH_DISEMBARK_" .. csar.spawnSerial + i, drop:GetVec2(), 8, true)
    inst:SpawnCSARAtZone(zone, coalition.side.BLUE, rec.desc or rec.player or "Downed pilot", false, true, rec.player or rec.desc, rec.originalUnit, true)
  end
  local n = #waiting
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
      if not group and csar.instance then
        for _, rec in pairs(csar.instance.downedPilots or {}) do
          if rec.alive and rec.name == p.name then group = csar.showPilot(csar.instance, rec) end
        end
      end
      if group then
        group:RouteGroundTo(COORDINATE:NewFromVec2(point), 12, "Off Road", 1)
        moved = moved + 1
      end
    end
  end
  return moved
end

function csar.onLand(e)
  if not e.initiatorName or not RH.logistics.transports[e.initiatorName] then return end
  if e.placeKind == "airdrome" or e.placeKind == "ship" then
    local n = RH.logistics.completeTransport(e.initiatorName)
    RH.dcs.messageToUnit(e.initiatorName, string.format("%d patients delivered to %s. MASH capacity freed.", n, e.place or "the airfield"), 15)
  end
end

function csar.start()
  csar.create()
  RH.events.on("land", csar.onLand)
end

return csar
