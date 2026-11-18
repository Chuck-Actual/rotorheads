RH = RH or {}

local util = RH.util

-- MOOSE CTLD setup: troop transport, crates, sling loading, CH-47 dynamic cargo, repacking, persistence.
-- Rotorheads-specific rules (per-FARP crate stock, FARP/MASH/outpost construction, -wpzone) hook in here.
local ctld = { instance = nil, fatCows = {} }
RH.ctld = ctld

local function kitName(cargoName)
  for key, kit in pairs(RH.config.kits) do
    if kit.name == cargoName then return key end
  end
end

local function templateKit(groupName)
  for key, kit in pairs(RH.config.kits) do
    if util.startsWith(groupName, kit.template) then return key end
  end
end

local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[deepCopy(k, seen)] = deepCopy(v, seen)
  end
  return copy
end

-- CTLD hides a crate when its group template is not in the mission. The FARP kit is thrown away
-- after the build, so copy a vehicle template that is already there instead of asking for a new group.
function ctld.ensureKitTemplate(name)
  local groups = _DATABASE and _DATABASE.Templates and _DATABASE.Templates.Groups
  if not groups then
    util.log("crate template %s skipped: MOOSE group templates are not loaded", name)
    return false
  end
  if groups[name] then return true end
  local donorName, donor = "RH_TPL_BLUE_HMMWV_TOW", nil
  donor = groups[donorName]
  if not donor then
    for existing, entry in pairs(groups) do
      if type(existing) == "string" and util.startsWith(existing, "RH_TPL_BLUE_") and entry.Template then
        donorName, donor = existing, entry
        break
      end
    end
  end
  if not donor or not donor.Template then
    util.log("crate template %s skipped: no RH_TPL_BLUE_ vehicle template is in the mission", name)
    return false
  end
  local copy = deepCopy(donor)
  copy.GroupName = name
  copy.Template.name = name
  groups[name] = copy
  -- Do not GROUP:Register a name that is not actually in the mission. The F10 scan calls
  -- getCoalition() on every database group, and DCS throws "Group doesn't exist" for a fake one.
  util.log("crate template %s copied from %s", name, donorName)
  return true
end

-- NASAMS and Roland only share a radar when every piece is in the same DCS group.
ctld.samLinkRadius = 2500

function ctld.samFamily(groupName, typeName)
  local blob = string.upper((groupName or "") .. " " .. (typeName or ""))
  if string.find(blob, "NASAMS", 1, true) then return "NASAMS" end
  if string.find(blob, "ROLAND", 1, true) then return "ROLAND" end
  return nil
end

-- One click spawns either the whole set or a single crate, so a second trip can finish a vehicle.
function ctld.crateChoices(needed)
  needed = math.max(1, math.floor(tonumber(needed) or 1))
  if needed == 1 then return { { label = "Get", count = 1 } } end
  return {
    { label = string.format("All %d crates", needed), count = needed },
    { label = "1 crate", count = 1 },
  }
end

function ctld.buildPoint(unit)
  if not unit or not unit.IsAlive or not unit:IsAlive() then return nil end
  local heading = unit:GetHeading() or 0
  local airframe = RH.config.airframes[unit:GetTypeName()]
  local length = airframe and airframe.length or 15
  return unit:GetCoordinate():Translate(length / 2 + 10, (heading + 180) % 360):GetVec2()
end

local function isLogisticsTent(static)
  local name = string.lower(static.name or "")
  local kind = string.lower((static.typeName or "") .. " " .. (static.display or ""))
  -- The hospital tent is spawned by us and named "<MASH> tent".
  if string.sub(name, -5) == " tent" then return false end
  if string.find(kind, "tent04", 1, true) or string.find(kind, "m92", 1, true) then return false end
  if string.find(kind, "tent", 1, true) or string.find(kind, "farp", 1, true) then return true end
  if string.find(name, "tent", 1, true) or string.find(name, "farp", 1, true) then return true end
  return false
end

