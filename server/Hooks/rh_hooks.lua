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

local function withSlash(path)
  if type(path) ~= "string" or path == "" then return nil end
  if not path:match("[/\\]$") then path = path .. "\\" end
  return path
end

local function writeText(path, text)
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if dir then lfs.mkdir(dir) end
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

local function missionString(code)
  local results = { pcall(net.dostring_in, "mission", code) }
  if not results[1] then return nil, tostring(results[2]) end
  if type(results[2]) == "string" then return results[2] end
  if type(results[3]) == "string" then return results[3] end
  return nil, "mission returned nothing"
end

local function findSource()
  local tried = {}
  local running = {}
  local function add(list, path)
    if type(path) == "string" and path ~= "" then
      list[#list + 1] = path
      tried[#tried + 1] = path
    end
  end
  local ok, name = pcall(DCS.getMissionFilename)
  if ok and type(name) == "string" and name ~= "" then
    if not name:match("^%a:[/\\]") and not name:match("^\\\\") then
      add(running, withSlash(lfs.currentdir()) .. name)
    end
    add(running, name)
  end
  -- The mission that is actually running wins, including RH_Editor.miz after a hand edit.
  for _, path in ipairs(running) do
    if lfs.attributes(path) then return path, tried end
  end
  local home = os.getenv("USERPROFILE") or ""
  local roots = { withSlash(lfs.writedir()) }
  if home ~= "" then
    roots[#roots + 1] = home .. "\\Saved Games\\DCS\\"
    roots[#roots + 1] = home .. "\\Saved Games\\DCS.dcs_serverrelease\\"
    roots[#roots + 1] = home .. "\\Saved Games\\DCS.openbeta\\"
  end
  for _, root in ipairs(roots) do
    local path = root .. "Missions\\RH Test.miz"
    tried[#tried + 1] = path
    if lfs.attributes(path) then return path, tried end
  end
  return nil, tried
end

local function loadPacker()
  if RHHook.packer then return RHHook.packer end
  local home = os.getenv("USERPROFILE") or ""
  local bases = { withSlash(lfs.writedir()) .. "Scripts\\Hooks\\" }
  if home ~= "" then bases[#bases + 1] = home .. "\\Saved Games\\DCS\\Scripts\\Hooks\\" end
  local errors = {}
  for _, base in ipairs(bases) do
    local inflatePath = base .. "inflate.lua"
    local mizPath = base .. "rh_miz.lua"
    if lfs.attributes(inflatePath) and lfs.attributes(mizPath) then
      local okI, inflateOrErr = pcall(dofile, inflatePath)
      if not okI then
        errors[#errors + 1] = tostring(inflateOrErr)
      else
        local okM, mizOrErr = pcall(dofile, mizPath)
        if not okM then
          errors[#errors + 1] = tostring(mizOrErr)
        elseif type(mizOrErr) == "table" and type(mizOrErr.exportText) == "function" then
          if mizOrErr.use then mizOrErr.use(inflateOrErr) end
          RHHook.packer = mizOrErr
          return mizOrErr
        else
          errors[#errors + 1] = "rh_miz.lua did not return the packer"
        end
      end
    else
      errors[#errors + 1] = "missing " .. inflatePath .. " or " .. mizPath
    end
  end
  return nil, table.concat(errors, " | ")
end

local function notePaths(source)
  local paths = {}
  local function add(path)
    if path and path ~= "" then paths[#paths + 1] = path end
  end
  local home = os.getenv("USERPROFILE") or ""
  if home ~= "" then add(home .. "\\Saved Games\\DCS\\Missions\\Rotorheads\\last_export.txt") end
  add(withSlash(lfs.writedir()) .. "Missions\\Rotorheads\\last_export.txt")
  add(withSlash(lfs.writedir()) .. "rotorheads\\last_export.txt")
  if source then
    local dir = source:match("^(.*)[/\\][^/\\]+$")
    if dir then add(dir .. "\\Rotorheads\\last_export.txt") end
  end
  return paths
end

local function writeNote(source, text)
  log(text:gsub("[\r\n]+", " | "))
  local wrote = false
  for _, path in ipairs(notePaths(source)) do
    if writeText(path, text .. "\r\n") then wrote = true end
  end
  if not wrote then log("could not write last_export.txt") end
end

local function pullWorld()
  local countText, err = missionString("return tostring(RH.world.cachePayload())")
  if not countText then return nil, err end
  local count = tonumber(countText:match("%d+"))
  if not count then return nil, "mission answered: " .. countText end
  if count > 2000000 then return nil, "world save is too large" end
  local size = 4000
  local parts = {}
  local n = math.max(1, math.ceil(count / size))
  if count == 0 then return "" end
  for i = 1, n do
    local quoted, partErr = missionString(string.format("return string.format(\"%%q\", RH.world.payloadSlice(%d, %d))", i, size))
    if not quoted then return nil, partErr or ("missing slice " .. i) end
    local fn, loadErr = loadstring("return " .. quoted)
    if not fn then return nil, loadErr end
    if setfenv then setfenv(fn, {}) end
    local ran, part = pcall(fn)
    if not ran or type(part) ~= "string" then return nil, "bad slice " .. i end
    parts[#parts + 1] = part
  end
  local text = table.concat(parts)
  if #text ~= count then return nil, "world save came back short (" .. #text .. " of " .. count .. ")" end
  return text
end

-- Builds RH_Editor.miz beside the running mission. The mission sandbox often cannot write files.
local function exportEditor()
  local source, tried = findSource()
  local worldText, worldErr = pullWorld()
  if not worldText then
    writeNote(source, "Editor mission was not built.\r\nThe mission script did not answer: " .. tostring(worldErr))
    return
  end
  if worldText:sub(1, 6) == "error:" then
    writeNote(source, "Editor mission was not built.\r\n" .. worldText)
    return
  end
  if not source then
    writeNote(nil, "Editor mission was not built.\r\nRH Test.miz was not found.\r\nLooked in " .. table.concat(tried, "\r\n"))
    return
  end
  local packer, packerErr = loadPacker()
  if not packer then
    writeNote(source, "Editor mission was not built.\r\n" .. tostring(packerErr))
    return
  end
  local dir, filename = source:match("^(.*)[/\\]([^/\\]+)$")
  -- The hosted file stays locked until the server stops, so the editor copy is a different file.
  local destName = filename:lower() == "rh_editor.miz" and "RH_Editor_latest.miz" or "RH_Editor.miz"
  local dest = dir .. "\\" .. destName
  local ok, err = packer.exportText(source, worldText, dest)
  if ok then
    writeNote(source, "Wrote " .. dest .. "\r\nFrom " .. source .. "\r\nStop the server, then open this file in the Mission Editor. The mission that is running is left as it is.")
    if not RHHook.told then
      RHHook.told = true
      net.send_chat("Rotorheads saved " .. destName .. ". Stop the server before opening it in the Mission Editor.", true)
    end
  else
    writeNote(source, "Editor mission failed.\r\n" .. tostring(err) .. "\r\nSource " .. source .. "\r\nDestination " .. dest)
    if not RHHook.toldFail then
      RHHook.toldFail = true
      net.send_chat("Rotorheads could not write the editor mission. See Missions\\Rotorheads\\last_export.txt.", true)
    end
  end
end

local function restart(reason)
  log("restarting mission: " .. reason)
  toMission("RH.shutdown()")
  net.load_mission(DCS.getMissionFilename())
end

function RHHook.onSimulationStop()
  if DCS.getModelTime and DCS.getModelTime() > 1 then
    local ok, err = pcall(exportEditor)
    if not ok then log("editor export error: " .. tostring(err)) end
  end
  if not RHHook.shutdownSent then
    RHHook.shutdownSent = true
    toMission("RH.shutdown()")
  end
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
  if DCS.getModelTime() > 1 and now - (RHHook.lastEditorExport or 0) >= 30 then
    RHHook.lastEditorExport = now
    local ok, err = pcall(exportEditor)
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
