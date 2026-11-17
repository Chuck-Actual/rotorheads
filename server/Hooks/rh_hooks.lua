-- Rotorheads server hook. Copy to Saved Games\DCS.dcs_serverrelease\Scripts\Hooks\ (or Saved Games\DCS\Scripts\Hooks\).
-- Handles chat commands and the automatic restart cycle. Campaign logic lives in the mission (dist/rotorheads.lua).

local RHHook = {
  restartHours = 5,
  warnings = { 1800, 900, 300, 60 },
  restartWhenEmptyAfter = 600,
  -- UCIDs allowed to use -save, e.g. ["0123456789abcdef0123456789abcdef"] = true. Find yours in dcs.log on join.
  admins = {},
  started = nil,
  warned = {},
  shutdownSent = false,
  lastCheck = 0,
  emptySince = nil,
  lastEditorExport = 0,
}

local function log(msg) net.log("[RH hook] " .. msg) end

local function toMission(code)
  net.dostring_in("mission", string.format("a_do_script(%q)", code))
end

local function secondsLeft()
  return RHHook.restartHours * 3600 - DCS.getModelTime()
end

local function fmt(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function savedRoot()
  local base = lfs.writedir()
  if not base:match("[/\\]$") then base = base .. "\\" end
  return base
end

local function editorPaths()
  local mission = DCS.getMissionFilename()
  if type(mission) ~= "string" or mission == "" then return nil end
  local root = savedRoot()
  -- Always this folder, which is the one the Mission Editor opens by default.
  local dest = root .. "Missions\\RH_Editor.miz"
  local world = root .. "rotorheads\\world.lua"
  return mission, world, dest
end

local function exportEditor(reason)
  local mission, world, dest = editorPaths()
  if not mission then
    log("editor export skipped (" .. reason .. "): mission path unavailable")
    return
  end
  log("editor export reading " .. mission)
  if not lfs.attributes(world) then
    log("editor export skipped (" .. reason .. "): no world.lua yet")
    return
  end
  local attr = lfs.attributes(mission)
  if reason ~= "exit" and attr and attr.size and attr.size > 8 * 1024 * 1024 then
    if not RHHook.editorDeferred then
      RHHook.editorDeferred = true
      log("editor export deferred until exit (" .. math.floor(attr.size / 1024) .. " KB mission)")
    end
    return
  end
  local hooks = lfs.writedir() .. "Scripts/Hooks/"
  local okInflate, inflateOrErr = pcall(dofile, hooks .. "inflate.lua")
  if not okInflate then
    log("editor export skipped: " .. tostring(inflateOrErr))
    return
  end
  _G.RH_INFLATE = inflateOrErr
  local chunk, loadErr = loadfile(hooks .. "rh_miz.lua")
  if not chunk then
    log("editor export skipped: " .. tostring(loadErr))
    return
  end
  if setfenv then
    setfenv(chunk, setmetatable({ RH_INFLATE = inflateOrErr }, { __index = _G }))
  end
  local okMiz, mizOrErr = pcall(chunk)
  if not okMiz then
    log("editor export skipped: " .. tostring(mizOrErr))
    return
  end
  local started = DCS.getRealTime()
  local ok, err = mizOrErr.exportFile(mission, world, dest)
  if ok then
    log(string.format("wrote %s (%s, %.1fs)", dest, reason, DCS.getRealTime() - started))
  else
    log("editor export failed (" .. reason .. "): " .. tostring(err))
  end
end

local function restart(reason)
  log("restarting mission: " .. reason)
  toMission("RH.shutdown()")
  net.load_mission(DCS.getMissionFilename())
end

function RHHook.onSimulationStop()
  if not RHHook.shutdownSent then
    RHHook.shutdownSent = true
    toMission("RH.shutdown()")
  end
  local ok, err = pcall(exportEditor, "exit")
  if not ok then log("editor export error: " .. tostring(err)) end
end

function RHHook.onSimulationStart()
  RHHook.warned = {}
  RHHook.shutdownSent = false
  RHHook.emptySince = nil
end

function RHHook.onSimulationFrame()
  local now = DCS.getRealTime()
  if now - RHHook.lastCheck < 5 then return end
  RHHook.lastCheck = now
  if now - RHHook.lastEditorExport >= 30 then
    RHHook.lastEditorExport = now
    local ok, err = pcall(exportEditor, "autosave")
    if not ok then log("editor export error: " .. tostring(err)) end
  end
  if not DCS.isServer() or not DCS.isMultiplayer() then return end

  local left = secondsLeft()
  for _, w in ipairs(RHHook.warnings) do
    if left <= w and not RHHook.warned[w] then
      RHHook.warned[w] = true
      net.send_chat(string.format("Server restart in %d minutes. Return to a FARP, airfield or ship before then.", math.floor(w / 60)), true)
    end
  end
  if left <= 30 and not RHHook.shutdownSent then
    RHHook.shutdownSent = true
    toMission("RH.shutdown()")
  end
  if left <= 0 then
    restart("scheduled")
    return
  end

  -- Restart early when nobody has been flying for a while, so the next player gets a full session.
  local flying = 0
  -- The host counts too: a dedicated server always sits in spectators, a game client hosting may be flying.
  for _, id in ipairs(net.get_player_list()) do
    local side = net.get_player_info(id, "side")
    if side and side ~= 0 then flying = flying + 1 end
  end
  if flying == 0 then
    RHHook.emptySince = RHHook.emptySince or now
    if DCS.getModelTime() > 3600 and now - RHHook.emptySince > RHHook.restartWhenEmptyAfter then
      restart("server empty")
    end
  else
    RHHook.emptySince = nil
  end
end

function RHHook.onPlayerTrySendChat(playerID, msg, all)
  if type(msg) ~= "string" then return msg end
  local cmd = msg:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if cmd:sub(1, 1) ~= "-" then return msg end
  local name = net.get_player_info(playerID, "name") or "Unknown"

  if cmd == "-time" then
    net.send_chat_to("Time until server restart: " .. fmt(secondsLeft()), playerID)
  elseif cmd == "-help" then
    net.send_chat_to("Chat: -time -lives -farps -mash | F10 markers: -smoke,<color> -illumination -wpzone -farp? -extract", playerID)
  elseif cmd == "-lives" or cmd == "-farps" or cmd == "-mash" then
    toMission(string.format("RH.chat.handle(%q, %q)", name, cmd))
  elseif cmd == "-save" then
    local ucid = net.get_player_info(playerID, "ucid")
    if playerID == net.get_server_id() or (ucid and RHHook.admins[ucid]) then
      toMission(string.format("RH.chat.handle(%q, %q)", name, cmd))
    else
      net.send_chat_to("Only server admins can force a save.", playerID)
    end
  end
  return msg
end

DCS.setUserCallbacks(RHHook)
log("loaded")