-- The 150 m load circle sits on the logistics tent, not on the middle of a large trigger zone.
function ctld.tentPoints(farp)
  local search = math.min(math.max(farp.zoneRadius or 0, 2000), 4000)
  local tents = {}
  for _, static in ipairs(RH.dcs.staticObjects()) do
    if isLogisticsTent(static) and util.distance(static, farp) <= search then
      table.insert(tents, static)
    end
  end
  if #tents > 0 then return tents, true end
  return { { x = farp.x, y = farp.y } }, false
end

function ctld.addFarpZone(farp)
  if not ctld.instance then return end
  local points, atTent = ctld.tentPoints(farp)
  farp.loadPoints = points
  local radius = RH.config.farp.loadRadius
  for i, point in ipairs(points) do
    local zoneName = "RH_LOAD_" .. farp.name .. "_" .. i
    local zone = ZONE:FindByName(zoneName)
    if zone and zone.UpdateFromVec2 then
      zone:UpdateFromVec2({ x = point.x, y = point.y }, radius)
    else
      ZONE_RADIUS:New(zoneName, { x = point.x, y = point.y }, radius)
    end
    ctld.instance:AddCTLDZone(zoneName, CTLD.CargoZoneType.LOAD, SMOKECOLOR.Blue, true, false)
    local id = "rh-load-" .. farp.name .. "-" .. i
    RH.dcs.drawCircle(id, "blue", point, radius, { 0, 0.55, 1, 1 }, { 0, 0.55, 1, 0.18 }, "Load")
    RH.after(60, function() RH.dcs.removeDrawing(id) end)
  end
  return atTent
end

function ctld.reply(Group, text)
  if ctld.instance then ctld.instance:_SendMessage(text, 10, false, Group) end
end

