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
  -- SPAWN refuses the copy unless a group of that name is also in the live database.
  if _DATABASE.GROUPS and not _DATABASE.GROUPS[name] and GROUP and GROUP.Register then
    _DATABASE.GROUPS[name] = GROUP:Register(name)
  end
  util.log("crate template %s copied from %s", name, donorName)
  return true
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
  -- The pad, fuel depot, and ammo dump all contain "farp". Only the tent should own the load circle.
  if string.find(kind, "tent04", 1, true) or string.find(kind, "m92", 1, true) then return false end
  if string.find(name, "mash", 1, true) then return false end
  if string.find(kind, "farp tent", 1, true) or string.find(kind, "palatka", 1, true) then return true end
  if string.sub(name, -5) == " tent" then return true end
  return false
end

-- The 150 m load circle sits on the logistics tent, not on the middle of a large trigger zone.
function ctld.tentPoints(farp)
  local search = math.max(farp.zoneRadius or 0, RH.config.farp.loadRadius or 150)
  if search > 600 then search = 600 end
  local tents = {}
  for _, static in ipairs(RH.dcs.staticObjects()) do
    if isLogisticsTent(static) and util.distance(static, farp) <= search then
      table.insert(tents, static)
    end
  end
  if #tents > 0 then return tents, true end
  return { { x = farp.x, y = farp.y } }, false
end

function ctld.zoneRadius(farp)
  if farp and (farp.lc or (RH.logistics and RH.logistics.hasUnlimitedCrates(farp))) then
    return RH.config.farp.lcLoadRadius or 500
  end
  return RH.config.farp.loadRadius or 150
end

function ctld.refreshZones()
  if not ctld.instance or not RH.logistics then return end
  for _, farp in ipairs(RH.logistics.farps()) do
    ctld.ensureFarpZone(farp)
  end
  if RH.logistics.refreshMapLabels then RH.logistics.refreshMapLabels() end
end

-- The saved flag loadZoneReady is ignored. Every FARP already in the campaign gets a zone
-- again on this mission, and a logistics center uses the apron radius.
ctld.zoneReady = {}

function ctld.ensureFarpZone(farp)
  if not ctld.instance or not farp or not farp.name then return end
  farp.loadZoneReady = nil
  local points, atTent = ctld.tentPoints(farp)
  farp.loadPoints = points
  local radius = ctld.zoneRadius(farp)
  for i, point in ipairs(points) do
    local zoneName = "RH_LOAD_" .. farp.name .. "_" .. i
    if ZONE and ZONE_RADIUS then
      local zone = ZONE.FindByName and ZONE:FindByName(zoneName)
      if zone and zone.UpdateFromVec2 then
        zone:UpdateFromVec2({ x = point.x, y = point.y }, radius)
      elseif not zone then
        ZONE_RADIUS:New(zoneName, { x = point.x, y = point.y }, radius)
      end
      local key = farp.name .. ":" .. i
      if not ctld.zoneReady[key] then
        ctld.instance:AddCTLDZone(zoneName, CTLD.CargoZoneType.LOAD, SMOKECOLOR.Blue, true, false)
        ctld.zoneReady[key] = true
      end
    end
  end
  return atTent, radius
end

