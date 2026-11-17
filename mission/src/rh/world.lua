RH = RH or {}

local util = RH.util

-- Snapshot of every ground group, ship, and static. This is what comes back on the next
-- mission start, and what the server hook writes into RH_Editor.miz for the Mission Editor.
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
  return false
end

function world.farpOwned(name)
  if type(name) ~= "string" or not RH.state or not RH.state.farps then return false end
  for farpName in pairs(RH.state.farps) do
    if name == farpName or name:sub(1, #farpName + 1) == farpName .. " " then return true end
  end
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
  state.savedAt = RH.dcs.wallclock()
  RH.state.world = state
  local path = RH.dcs.savePath and RH.dcs.savePath("world.lua")
  if path and RH.dcs.writeFile then RH.dcs.writeFile(path, util.serialize(state)) end
  local ok, err = pcall(world.exportEditor)
  if not ok then util.log("editor export error: %s", tostring(err)) end
  return true
end

function world.savedRoot()
  if not RH.dcs.filesEnabled or not RH.dcs.filesEnabled() then return nil end
  if not lfs or not lfs.writedir then return nil end
  local base = lfs.writedir()
  if type(base) ~= "string" or base == "" then return nil end
  if not base:match("[/\\]$") then base = base .. "\\" end
  return base
end

function world.fileExists(path)
  if type(path) ~= "string" or path == "" or not io then return false end
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

-- Prefer the mission the hook saw, then the configured test mission. Never read the editor copy back in.
function world.pickSource(root, hint, exists)
  exists = exists or world.fileExists
  local function accept(path)
    if type(path) ~= "string" then return nil end
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" or path:lower():match("rh_editor%.miz$") then return nil end
    if exists(path) then return path end
    return nil
  end
  local chosen = accept(hint)
  if chosen then return chosen end
  return accept(root .. (RH.config.editorSource or "Missions\\RH Test.miz"))
end

function world.writeNote(text)
  local root = world.savedRoot()
  if not root or not RH.dcs.writeFile then return end
  RH.dcs.writeFile(root .. "Missions\\Rotorheads\\last_export.txt", text .. "\r\n")
  util.log("editor: %s", (text:gsub("\r\n", " | ")))
end

-- Builds Saved Games\DCS\Missions\RH_Editor.miz from the running mission plus the snapshot.
-- This runs in the mission script, which can already write files. The server hook cannot see the miz.
function world.exportEditor()
  local root = world.savedRoot()
  if not root then return end
  if not RH.miz or not RH.miz.exportFile then
    world.writeNote("Editor mission was not built: the mission packer is not loaded.")
    return
  end
  local hint = RH.dcs.readFile and RH.dcs.readFile(root .. "rotorheads\\active_mission.txt") or nil
  local src = world.pickSource(root, hint)
  local dest = root .. "Missions\\RH_Editor.miz"
  if not src then
    world.writeNote("Editor mission was not built. Put the mission at Saved Games\\DCS\\Missions\\RH Test.miz, or launch it so the hook can record the path.")
    return
  end
  local ok, err = RH.miz.exportFile(src, root .. "rotorheads\\world.lua", dest)
  if ok then
    world.writeNote("Wrote " .. dest .. "\r\nFrom " .. src .. "\r\nOpen RH_Editor.miz in the Mission Editor. It updates about every 30 seconds while the mission is running.")
  else
    world.writeNote("Editor mission failed.\r\n" .. tostring(err) .. "\r\nSource " .. src)
  end
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

function world.restore()
  local saved = RH.state.world
  if not saved or not saved.baselineReady or not RH.dcs.groundRoster then return { spawn = {}, destroy = {}, adopt = {}, refresh = {} } end
  local plan = world.plan(saved, RH.dcs.groundRoster())
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