function ctld.create()
  local c = RH.config
  local inst = CTLD:New(coalition.side.BLUE, { "" }, "RH Logistics")
  inst:SetOwnSetPilotGroups(SET_GROUP:New():FilterCoalitions("blue"):FilterCategories({ "helicopter", "plane" }):FilterStart())

  inst.enableslingload = true
  inst.enableChinookGCLoading = true
  inst.enableFixedWing = true
  inst.dropcratesanywhere = true
  inst.nobuildinloadzones = true
  -- Chinooks unload through the rearm/refuel window. Those crates were never "moved" by CTLD,
  -- and the default refuses to build them until they are packed and dropped again.
  inst.movecratesbeforebuild = false
  inst.forcehoverload = false
  inst.CrateDistance = 50
  inst.PackDistance = 50
  inst.buildtime = 5
  inst.repairtime = 60
  inst.usesubcats = true
  inst.allowcratepickupagain = true
  inst.TroopUnloadDistGroundHook = 15
  inst.useaircraftheadingforbuilds = true
  -- Same CDS box the C-130 loads (22 of them), for helicopters and the Hercules.
  inst.basetype = c.crateModel or "cds_crate"
  inst.C130basetype = inst.basetype

  inst.enableLoadSave = RH.dcs.filesEnabled()
  inst.saveinterval = 30
  inst.filepath = RH.dcs.saveDir()
  inst.filename = "ctld.csv"

  for typeName, a in pairs(c.airframes) do
    inst:SetUnitCapabilities(typeName, a.crates, a.troops, a.cratelimit, a.trooplimit, a.length, a.maxweight)
  end

  for _, t in ipairs(c.troops) do
    -- No subcategory: Load troops lists the squad, and clicking that name loads it.
    inst:AddTroopsCargo(t.name, { t.template }, CTLD_CARGO.Enum.TROOPS, t.size, c.troopWeight, nil, nil)
  end
  local function addCrates(name, template, kind, crates, mass, subcat)
    inst:AddCratesCargo(name, { template }, kind, crates, mass, nil, subcat, nil, nil, nil, "Cargos", inst.basetype, nil, inst.basetype)
  end
  for _, v in ipairs(c.vehicles) do
    local crates = c.testVehicleCrates or v.crates
    addCrates(v.name, v.template, CTLD_CARGO.Enum.VEHICLE, crates, v.mass, v.subcat)
  end
  ctld.ensureKitTemplate(c.kits.farp.template)
  addCrates(c.kits.farp.name, c.kits.farp.template, CTLD_CARGO.Enum.FOB, c.farp.cratesForFarp, c.farp.farpCrateMass, "FARP AND MASH")
  addCrates(c.kits.mash.name, c.kits.mash.template, CTLD_CARGO.Enum.FOB, c.mash.crates, c.mash.crateMass, "FARP AND MASH")
  addCrates(c.kits.outpost.name, c.kits.outpost.template, CTLD_CARGO.Enum.FOB, c.kits.outpost.crates, c.kits.outpost.mass, "SUPPORT AND SUPPLIES")
  addCrates(c.kits.uhRepair.name, c.kits.uhRepair.template, CTLD_CARGO.Enum.FOB, c.kits.uhRepair.crates, c.kits.uhRepair.mass, "FARP AND MASH")
  local supply = c.kits.generalSupply
  if supply then
    for _, batch in ipairs(supply.batches) do
      addCrates(supply.name .. " x" .. batch, supply.template, CTLD_CARGO.Enum.VEHICLE, batch, supply.mass, "SUPPORT AND SUPPLIES")
    end
  end

  for _, ship in ipairs(c.ships) do
    if UNIT:FindByName(ship.unit) then
      inst:AddCTLDZone(ship.unit, CTLD.CargoZoneType.SHIP, SMOKECOLOR.Blue, true, true, ship.length, ship.width)
    end
  end

  ctld.instance = inst
  local notes = {}
  for _, farp in ipairs(RH.logistics.farps()) do
    local atTent = ctld.addFarpZone(farp)
    table.insert(notes, farp.name .. (atTent and " (tent)" or " (zone center, no tent found)"))
  end
  if #notes > 0 then
    RH.dcs.message("blue", "Logistics load zones, 150 m, shown in blue for 60 seconds: " .. table.concat(notes, ", ")
      .. ". Vehicle crates are under CTLD > Cargos. FARP crates and general supply come from a logistics center.", 25)
  end
  if RH.logistics.refreshPlacedCenters then RH.logistics.refreshPlacedCenters() end
  ctld.installHooks(inst)
  ctld.installMenus(inst)
  if RH.events and RH.events.on then RH.events.on("playerEnter", ctld.onPlayerEnter) end
  inst:__Start(2)
  if RH.after then RH.after(20, ctld.linkExisting) end
  -- Once the world snapshot exists it restores vehicles and crates itself. Loading CTLD's
  -- csv as well would build a second copy. The first run still reads the csv, so a Humvee
  -- saved only there can come back once and then join the snapshot.
  if inst.enableLoadSave and not (RH.state.world and RH.state.world.baselineReady) then
    inst:__Load(10)
  end
  return inst
end

function ctld.installMenus(inst)
  local refresh = inst._RefreshF10Menus
  function inst:_AddCrateQuantityMenus(Group, Unit, parentMenu, cargoObj)
    local needed = cargoObj.GetCratesNeeded and cargoObj:GetCratesNeeded() or 1
    for _, choice in ipairs(ctld.crateChoices(needed)) do
      MENU_GROUP_COMMAND:New(Group, choice.label, parentMenu, self._GetCrates, self, Group, Unit, cargoObj, choice.count, false, false)
    end
    return self
  end
  function inst:_RefreshF10Menus()
    local already = {}
    for name in pairs(self.MenusDone or {}) do already[name] = true end
    refresh(self)
    for name in pairs(self.CtldUnits or {}) do
      if not already[name] then ctld.flattenTroopMenu(self, name) end
    end
  end
end