function ctld.drawLoadZones(farp)
  if not farp or not farp.name then return 0 end
  local points = (farp.loadPoints and #farp.loadPoints > 0) and farp.loadPoints or { { x = farp.x, y = farp.y } }
  local radius = ctld.zoneRadius(farp)
  local seconds = RH.config.farp.displayCirclesFor or 60
  local drawn = 0
  for i, point in ipairs(points) do
    local id = "rh-load-" .. farp.name .. "-" .. i
    RH.dcs.drawCircle(id, "blue", point, radius, { 0, 0.55, 1, 1 }, { 0, 0.55, 1, 0.18 }, "Load")
    drawn = drawn + 1
    RH.after(seconds, function()
      RH.dcs.removeDrawing(id)
      if RH.logistics.refreshMapLabels then RH.logistics.refreshMapLabels() end
    end)
  end
  return drawn
end

function ctld.addFarpZone(farp)
  local atTent = ctld.ensureFarpZone(farp)
  ctld.drawLoadZones(farp)
  return atTent
end

function ctld.reply(Group, text)
  if ctld.instance and ctld.instance._SendMessage then
    ctld.instance:_SendMessage(text, 10, false, Group)
  end
end

function ctld.create()
  local c = RH.config
  local inst = CTLD:New(coalition.side.BLUE, { "" }, "RH Logistics")
  inst:SetOwnSetPilotGroups(SET_GROUP:New():FilterCoalitions("blue"):FilterCategories({ "helicopter", "plane" }):FilterStart())

  inst.enableslingload = true
  inst.enableChinookGCLoading = true
  inst.enableFixedWing = true
  inst.dropcratesanywhere = true
  -- The load circle is 150 m at a FARP tent and 500 m at a logistics center. A MASH is built
  -- inside that circle, so MOOSE must not refuse a build there.
  inst.nobuildinloadzones = false
  -- Chinooks unload through the rearm/refuel window. Those crates were never "moved" by CTLD,
  -- and the default refuses to build them until they are packed and dropped again.
  inst.movecratesbeforebuild = false
  inst.forcehoverload = false
  -- Hovering into a load zone must not pull crates aboard. The pilot loads on purpose.
  inst.hoverautoloading = false
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
    inst:AddTroopsCargo(t.name, { t.template }, CTLD_CARGO.Enum.TROOPS, t.size, c.troopWeight, nil, t.subcat)
  end
  local function addCrates(name, template, kind, crates, mass, subcat)
    inst:AddCratesCargo(name, { template }, kind, crates, mass, nil, subcat, nil, nil, nil, "Cargos", inst.basetype, nil, inst.basetype)
  end
  for _, v in ipairs(c.vehicles) do
    local crates = c.testVehicleCrates or v.crates
    addCrates(v.name, v.template, CTLD_CARGO.Enum.VEHICLE, crates, v.mass, v.subcat)
  end
  ctld.ensureKitTemplate(c.kits.farp.template)
  ctld.ensureKitTemplate(c.kits.mash.template)
  if c.kits.generalSupply then ctld.ensureKitTemplate(c.kits.generalSupply.template) end
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
  if RH.logistics.discoverEditorPads then RH.logistics.discoverEditorPads() end
  if RH.logistics.assignFarpNames then RH.logistics.assignFarpNames() end
  if RH.logistics.equipEditorFarps then RH.logistics.equipEditorFarps() end
  if RH.logistics.refreshMapLabels then RH.logistics.refreshMapLabels() end
  local notes = {}
  for _, farp in ipairs(RH.logistics.farps()) do
    local atTent = ctld.addFarpZone(farp)
    table.insert(notes, (farp.label or farp.name) .. (atTent and " (tent)" or " (zone center, no tent found)"))
  end
  if #notes > 0 then
    RH.dcs.message("blue", "Logistics load zones shown in blue for 60 seconds: " .. table.concat(notes, ", ")
      .. ". A logistics center covers 500 m. A FARP tent covers 150 m. Crate counts stay on the map.", 25)
  end
  if RH.logistics.refreshPlacedCenters then RH.logistics.refreshPlacedCenters() end
  if RH.logistics.refreshMapLabels then RH.logistics.refreshMapLabels() end
  ctld.installHooks(inst)
  ctld.guardChinook(inst)
  ctld.installMenus(inst)
  inst:__Start(2)
  -- Once the world snapshot exists it restores vehicles and crates itself. Loading CTLD's
  -- csv as well would build a second copy. The first run still reads the csv, so a Humvee
  -- saved only there can come back once and then join the snapshot.
  if inst.enableLoadSave and not (RH.state.world and RH.state.world.baselineReady) then
    inst:__Load(10)
  end
  return inst
end

-- Put a freshly built vehicle 10 m behind the tail, facing the same way as the helicopter.
function ctld.placeBehind(group, pilot)
  if not group or not pilot or not group:IsAlive() or not pilot:IsAlive() then return end
  local heading = pilot:GetHeading() or 0
  local airframe = RH.config.airframes[pilot:GetTypeName()]
  local length = airframe and airframe.length or 15
  local dest = pilot:GetCoordinate():Translate(length / 2 + 10, (heading + 180) % 360)
  group:InitZone(dest)
  group:InitHeading(heading)
  group:Respawn(nil, true)
end

ctld.chinookCargoMessage = "The Chinook loads and unloads crates from the rearm/refuel cargo menu. Get Crates puts them on the ground. Unload at the tent, then use Return crates to tent."

function ctld.isChinook(unit)
  return unit and unit.GetTypeName and unit:GetTypeName() == "CH-47Fbl1"
end

function ctld.cargoVec2(cargo)
  if not cargo then return nil end
  if cargo.GetVec2 then
    local point = cargo:GetVec2()
    if point and point.x then return point end
  end
  if cargo.GetCoordinate then
    local coord = cargo:GetCoordinate()
    if coord and coord.GetVec2 then
      local point = coord:GetVec2()
      if point and point.x then return point end
    end
  end
  if cargo.x and cargo.y then return { x = cargo.x, y = cargo.y } end
end

function ctld.spawnedCratesNearby(inst, point, reach)
  local count = 0
  for _, crate in pairs(inst.Spawned_Cargo or {}) do
    local body = crate.GetPositionable and crate:GetPositionable()
    local alive = body and (not body.IsAlive or body:IsAlive())
    local pos = (alive and ctld.cargoVec2(body)) or ctld.cargoVec2(crate)
    if pos and util.distance(pos, point) <= reach then count = count + 1 end
  end
  return count
end

-- Chinook ground-crew cargo is not CTLD boarded cargo. Counting it here as well double-books the weight.
function ctld.forgetChinookGroundCrewCrates(inst)
  if not inst or not inst.Loaded_Cargo or not UNIT or not UNIT.FindByName then return end
  local gc = CTLD_CARGO and CTLD_CARGO.Enum and CTLD_CARGO.Enum.GCLOADABLE
  for unitName, loaded in pairs(inst.Loaded_Cargo) do
    local unit = UNIT:FindByName(unitName)
    if ctld.isChinook(unit) and type(loaded) == "table" and loaded.Cargo then
      local keep = {}
      local crates = 0
      for _, item in pairs(loaded.Cargo) do
        local kind = item and item.GetType and item:GetType()
        local groundCrew = item and (item.ClassName == "DYNAMICCARGO" or (gc and kind == gc))
        if not groundCrew then
          keep[#keep + 1] = item
          if kind ~= (CTLD_CARGO and CTLD_CARGO.Enum.TROOPS) and kind ~= (CTLD_CARGO and CTLD_CARGO.Enum.ENGINEERS) then
            crates = crates + 1
          end
        end
      end
      loaded.Cargo = keep
      loaded.Cratesloaded = crates
    end
  end
end

function ctld.guardChinook(inst)
  if not inst then return end
  inst.hoverautoloading = false
  local function block(methodName)
    local inner = inst[methodName]
    if not inner then return end
    inst[methodName] = function(self, Group, Unit, ...)
      if ctld.isChinook(Unit) then
        self:_SendMessage(ctld.chinookCargoMessage, 15, false, Group)
        return self
      end
      return inner(self, Group, Unit, ...)
    end
  end
  block("_GetAndLoad")
  block("_LoadCratesNearby")
  block("_UnloadCrates")
  block("_UnloadSingleCrateSet")
  local handler = inst._EventHandler
  if handler then
    function inst:_EventHandler(EventData)
      handler(self, EventData)
      local id = EventData and EventData.id
      if EVENTS and (id == EVENTS.DynamicCargoLoaded or id == EVENTS.DynamicCargoUnloaded or id == EVENTS.DynamicCargoRemoved) then
        ctld.forgetChinookGroundCrewCrates(self)
      end
    end
  end
end

function ctld.showLoadZones(group)
  local seconds = RH.config.farp.displayCirclesFor or 60
  local drawn = 0
  for _, farp in ipairs(RH.logistics.farps()) do
    ctld.ensureFarpZone(farp)
    drawn = drawn + ctld.drawLoadZones(farp)
  end
  if RH.logistics.refreshMapLabels then RH.logistics.refreshMapLabels() end
  ctld.reply(group, string.format("Logistics zones shown for %d seconds. Crate counts stay on the map.", seconds))
  return drawn
end

function ctld.attachReturnCommand(inst, group, unit)
  if not group or not MENU_GROUP_COMMAND then return end
  group.RHReturnParents = group.RHReturnParents or {}
  local parents = {}
  if group.CTLDTopmenu then table.insert(parents, group.CTLDTopmenu) end
  if group.MyTopCratesMenu then table.insert(parents, group.MyTopCratesMenu) end
  for _, parent in ipairs(parents) do
    if not group.RHReturnParents[parent] then
      local commands = {
        { "Show logistics zones", function() ctld.showLoadZones(group) end },
        { "Return crates to tent", function() ctld.returnCratesToTent(inst, group, unit) end },
      }
      for _, command in ipairs(commands) do
        local item = MENU_GROUP_COMMAND:New(group, command[1], parent, command[2])
        if item and item.Refresh then item:Refresh() end
      end
      group.RHReturnParents[parent] = true
    end
  end
end

function ctld.liveUnit(group, fallback)
  local function alive(u)
    if not u or not u.GetVec2 then return nil end
    if u.IsAlive and not u:IsAlive() then return nil end
    local point = u:GetVec2()
    if point and point.x then return u end
  end
  if group and group.GetUnits then
    local units = group:GetUnits() or {}
    for _, u in pairs(units) do
      if u and u.GetPlayerName and u:GetPlayerName() and alive(u) then return u end
    end
    for _, u in pairs(units) do
      if alive(u) then return u end
    end
  end
  return alive(fallback)
end

function ctld.nearestTent(point, radius)
  local best, bestDist
  for _, static in ipairs(RH.dcs.staticObjects()) do
    if isLogisticsTent(static) then
      local d = util.distance(static, point)
      if d <= radius and (not bestDist or d < bestDist) then best, bestDist = static, d end
    end
  end
  return best
end

-- The helicopter parks at the tent. The saved FARP point can be the pad or the zone center,
-- which is far enough away that a 500 m check from the helicopter misses.
function ctld.farpForReturn(point)
  local reach = RH.config.farp.loadRadius or 150
  local tent = ctld.nearestTent(point, reach)
  local farp = RH.logistics.farpAt(tent or point, tent and 1000 or 500)
  if farp or not tent then return farp, tent end
  local pad, padDist
  for _, static in ipairs(RH.dcs.staticObjects()) do
    local kind = static.typeName or ""
    if (kind == "FARP" or kind == "Invisible FARP" or kind == "SINGLE_HELIPAD") and static.side ~= "red" then
      local d = util.distance(static, tent)
      if d <= 400 and (not padDist or d < padDist) then pad, padDist = static, d end
    end
  end
  local spot = pad or tent
  local name = (pad and pad.name and pad.name ~= "" and pad.name) or (tent.name ~= "" and tent.name) or "FARP"
  if RH.state.farps[name] then return RH.state.farps[name], tent end
  return RH.logistics.register(name, spot, {
    editor = true,
    label = RH.logistics.pickFarpName(),
  }), tent
end

function ctld.returnCratesToTent(inst, group, unit)
  unit = ctld.liveUnit(group, unit) or unit
  local point = unit and unit.GetVec2 and unit:GetVec2()
  local farp = point and ctld.farpForReturn(point)
  if not farp then
    ctld.reply(group, "Park within 150 m of the FARP tent, then return the crates.")
    return
  end
  local reach = RH.config.farp.loadRadius or 150
  if inst and ctld.spawnedCratesNearby(inst, point, reach) == 0 then
    local worth = 0
    local removed = 0
    for name, cargo in pairs(inst.DynamicCargo or {}) do
      local pos = ctld.cargoVec2(cargo)
      if pos and util.distance(pos, point) <= reach then
        worth = worth + RH.logistics.crateWorth(cargo.GetName and cargo:GetName() or name)
        if cargo.Destroy then cargo:Destroy(false) end
        inst.DynamicCargo[name] = nil
        removed = removed + 1
      end
    end
    if removed > 0 then
      local added = RH.logistics.returnCrates(farp, worth)
      ctld.reply(group, string.format("%d crates returned to %s stock (now %s).", added, RH.logistics.displayName(farp),
        RH.logistics.hasUnlimitedCrates(farp) and "unlimited" or tostring(farp.crates)))
      return
    end
  end
  if not inst or not inst._RemoveCratesNearby then return end
  local previous = inst.CrateDistance
  inst.CrateDistance = math.max(previous or 50, RH.config.farp.loadRadius or 150)
  local ok, err = pcall(inst._RemoveCratesNearby, inst, group, unit)
  inst.CrateDistance = previous
  if not ok then util.log("return crates failed: %s", tostring(err)) end
end

-- Manage Crates already has eight MOOSE entries. The return command also sits on the CTLD
-- menu itself, and it is added again whenever MOOSE rebuilds that menu.
function ctld.installMenus(inst)
  local refresh = inst._RefreshF10Menus
  if not refresh then return end
  function inst:_RefreshF10Menus()
    refresh(self)
    if not UNIT or not UNIT.FindByName then return end
    for key, value in pairs(self.CtldUnits or {}) do
      local unitName = type(value) == "string" and value or key
      if type(unitName) == "string" then
        local unit = UNIT:FindByName(unitName)
        local group = unit and unit.GetGroup and unit:GetGroup()
        ctld.attachReturnCommand(self, group, unit)
      end
    end
  end
end

function ctld.installHooks(inst)
  -- Per-FARP crate stock. LCs and ships are unlimited; FARP construction crates only come from LCs and ships.
  function inst:CanGetCrates(Group, Unit, Cargo, number)
    local point = Unit and Unit.GetVec2 and Unit:GetVec2()
    local farp = point and RH.logistics.farpAt(point)
    if not farp and point and RH.logistics.nearestTent then
      local tent = RH.logistics.nearestTent(point, RH.config.farp.loadRadius or 150)
      if tent then farp = RH.logistics.farpAt(tent, 1000) end
    end
    if not farp then return true end
    local cargoName = Cargo:GetName()
    local kit = kitName(cargoName)
    if (kit == "farp" or RH.logistics.isGeneralSupply(cargoName)) and not RH.logistics.hasUnlimitedCrates(farp) then
      ctld.reply(Group, "General supply and FARP crates are only available at Logistics Centers and ships.")
      return false
    end
    local count = tonumber(number) or Cargo:GetCratesNeeded() or 1
    if not RH.logistics.takeCrates(farp, count) then
      ctld.reply(Group, string.format("%s only has %d crates left. Ask a C-130 or a convoy to resupply it.", RH.logistics.displayName(farp), farp.crates))
      return false
    end
    return true
  end

  function inst:OnAfterRemoveCratesNearby(From, Event, To, Group, Unit, Cargotable)
    local farp = Unit and RH.logistics.farpAt(Unit:GetVec2(), 500)
    if farp and Cargotable then
      local worth = 0
      for _, cargo in pairs(Cargotable) do
        local name = cargo.GetName and cargo:GetName() or ""
        worth = worth + RH.logistics.crateWorth(name)
      end
      local added = RH.logistics.returnCrates(farp, worth)
      if added > 0 then
        ctld.reply(Group, string.format("%d crates returned to %s stock (now %s).", added, RH.logistics.displayName(farp),
          RH.logistics.hasUnlimitedCrates(farp) and "unlimited" or tostring(farp.crates)))
      end
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
      ctld.reply(Group, "General supply is not a FARP. Drop it at a FARP tent and use Return crates to tent. Each crate adds 5.")
      return false
    end
    return true
  end

  function inst:OnAfterCratesBuildStarted(From, Event, To, Group, Unit, cargoName)
    if type(cargoName) == "table" and cargoName.GetName then cargoName = cargoName:GetName() end
    if RH.logistics.isGeneralSupply(cargoName) then return end
    if cargoName ~= RH.config.kits.farp.name then return end
    local point = ctld.buildPoint(Unit) or (Unit and Unit.GetVec2 and Unit:GetVec2())
    if not point then return end
    local player = Unit and Unit.GetPlayerName and Unit:GetPlayerName() or "A pilot"
    local farp, reason = RH.logistics.buildFarp(point, player)
    if not farp then ctld.reply(Group, "FARP was not marked: " .. tostring(reason)) end
  end

  function inst:OnAfterCratesBuild(From, Event, To, Group, Unit, Vehicle)
    if not Group or not Vehicle then return end
    local kit = templateKit(Vehicle:GetName())
    if kit == "generalSupply" or RH.logistics.isGeneralSupply(Vehicle:GetName()) then
      Vehicle:Destroy(false)
      ctld.reply(Group, "General supply is not a FARP. Use Return crates to tent. Each crate adds 5 to that FARP.")
      return
    end
    if not kit then
      ctld.placeBehind(Vehicle, Unit)
      return
    end
    local point = Vehicle:GetVec2()
    local behind = ctld.buildPoint(Unit)
    if behind then point = behind end
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
