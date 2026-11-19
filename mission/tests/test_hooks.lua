-- The server hook runs outside the mission. These stubs stand in for DCS, net, and lfs.
local function loadHook(files, mission)
  local hook
  local state = { loaded = nil, chats = {}, toMission = {}, mission = mission, time = 0 }
  net = {
    log = function() end,
    send_chat = function(text) state.chats[#state.chats + 1] = text end,
    send_chat_to = function() end,
    load_mission = function(path) state.loaded = path end,
    dostring_in = function(_, code) state.toMission[#state.toMission + 1] = code end,
    get_player_list = function() return {} end,
  }
  DCS = {
    setUserCallbacks = function(t) hook = t end,
    getMissionFilename = function() return state.mission end,
    getModelTime = function() return state.time end,
    getRealTime = function() return 1000 + state.time end,
    isServer = function() return true end,
    isMultiplayer = function() return true end,
  }
  lfs = {
    attributes = function(path) return files[path] and { modification = files[path] } or nil end,
    currentdir = function() return "C:\\DCS" end,
    writedir = function() return "C:\\Saved\\" end,
    mkdir = function() end,
  }
  dofile("../server/Hooks/rh_hooks.lua")
  return hook, state
end

local DIR = "C:\\Saved\\Missions"
local A, B = DIR .. "\\RH Campaign A.miz", DIR .. "\\RH Campaign B.miz"
local MANUAL = DIR .. "\\RH Manual.miz"

T.test("hosting campaign A writes B, and hosting B writes A", function()
  local hook = loadHook({ [A] = 100, [B] = 50 }, A)
  T.eq(hook.slotTarget(A), B)
  T.eq(hook.slotTarget(B), A)
end)

T.test("hosting RH Manual.miz writes the older campaign slot", function()
  local hook = loadHook({ [MANUAL] = 1, [A] = 100, [B] = 50 }, MANUAL)
  T.eq(hook.slotTarget(MANUAL), B)
  hook = loadHook({ [MANUAL] = 1 }, MANUAL)
  T.eq(hook.slotTarget(MANUAL), A)
  hook = loadHook({ [MANUAL] = 1, [A] = 100 }, MANUAL)
  T.eq(hook.slotTarget(MANUAL), B)
end)

T.test("hosting the older campaign slot switches to the newer one before the campaign loads", function()
  local hook, state = loadHook({ [A] = 100, [B] = 200 }, A)
  hook.onSimulationStart()
  hook.onSimulationFrame()
  T.eq(state.loaded, B)
  T.eq(#state.toMission, 0, "nothing is saved from the old file")
end)

T.test("hosting the newest slot, or RH Manual.miz, does not switch", function()
  local hook, state = loadHook({ [A] = 300, [B] = 200 }, A)
  hook.onSimulationStart()
  hook.onSimulationFrame()
  T.eq(state.loaded, nil)
  hook, state = loadHook({ [MANUAL] = 1, [A] = 300, [B] = 200 }, MANUAL)
  hook.onSimulationStart()
  hook.onSimulationFrame()
  T.eq(state.loaded, nil)
end)
