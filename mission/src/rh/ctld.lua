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

function ctld.addFarpZone(farp)
  if not ctld.instance then return end
  -- A small zone of our own. The mission-editor zone can be huge, and crates should only load at the tent.
  local zoneName = "RH_LOAD_" .. farp.name
  if not ZONE:FindByName(zoneName) then
    ZONE_RADIUS:New(zoneName, { x = farp.x, y = farp.y }, RH.config.farp.loadRadius)
  end
  ctld.instance:AddCTLDZone(zoneName, CTLD.CargoZoneType.LOAD, SMOKECOLOR.Blue, true, true)
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
  inst.buildtime = 30
  inst.repairtime = 60
  inst.usesubcats = true
  inst.allowcratepickupagain = true
  inst.TroopUnloadDistGroundHook = 15
  inst.useaircraftheadingforbuilds = true
  -- Same CDS box the C-130 loads (22 of them), for helicopters and the Hercules.
  inst.basetype = c.crateModel or "cds_crate"
  inst.C130basetype = inst.basetype

  inst.enableLoadSave = RH.dcs.filesEnabled()
  inst.saveinterval = c.saveInterval
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
    addCrates(v.name, v.template, CTLD_CARGO.Enum.VEHICLE, v.crates, v.mass, v.subcat)
  end
  addCrates(c.kits.farp.name, c.kits.farp.template, CTLD_CARGO.Enum.FOB, c.farp.cratesForFarp, c.farp.farpCrateMass, "Construction")
  addCrates(c.kits.mash.name, c.kits.mash.template, CTLD_CARGO.Enum.FOB, c.mash.crates, c.mash.crateMass, "Construction")
  addCrates(c.kits.outpost.name, c.kits.outpost.template, CTLD_CARGO.Enum.FOB, c.kits.outpost.crates, c.kits.outpost.mass, "Construction")
  addCrates(c.kits.uhRepair.name, c.kits.uhRepair.template, CTLD_CARGO.Enum.FOB, c.kits.uhRepair.crates, c.kits.uhRepair.mass, "Construction")

  for _, ship in ipairs(c.ships) do
    if UNIT:FindByName(ship.unit) then
      inst:AddCTLDZone(ship.unit, CTLD.CargoZoneType.SHIP, SMOKECOLOR.Blue, true, true, ship.length, ship.width)
    end
  end

  ctld.instance = inst
  for _, farp in ipairs(RH.logistics.farps()) do ctld.addFarpZone(farp) end
  ctld.installHooks(inst)
  inst:__Start(2)
  if inst.enableLoadSave then inst:__Load(10) end
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

function ctld.installHooks(inst)
  -- Per-FARP crate stock. LCs and ships are unlimited; FARP construction crates only come from LCs and ships.
  function inst:CanGetCrates(Group, Unit, Cargo, number)
    local farp = RH.logistics.farpAt(Unit:GetVec2())
    if not farp then return true end
    local kit = kitName(Cargo:GetName())
    if kit == "farp" and not RH.logistics.hasUnlimitedCrates(farp) then
      ctld.reply(Group, "FARP crates are only available at Logistics Centers and ships.")
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
    local farp = Unit and RH.logistics.farpAt(Unit:GetVec2())
    if farp and Cargotable then
      local added = RH.logistics.returnCrates(farp, #Cargotable)
      if added > 0 then
        ctld.reply(Group, string.format("%d crates returned to %s stock (now %s).", added, farp.name,
          RH.logistics.hasUnlimitedCrates(farp) and "unlimited" or tostring(farp.crates)))
      end
    end
  end

  function inst:OnAfterTroopsDeployed(From, Event, To, Group, Unit, Troops)
    if not Troops or not Troops:IsAlive() then return end
    local wp = RH.markers.wpzoneFor(Troops:GetVec2())
    if wp then Troops:RouteGroundTo(COORDINATE:NewFromVec2(wp), 15, "Off Road", 2) end
  end

  function inst:OnAfterCratesBuild(From, Event, To, Group, Unit, Vehicle)
    if not Group or not Vehicle then return end
    local kit = templateKit(Vehicle:GetName())
    if not kit then
      ctld.placeBehind(Vehicle, Unit)
      return
    end
    local point = Vehicle:GetVec2()
    if Unit and Unit:IsAlive() then
      local heading = Unit:GetHeading() or 0
      local airframe = RH.config.airframes[Unit:GetTypeName()]
      local length = airframe and airframe.length or 15
      point = Unit:GetCoordinate():Translate(length / 2 + 10, (heading + 180) % 360):GetVec2()
    end
    local player = Unit and Unit:GetPlayerName() or "A pilot"
    local ok, reason
    if kit == "farp" then
      ok, reason = RH.logistics.buildFarp(point, player)
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
