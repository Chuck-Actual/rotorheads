RH = RH or {}

local util = RH.util

-- Snapshot of every ground group, ship, and static. The server hook writes it into
-- RH Campaign A.miz or B.miz, the file the next launch hosts and the Mission Editor opens.
local world = {}
RH.world = world

-- Recreated by other campaign systems. Saving them here would spawn a second copy.
local EXCLUDE_PREFIXES = {
  "Garrison ",
  "Convoy ",
  "Factory troops ",
  "Insurgents",
  "Havoc",
  "Red CAP",
  "Paratroopers",
  "Supply convoy",
  "Convoy escort",
  "Mi-26 ",
  "RH Pilot ",
  "Downed Pilot",
}

function world.excluded(name)
  if type(name) ~= "string" or name == "" then return true end
  for _, prefix in ipairs(EXCLUDE_PREFIXES) do
    if name:sub(1, #prefix) == prefix then return true end
  end
  -- The template itself stays in the mission file. A built copy is named with # or -1.
  if name:sub(1, 7) == "RH_TPL_" and not string.find(name, "#", 1, true) and not string.find(name, "%-%d+$") then
    return true
  end
  -- The hospital tent is spawned from RH.state.mashes. Saving it here put a second tent on the airfield.
  if RH.logistics and RH.logistics.isMashTent and RH.logistics.isMashTent({ name = name }) then return true end
  return false
end

function world.farpOwned(name)
  if type(name) ~= "string" or not RH.state or not RH.state.farps then return false end
  for farpName, farp in pairs(RH.state.farps) do
    local labels = { farpName }
    if type(farp) == "table" then
      labels[#labels + 1] = farp.label
      labels[#labels + 1] = farp.name
    end
    for _, label in ipairs(labels) do
      if type(label) == "string" and label ~= "" then
        if name == label or name:sub(1, #label + 1) == label .. " " then return true end
      end
    end
  end
  -- A rename leaves the old service Humvee in the save. The FARP spawner places the current one.
  if name:sub(1, 5) == "FARP " and name:sub(-7) == " Humvee" then return true end
  return false
end

-- alive is a list of { name, x, y } already in the mission when it starts.
function world.plan(saved, alive)
  saved = saved or {}
  local desired = {}
  for _, obj in ipairs(saved.objects or {}) do
    if obj.name and not world.excluded(obj.name) then desired[obj.name] = obj end
  end
  local baseline = saved.baseline or {}
  local here = {}
  for _, obj in ipairs(alive or {}) do
    if obj.name and not world.excluded(obj.name) then here[obj.name] = obj end
  end
  local spawn, destroy, adopt, refresh = {}, {}, {}, {}
  for name, obj in pairs(desired) do
    if world.farpOwned(name) then
      -- The FARP spawner places the pad and its tent, depots, and Humvee.
    elseif not here[name] then
      spawn[#spawn + 1] = obj
    elseif obj.x and here[name].x and util.distance(obj, here[name]) > 25 then
      refresh[#refresh + 1] = obj
    end
  end
  for name in pairs(here) do
    if not desired[name] and not world.farpOwned(name) then
      if baseline[name] then destroy[#destroy + 1] = name else adopt[#adopt + 1] = name end
    end
  end
  local function byName(a, b)
    local an = type(a) == "table" and a.name or a
    local bn = type(b) == "table" and b.name or b
    return tostring(an) < tostring(bn)
  end
  table.sort(spawn, byName)
  table.sort(refresh, byName)
  table.sort(destroy)
  table.sort(adopt)
  return { spawn = spawn, destroy = destroy, adopt = adopt, refresh = refresh }
end

-- What the hook needs to write every FARP into the mission file as a real pad with its own warehouse.
function world.describeFarps(state)
  local farps = {}
  for _, name in ipairs(util.keys(RH.state.farps or {})) do
    local farp = RH.state.farps[name]
    if type(farp) == "table" and (farp.pending or farp.built or farp.editor) and farp.x and farp.y then
      farps[#farps + 1] = {
        name = name, x = farp.x, y = farp.y, lc = farp.lc == true, editor = farp.editor == true,
        pending = farp.pending == true, freq = farp.freq,
      }
    end
  end
  state.farps = farps
  local pads = {}
  for name, stock in pairs(RH.state.padStock or {}) do
    if type(stock) == "table" and type(stock.fuelKg) == "number" and stock.fuelKg >= 0 and stock.fuelKg < 1000000 then
      pads[name] = stock.fuelKg
    end
  end
  state.pads = pads
  local fcfg = RH.config.farp or {}
  state.farpServices = fcfg.services
  state.airframes = fcfg.airframes
  local helicopters = {}
  for typeName, info in pairs(RH.config.airframes or {}) do
    if type(info) == "table" and not info.fixedWing then helicopters[#helicopters + 1] = typeName end
  end
  table.sort(helicopters)
  state.helicopters = #helicopters > 0 and helicopters or nil
end

-- A mission the hook wrote carries this zone. In that file the units are already the war.
function world.isSaveCopy()
  if not RH.dcs.zonesWithPrefix then return false end
  local ok, zones = pcall(RH.dcs.zonesWithPrefix, "RH_SAVE_COPY")
  return ok and type(zones) == "table" and #zones > 0
end

-- The hook stamps the save time on the marker. Each export is at most 30 seconds behind the save.
world.STALE_AFTER = 300

function world.saveCopyIsStale(saved)
  if not RH.dcs.zoneProperty or type(saved) ~= "table" or type(saved.savedAt) ~= "number" then return false end
  local ok, stamp = pcall(RH.dcs.zoneProperty, "RH_SAVE_COPY", "savedAt")
  stamp = ok and tonumber(stamp) or nil
  if not stamp or stamp <= 0 then return false end
  return saved.savedAt - stamp > world.STALE_AFTER
end

function world.capture()
  if not RH.dcs.snapshotGround then return false end
  local roster = RH.dcs.snapshotGround() or {}
  local state = RH.state.world or { baseline = {} }
  state.baseline = state.baseline or {}
  if not state.baselineReady then
    state.baseline = {}
    for _, obj in ipairs(roster) do
      if not world.excluded(obj.name) and not world.farpOwned(obj.name) then
        state.baseline[obj.name] = true
      end
    end
    state.baselineReady = true
  end
  local objects = {}
  for _, obj in ipairs(roster) do
    if not world.excluded(obj.name) then
      if world.farpOwned(obj.name) then obj.origin = "farp"
      elseif state.baseline[obj.name] then obj.origin = "baseline"
      else obj.origin = "runtime" end
      objects[#objects + 1] = obj
    end
  end
  table.sort(objects, function(a, b) return tostring(a.name) < tostring(b.name) end)
  state.objects = objects
  state.seen = state.seen or {}
  for _, obj in ipairs(objects) do state.seen[obj.name] = true end
  world.describeFarps(state)
  state.savedAt = RH.dcs.wallclock()
  RH.state.world = state
  local path = RH.dcs.savePath and RH.dcs.savePath("world.lua")
  if path and RH.dcs.writeFile then RH.dcs.writeFile(path, util.serialize(state)) end
  world._payload = util.serialize(state)
  return true
end

-- The server hook asks for this. It has file access even when the mission scripting sandbox does not.
function world.cachePayload()
  local ok, err = pcall(world.capture)
  if not ok then
    world._payload = "error: " .. tostring(err)
  end
  world._payload = world._payload or "error: nothing captured"
  return #world._payload
end

function world.payloadSlice(index, size)
  local text = world._payload or ""
  size = size or 4000
  index = index or 1
  local from = (index - 1) * size + 1
  return text:sub(from, from + size - 1)
end

-- DCS's own Esc > Save Mission includes script-spawned units. Attach the campaign so that file can resume the war.
function world.installOfficialSave()
  local dcsWorld = _G.world
  if type(dcsWorld) ~= "table" or type(dcsWorld.setPersistenceHandler) ~= "function" then
    util.log("DCS Save Mission persistence is not in this build")
    return
  end
  dcsWorld.setPersistenceHandler("Rotorheads", function()
    return { campaign = RH.state }
  end)
  util.log("campaign will be stored inside a DCS Save Mission file")
end

function world.readOfficialSave()
  if RH.state.world and RH.state.world.baselineReady then return false end
  local dcsWorld = _G.world
  if type(dcsWorld) ~= "table" or type(dcsWorld.getPersistenceData) ~= "function" then return false end
  local ok, data = pcall(dcsWorld.getPersistenceData, "Rotorheads")
  if not ok or type(data) ~= "table" or type(data.campaign) ~= "table" then return false end
  for k, v in pairs(data.campaign) do RH.state[k] = v end
  util.log("loaded the campaign stored in this mission's DCS save")
  return true
end

-- In a save copy the editor is allowed to add, move, and delete units. What the file holds is kept.
function world.planSaveCopy(saved, alive)
  local plan = world.plan(saved, alive)
  return { spawn = {}, destroy = {}, adopt = plan.adopt, refresh = {} }
end

function world.restore()
  local saved = RH.state.world
  if not saved or not saved.baselineReady or not RH.dcs.groundRoster then return { spawn = {}, destroy = {}, adopt = {}, refresh = {} } end
  world.hostingSaveCopy = world.isSaveCopy()
  if world.hostingSaveCopy and world.saveCopyIsStale(saved) then
    world.hostingSaveCopy = false
    util.log("world restore: the hosted save copy is older than the campaign save, so missing units are put back")
    RH.dcs.message("all", "ROTORHEADS: this campaign file is older than the save. Host the newer RH Campaign file. Missing units were put back from the save.", 60)
  end
  local plan
  if world.hostingSaveCopy then
    plan = world.planSaveCopy(saved, RH.dcs.groundRoster())
    util.log("world restore: the hosted mission is a save copy, so its units are used as they are")
  else
    plan = world.plan(saved, RH.dcs.groundRoster())
  end
  for _, name in ipairs(plan.destroy) do
    if RH.dcs.destroyNamed then RH.dcs.destroyNamed(name) end
  end
  for _, obj in ipairs(plan.refresh) do
    if RH.dcs.destroyNamed then RH.dcs.destroyNamed(obj.name) end
    if RH.dcs.spawnSnapshot then RH.dcs.spawnSnapshot(obj) end
  end
  for _, obj in ipairs(plan.spawn) do
    if RH.dcs.spawnSnapshot then RH.dcs.spawnSnapshot(obj) end
  end
  saved.baseline = saved.baseline or {}
  for _, name in ipairs(plan.adopt) do saved.baseline[name] = true end
  util.log("world restore: %d spawned, %d moved, %d removed, %d new editor units kept",
    #plan.spawn, #plan.refresh, #plan.destroy, #plan.adopt)
  return plan
end

return world
