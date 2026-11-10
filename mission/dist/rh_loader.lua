-- Loads the Rotorheads campaign two seconds after the mission starts.
-- The Mission Editor trigger only needs: dofile(lfs.writedir() .. [[Missions\Rotorheads\rh_loader.lua]])
-- Test overrides live here. Delete the RH_CONFIG_OVERRIDES block for full Rotorheads timings.
RH_CONFIG_OVERRIDES = {
  outpost = { holdTimeMin = 60, holdTimeMax = 90 },
  factory = { reinforceInterval = 120, repairFlightInterval = 300 },
  redAir = { areaCooldown = 120, fighterCooldown = 120 },
  lives = { restoreAfter = 600 },
}

local function start()
  local ok, err = pcall(function()
    dofile(lfs.writedir() .. [[Missions\Rotorheads\rotorheads.lua]])
  end)
  if not ok then
    env.error("[RH] failed to start: " .. tostring(err))
    trigger.action.outText("ROTORHEADS FAILED TO START: " .. tostring(err), 60)
  end
end

-- timer may not exist yet while MOOSE is still loading, so wait for it.
local function waitForTimer()
  if timer and timer.scheduleFunction and timer.getTime then
    timer.scheduleFunction(start, nil, timer.getTime() + 2)
  else
    env.error("[RH] timer unavailable, starting immediately")
    start()
  end
end

waitForTimer()