-- MOOSE puts a "1" under every squad. Clicking the squad name loads that one squad.
function ctld.flattenTroopMenu(inst, unitName)
  if not UNIT or not UNIT.FindByName then return end
  local unit = UNIT:FindByName(unitName)
  local group = unit and unit.GetGroup and unit:GetGroup()
  if not group then return end
  group.RHReturnCrates = nil
  local menus = group.CTLD_TroopMenus
  if menus then
    for name, menu in pairs(menus) do
      local cargo = inst._FindTroopsCargoObject and inst:_FindTroopsCargoObject(name)
      local owner = menu.MenuParent or menu.ParentMenu
      local text = menu.MenuText or name
      if menu.Remove then menu:Remove() end
      if cargo and owner and MENU_GROUP_COMMAND then
        MENU_GROUP_COMMAND:New(group, text, owner, inst._LoadTroops, inst, group, unit, cargo)
      end
    end
    group.CTLD_TroopMenus = nil
  end
  local crates = group.MyTopCratesMenu
  if crates and not group.RHReturnCrates and MENU_GROUP_COMMAND then
    MENU_GROUP_COMMAND:New(group, "Return crates to tent", crates, function()
      if inst._RemoveCratesNearby then inst:_RemoveCratesNearby(group, unit) end
    end)
    group.RHReturnCrates = true
  end
end

function ctld.installHooks(inst)
  -- Per-FARP crate stock. LCs and ships are unlimited; FARP construction crates only come from LCs and ships.
  function inst:CanGetCrates(Group, Unit, Cargo, number)
    local farp = RH.logistics.farpAt(Unit:GetVec2())
    if not farp then return true end
    local cargoName = Cargo:GetName()
    local kit = kitName(cargoName)
    if (kit == "farp" or RH.logistics.isGeneralSupply(cargoName)) and not RH.logistics.hasUnlimitedCrates(farp) then
      ctld.reply(Group, "General supply and FARP crates are only available at Logistics Centers and ships.")
      return false
    end
    local count = tonumber(number) or Cargo:GetCratesNeeded() or 1
    if not RH.logistics.takeCrates(farp, count) then
      ctld.reply(Group, string.format("%s only has %d crates left. Ask a C-130 or a convoy to resupply it.", farp.name, farp.crates))
      return false
    end
    return true
  end

  function inst:OnAfterRemoveCratesNearby(From, Event, To, Group, Unit, Cargotable)
    local point = Unit and Unit.GetVec2 and Unit:GetVec2()
    local farp = point and RH.logistics.farpAt(point, 500)
    if not farp or not Cargotable then
      ctld.reply(Group, "Crates removed. Land within 500 m of a FARP or logistics tent to add them to that stock.")
      return
    end
    local worth = 0
    for _, cargo in pairs(Cargotable) do
      local name = cargo.GetName and cargo:GetName() or ""
      worth = worth + RH.logistics.crateWorth(name)
    end
    local added = RH.logistics.returnCrates(farp, worth)
    if added > 0 then
      ctld.reply(Group, string.format("%d crates returned to %s (now %s).", added, farp.name,
        RH.logistics.hasUnlimitedCrates(farp) and "unlimited" or tostring(farp.crates)))
    end
  end

  function inst:OnAfterTroopsDeployed(From, Event, To, Group, Unit, Troops)
    if not Troops or not Troops:IsAlive() then return end
    local wp = RH.markers.wpzoneFor(Troops:GetVec2())
    if wp then Troops:RouteGroundTo(COORDINATE:NewFromVec2(wp), 15, "Off Road", 2) end
  end

  -- Mark the FARP when the countdown starts. The placeholder vehicle spawn can fail, and
  -- waiting for it is what left the last site unsaved.
  function inst:OnBeforeCratesBuild(From, Event, To, Group, Unit, cargoName)
    if type(cargoName) == "table" and cargoName.GetName then cargoName = cargoName:GetName() end
    if RH.logistics.isGeneralSupply(cargoName) then
      ctld.reply(Group, "General supply crates are not built. Land at a FARP tent and use Return crates. Each one adds 5 to that FARP.")
      return false
    end
    return true
  end

  function inst:OnAfterCratesBuildStarted(From, Event, To, Group, Unit, cargoName)
    if cargoName ~= RH.config.kits.farp.name then return end
    local point = Unit and Unit.GetVec2 and Unit:GetVec2()
    if not point then return end
    local player = Unit and Unit.GetPlayerName and Unit:GetPlayerName() or "A pilot"
    local farp, reason = RH.logistics.buildFarp(point, player)
    if not farp then ctld.reply(Group, "FARP was not marked: " .. tostring(reason)) end
  end

  function inst:OnAfterCratesBuild(From, Event, To, Group, Unit, Vehicle)
    if not Group or not Vehicle then return end
    local kit = templateKit(Vehicle:GetName())
    -- Leave the unit on the crate it was built from. Moving every build behind the helicopter
    -- stacked a radar, a CP, and a launcher on the same spot.
    if not kit then
      ctld.linkSam(Vehicle)
      return
    end
    local point = Vehicle:GetVec2()
    local player = Unit and Unit:GetPlayerName() or "A pilot"
    local ok, reason
    if kit == "farp" then
      -- The spawned group is only the Humvee template CTLD needs in order to finish the build.
      Vehicle:Destroy(false)
      if not RH.logistics.farpNear(point, 400) then
        local farp, reason = RH.logistics.buildFarp(point, player)
        if not farp then ctld.reply(Group, "FARP was not marked: " .. tostring(reason)) end
      end
      return
    elseif kit == "mash" then
      ok, reason = RH.logistics.buildMash(point, player)
    elseif kit == "outpost" then
      ok = RH.logistics.buildBlueOutpost(point, player)
    elseif kit == "uhRepair" then
      ok = ctld.deployFatCow(point, Unit)
    end
    if ok then
      Vehicle:Destroy(false)
    else
      ctld.reply(Group, string.format("Cannot build here: %s. Pack the kit (CTLD > Pack) and move it.", tostring(reason)))
    end
  end
