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
    for _, name in ipairs({ "RH Manual.miz", "RH Test.miz" }) do
      local path = root .. "Missions\\" .. name
      tried[#tried + 1] = path
      if lfs.attributes(path) then return path, tried end
    end
  end
  return nil, tried
end

-- The save is written into one of two mission files. The one being hosted is locked, so each
-- launch writes the other one, and the next launch hosts that.
RHHook.slots = { "RH Campaign A.miz", "RH Campaign B.miz" }

local function splitPath(path)
  local dir, file = tostring(path or ""):match("^(.*)[/\\]([^/\\]+)$")
  return dir, file
end

local function slotIndex(path)
  local _, file = splitPath(path)
  if not file then return nil end
  for i, name in ipairs(RHHook.slots) do
    if file:lower() == name:lower() then return i end
  end
  return nil
end

local function modified(path)
  local attr = path and lfs.attributes(path)
  return attr and attr.modification or nil
end

function RHHook.slotTarget(source)
  local dir = splitPath(source)
  if not dir then return nil end
  local running = slotIndex(source)
  if running then return dir .. "\\" .. RHHook.slots[3 - running] end
  -- Hosting RH Manual.miz or another file: overwrite the older slot, so the newer one stays as a backup.
  local a, b = dir .. "\\" .. RHHook.slots[1], dir .. "\\" .. RHHook.slots[2]
  local ma, mb = modified(a), modified(b)
  if ma and mb and mb < ma then return b end
  if ma and not mb then return b end
  return a
end

-- Hosting the older slot by mistake would roll the war back. The newer slot wins.
function RHHook.newerSlot(source)
  local running = slotIndex(source)
  if not running then return nil end
  local dir = splitPath(source)
  local other = dir .. "\\" .. RHHook.slots[3 - running]
  local mine, theirs = modified(source), modified(other)
  if mine and theirs and theirs > mine then return other end
  return nil
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

local function worldFilePaths()
  local home = os.getenv("USERPROFILE") or ""
  local paths = { withSlash(lfs.writedir()) .. "rotorheads\\world.lua" }
  if home ~= "" then
    paths[#paths + 1] = home .. "\\Saved Games\\DCS\\rotorheads\\world.lua"
    paths[#paths + 1] = home .. "\\Saved Games\\DCS.dcs_serverrelease\\rotorheads\\world.lua"
    paths[#paths + 1] = home .. "\\Saved Games\\DCS.openbeta\\rotorheads\\world.lua"
  end
  return paths
end

local function readWorldFile()
  for _, path in ipairs(worldFilePaths()) do
    local f = io.open(path, "rb")
    if f then
      local text = f:read("*a")
      f:close()
      if type(text) == "string" and text:sub(1, 1) == "{" then return text, path end
    end
  end
  return nil
end

local function missionScriptPaths()
  local found = {}
  local function add(path)
    if type(path) == "string" and path ~= "" then found[#found + 1] = path end
  end
  local cwd = lfs.currentdir() or ""
  add(cwd .. "\\..\\Scripts\\MissionScripting.lua")
  add(cwd .. "\\..\\..\\Scripts\\MissionScripting.lua")
  local home = os.getenv("USERPROFILE") or ""
  if home ~= "" then
    add(home .. "\\Saved Games\\DCS\\Scripts\\MissionScripting.lua")
  end
  return found
end

-- DCS ships with os, io, and lfs removed from mission scripts. The campaign cannot save until those lines are commented out.
local function allowMissionFiles()
  local blocked = { ["sanitizeModule('os')"] = true, ["sanitizeModule('io')"] = true, ["sanitizeModule('lfs')"] = true }
  local notes = {}
  for _, path in ipairs(missionScriptPaths()) do
    local f = io.open(path, "r")
    if f then
      local text = f:read("*a")
      f:close()
      local changed = false
      local lines = {}
      for line in (text .. "\n"):gmatch("(.-)\n") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if blocked[trimmed] then
          lines[#lines + 1] = line:gsub("sanitizeModule", "--sanitizeModule", 1)
          changed = true
        else
          lines[#lines + 1] = line
        end
      end
      if changed then
        local out = io.open(path, "w")
        if not out then
          notes[#notes + 1] = "Found " .. path .. " but Windows would not let the game rewrite it. Open that file as administrator and put -- in front of sanitizeModule('os'), sanitizeModule('io'), and sanitizeModule('lfs')."
        else
          out:write(table.concat(lines, "\n"))
          out:close()
          notes[#notes + 1] = "Commented out the file block in " .. path .. ". Quit DCS completely and start the server again. The change does nothing until DCS is restarted."
        end
      else
        notes[#notes + 1] = path .. " already allows mission files."
      end
    end
  end
  if #notes == 0 then
    notes[1] = "Could not find Scripts\\MissionScripting.lua next to the running game. In the DCS install folder, edit Scripts\\MissionScripting.lua and put -- in front of sanitizeModule('os'), sanitizeModule('io'), and sanitizeModule('lfs'). Quit DCS completely afterward."
  end
  return table.concat(notes, "\r\n")
end

-- Builds the next campaign file beside the running mission. The mission sandbox often cannot write files.
local function exportEditor()
  if RHHook.switching then return end
  local source, tried = findSource()
  -- a_do_script runs in the mission environment, which is where RH exists. A bare return from the hook does not.
  toMission("if RH and RH.persistence and RH.persistence.save then RH.persistence.save() end")
  local worldText, worldPath = readWorldFile()
  if not worldText then
    local looked = table.concat(worldFilePaths(), "\r\n")
    local access = allowMissionFiles()
    writeNote(source, "Editor mission was not built.\r\nThe 4444-line mission script is loaded. The yellow line in chat is the block: DCS is not letting the mission write files, so there is no unit save to put into a mission.\r\n" .. access .. "\r\nLooked for the unit save at:\r\n" .. looked)
    if not RHHook.toldFail then
      RHHook.toldFail = true
      net.send_chat("Rotorheads cannot save yet. DCS is blocking mission files. Quit DCS after this flight and see last_export.txt.", true)
    end
    return
  end
  if worldText:sub(1, 6) == "error:" then
    writeNote(source, "Editor mission was not built.\r\n" .. worldText)
    return
  end
  if not source then
    writeNote(nil, "Campaign mission was not built.\r\nRH Manual.miz was not found.\r\nLooked in " .. table.concat(tried, "\r\n"))
    return
  end
  local packer, packerErr = loadPacker()
  if not packer then
    writeNote(source, "Campaign mission was not built.\r\n" .. tostring(packerErr))
    return
  end
  local dest = RHHook.slotTarget(source)
  local _, destName = splitPath(dest)
  local ok, err = packer.exportText(source, worldText, dest)
  if ok then
    RHHook.lastExport = dest
    writeNote(source, "Wrote " .. dest .. "\r\nFrom " .. source .. "\r\nUnits from " .. tostring(worldPath)
      .. "\r\nHost " .. destName .. " next. It holds every unit and every FARP as a real pad with its warehouse."
      .. "\r\nTo change the war, stop the server, open " .. destName .. " in the Mission Editor, save it under the same name, and host it.")
    if not RHHook.told then
      RHHook.told = true
      net.send_chat("Rotorheads saved " .. destName .. ". The next restart hosts it. Stop the server before opening it in the Mission Editor.", true)
    end
  else
    writeNote(source, "Editor mission failed.\r\n" .. tostring(err) .. "\r\nSource " .. source .. "\r\nDestination " .. dest)
    if not RHHook.toldFail then
      RHHook.toldFail = true
      net.send_chat("Rotorheads could not write the editor mission. See Missions\\Rotorheads\\last_export.txt.", true)
    end
  end
end

local SHUTDOWN = "if RH and RH.shutdown then RH.shutdown() end"

-- The restart hosts the campaign file that was just written, so built FARPs load as real pads.
local function restart(reason)
  log("restarting mission: " .. reason)
  toMission(SHUTDOWN)
  RHHook.lastExport = nil
  local ok, err = pcall(exportEditor)
  if not ok then log("editor export error: " .. tostring(err)) end
  local target = RHHook.lastExport or DCS.getMissionFilename()
  log("loading " .. tostring(target))
  net.load_mission(target)
end

function RHHook.onSimulationStop()
  if DCS.getModelTime and DCS.getModelTime() > 1 then
    local ok, err = pcall(exportEditor)
    if not ok then log("editor export error: " .. tostring(err)) end
  end
  if not RHHook.shutdownSent then
    RHHook.shutdownSent = true
    toMission(SHUTDOWN)
  end
end

function RHHook.onSimulationStart()
  RHHook.warned = {}
  RHHook.shutdownSent = false
  RHHook.emptySince = nil
  RHHook.switching = false
  RHHook.slotChecked = false
end

-- Runs on the first frame, before the campaign script loads two seconds in.
local function checkSlot()
  RHHook.slotChecked = true
  local source = findSource()
  local newer = source and RHHook.newerSlot(source)
  if newer then
    RHHook.switching = true
    log("hosting " .. source .. " but " .. newer .. " is newer, loading that instead")
    net.load_mission(newer)
    return true
  end
  return false
end

function RHHook.onSimulationFrame()
  if not RHHook.slotChecked then
    local ok, switched = pcall(checkSlot)
    if not ok then log("slot check error: " .. tostring(switched)) end
    if ok and switched then return end
  end
  if RHHook.switching then return end
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
    toMission(SHUTDOWN)
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
