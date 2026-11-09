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

local function restart(reason)
  log("restarting mission: " .. reason)
  toMission("RH.shutdown()")
  net.load_mission(DCS.getMissionFilename())
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
  for _, id in ipairs(net.get_player_list()) do
    if id ~= net.get_server_id() then
      local side = net.get_player_info(id, "side")
      if side and side ~= 0 then flying = flying + 1 end
    end
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
