-- CSAR block around FARPs and airfields. A crash on a pad must not leave a downed pilot there.
local w = T.fresh()
dofile("src/rh/csar.lua")

local function place()
  RH.state.farps = {
    COPPERHEAD = { name = "COPPERHEAD", x = 0, y = 0, loadPoints = { { x = 70, y = 0 } } },
  }
  w.airbases = {
    { name = "Bassel Al-Assad", point = { x = 10000, y = 0 }, kind = "airdrome", coalition = "blue", logistics = true },
    { name = "Enemy", point = { x = 0, y = 20000 }, kind = "airdrome", coalition = "red", logistics = true },
    { name = "Deck", point = { x = 0, y = 5000 }, kind = "ship", coalition = "blue", logistics = false },
  }
end

T.test("a pad and an airfield are blocked, the field beyond them is open", function()
  place()
  T.eq(RH.csar.blocked({ x = 100, y = 0 }), "farp", "on the pad")
  T.eq(RH.csar.blocked({ x = 350, y = 0 }), "farp", "inside 400 m of the tent")
  T.eq(RH.csar.blocked({ x = 900, y = 0 }), nil, "outside the FARP block")
  T.eq(RH.csar.blocked({ x = 11000, y = 0 }), "airfield", "on the airfield")
  T.eq(RH.csar.blocked({ x = 13000, y = 0 }), nil, "past the airfield block")
  T.eq(RH.csar.blocked({ x = 0, y = 20000 }), nil, "a red airfield stays a real CSAR")
  T.eq(RH.csar.blocked({ x = 0, y = 5200 }), "farp", "a ship deck")
end)

T.test("pilots already on a pad are deleted and one in the field stays", function()
  place()
  local destroyed = {}
  local inst = {
    downedPilots = {
      { name = "RH Pilot 1", alive = true, rhPos = { x = 20, y = 10 }, group = { Destroy = function() destroyed[#destroyed + 1] = "group" end } },
      { name = "RH Pilot 2", alive = true, rhPos = { x = 4000, y = 4000 } },
    },
    _RemoveNameFromDownedPilots = function(_, name) destroyed[#destroyed + 1] = name end,
  }
  RH.csar.instance = inst
  w.groups["Downed Pilot-9"] = { alive = 1, pos = { x = 80, y = 0 } }
  RH.dcs.groundRoster = function()
    return { { name = "Downed Pilot-9", x = 80, y = 0 }, { name = "RH_TPL_DOWNED_PILOT", x = 0, y = 0 } }
  end
  T.eq(RH.csar.clearBlocked(), 2, "pad record plus the saved group")
  T.eq(inst.downedPilots[1].alive, false, "pad pilot is dead")
  T.eq(inst.downedPilots[2].alive, true, "field pilot stays")
  T.eq(w.groups["Downed Pilot-9"].alive, 0, "saved pilot group is destroyed")
  T.eq(RH.world.excluded("RH Pilot 4"), true, "pilot names stay out of the mission file")
  T.eq(RH.world.excluded("Downed Pilot-9"), true, "moose pilot names stay out of the mission file")
  T.eq(RH.world.excluded("RH_TPL_DOWNED_PILOT"), true, "the template stays in the mission")
end)

T.test("a crash on the pad does not call the MOOSE spawn", function()
  place()
  EVENTS = { PilotDead = 9, Ejection = 10, Dead = 8, Crash = 11 }
  local calls = 0
  local added = 0
  local inst = {
    downedPilots = {},
    csarUnits = {},
    addedTo = {},
    inTransitGroups = {},
    ScheduleOnce = function() end,
    _EventHandler = function() calls = calls + 1 end,
    _AddCsar = function() added = added + 1 end,
  }
  RH.csar.installHooks(inst)
  inst:_EventHandler({
    id = EVENTS.PilotDead,
    IniPlayerName = "Hill",
    IniCategory = 1,
    IniUnit = { GetVec2 = function() return { x = 10, y = 5 } end },
  })
  T.eq(calls, 0, "moose handler skipped")
  T.eq(w.messages[#w.messages].text, "No CSAR. Hill went down at a FARP.", "the flight is told")
  inst:_AddCsar(2, 2, { x = 0, y = 0, z = 0 })
  T.eq(added, 0, "add on the pad is refused")
  inst:_EventHandler({
    id = EVENTS.PilotDead,
    IniPlayerName = "Hill",
    IniCategory = 1,
    IniUnit = { GetVec2 = function() return { x = 4000, y = 4000 } end },
  })
  T.eq(calls, 1, "a crash in the field still spawns")
  inst:_AddCsar(2, 2, { x = 4000, y = 0, z = 4000 })
  T.eq(added, 1, "add in the field is kept")
end)