end

function ctld.unitHeading(unit)
  local ok, pos = pcall(function() return unit:getPosition() end)
  if not ok or type(pos) ~= "table" or type(pos.x) ~= "table" then return 0 end
  local h = math.atan2(pos.x.z or 0, pos.x.x or 1)
  if h < 0 then h = h + math.pi * 2 end
  return h
end

function ctld.collectSam(group, family, anchor, into, seen)
  if not group or not group.isExist or not group:isExist() then return end
  local name = group.getName and group:getName() or ""
  if seen[name] then return end
  local units = group.getUnits and group:getUnits() or {}
  local taken = false
  for _, unit in ipairs(units) do
    if unit:isExist() and unit:getLife() > 1 then
      local point = unit:getPoint()
      local pos = { x = point.x, y = point.z }
      local fam = ctld.samFamily(name, unit:getTypeName())
      if fam == family and RH.util.distance(anchor, pos) <= ctld.samLinkRadius then
        into[#into + 1] = { type = unit:getTypeName(), x = pos.x, y = pos.y, heading = ctld.unitHeading(unit) }
        taken = true
      end
    end
  end
  if taken then seen[name] = group end
end

-- Rebuild every NASAMS or Roland piece within 2.5 km as one group so the radar can cue the launchers.
function ctld.linkSam(spawned)
  if not spawned or not spawned.GetName or not coalition or not coalition.getGroups then return end
  local dcsGroup = Group.getByName(spawned:GetName())
  if not dcsGroup then return end
  local family
  for _, unit in ipairs(dcsGroup:getUnits() or {}) do
    if unit:isExist() then
      family = ctld.samFamily(dcsGroup:getName(), unit:getTypeName())
      if family then break end
    end
  end
  if not family then return end
  local anchor = spawned.GetVec2 and spawned:GetVec2() or { x = 0, y = 0 }
  local pieces, seen = {}, {}
  ctld.collectSam(dcsGroup, family, anchor, pieces, seen)
  for _, group in ipairs(coalition.getGroups(coalition.side.BLUE, Group.Category.GROUND) or {}) do
    ctld.collectSam(group, family, anchor, pieces, seen)
  end
  if #pieces < 2 then
    ctld.reply(spawned, family .. " is in place. Add the rest of the battery within 2.5 km and they will link.")
    return
  end
  for _, group in pairs(seen) do
    if group.destroy then group:destroy() end
  end
  ctld.batterySerial = (ctld.batterySerial or 0) + 1
  local name = string.format("RH %s %d", family, ctld.batterySerial)
  local ok = RH.dcs.spawnSamBattery and RH.dcs.spawnSamBattery(name, pieces)
  if not ok then return end
  if RH.after and GROUP then
    RH.after(1, function()
      local linked = GROUP:FindByName(name)
      if not linked then return end
      linked:OptionROEOpenFire()
      linked:OptionAlarmStateRed()
    end)
  end
  ctld.reply(spawned, string.format("%s battery linked, %d units. The radar, command post, and launchers are one group.", family, #pieces))
end

function ctld.linkExisting()
  if not coalition or not coalition.getGroups or not GROUP then return end
  local ok, err = pcall(function()
  local names = {}
  for _, group in ipairs(coalition.getGroups(coalition.side.BLUE, Group.Category.GROUND) or {}) do
    local name = group:getName()
    for _, unit in ipairs(group:getUnits() or {}) do
      if unit:isExist() and ctld.samFamily(name, unit:getTypeName()) then
        names[#names + 1] = name
        break
      end
    end
  end
  for _, name in ipairs(names) do
    local wrapper = GROUP:FindByName(name)
    if wrapper and wrapper:IsAlive() then ctld.linkSam(wrapper) end
  end
  end)
  if not ok then util.log("SAM link failed: %s", tostring(err)) end
end

function ctld.onPlayerEnter(e)
  if not e or e.initiatorCoalition ~= "blue" then return end
  if e.initiatorCategory ~= "helicopter" and e.initiatorCategory ~= "plane" then return end
  local function rebuild()
    local inst = ctld.instance
    if not inst or not e.initiatorName then return end
    inst.MenusDone[e.initiatorName] = nil
    if UNIT and UNIT.FindByName then
      local unit = UNIT:FindByName(e.initiatorName)
      local group = unit and unit.GetGroup and unit:GetGroup()
      if group and group.CTLDTopmenu and group.CTLDTopmenu.Remove then
        group.CTLDTopmenu:Remove()
        group.CTLDTopmenu = nil
      end
      if group then group.RHReturnCrates = nil end
    end
    if inst._RefreshF10Menus then inst:_RefreshF10Menus() end
  end
  if RH.after then
    RH.after(1, rebuild)
    RH.after(5, rebuild)
  else
    rebuild()
  end
end

-- Fat Cow: temporary repair point from a UH Repair kit. Disappears after 30 minutes or when the deploying helo lifts off.
function ctld.deployFatCow(point, Unit)
  local name = string.format("Fat Cow %d", math.random(1000, 9999))
  local objects = UTILS.SpawnFARPAndFunctionalStatics(name, COORDINATE:NewFromVec2(point), ENUMS.FARPType.INVISIBLE,
    coalition.side.BLUE, country.id.USA, nil, nil, nil, nil, 50, nil, 0, 0, 0, name, false)
  local unitName = Unit and Unit:GetName()
  local expiresAt = timer.getTime() + RH.config.kits.uhRepair.lifetime
  local function remove()
    for _, obj in ipairs(objects or {}) do
      if obj and obj.Destroy then obj:Destroy(false) end
    end
  end
  local timerObj
  timerObj = TIMER:New(function()
    local u = unitName and UNIT:FindByName(unitName)
    if timer.getTime() >= expiresAt or not u or not u:IsAlive() or u:InAir() then
      remove()
      timerObj:Stop()
    end
  end)
  timerObj:Start(20, 10)
  return true
end

return ctld
