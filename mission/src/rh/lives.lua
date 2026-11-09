RH = RH or {}

local util = RH.util

-- Pilot lives. Utility helicopters are unlimited, everything else gets three.
-- A life is lost when the pilot dies, ejects, crashes, or leaves the aircraft anywhere other than a base.
-- Lives come back after 24 hours or when the pilot's CSAR is delivered to a MASH / base.
local lives = { sorties = {}, weaponsLocked = {} }
RH.lives = lives

local function cfg() return RH.config.lives end

local function record(player)
  RH.state.lives[player] = RH.state.lives[player] or { lost = {} }
  return RH.state.lives[player]
end

function lives.isUnlimited(typeName)
  return util.contains(cfg().unlimitedTypes, typeName)
end

function lives.prune(player)
  local rec = record(player)
  local now = RH.dcs.wallclock()
  local kept = {}
  for _, t in ipairs(rec.lost) do
    if now - t < cfg().restoreAfter then table.insert(kept, t) end
  end
  rec.lost = kept
  return rec
end

function lives.remaining(player)
  return math.max(0, cfg().max - #lives.prune(player).lost)
end

function lives.nextRestoreIn(player)
  local rec = lives.prune(player)
  if #rec.lost == 0 then return 0 end
  local oldest = rec.lost[1]
  for _, t in ipairs(rec.lost) do if t < oldest then oldest = t end end
  return math.max(0, oldest + cfg().restoreAfter - RH.dcs.wallclock())
end

function lives.lose(player, reason)
  local rec = lives.prune(player)
  if #rec.lost >= cfg().max then return 0 end
  table.insert(rec.lost, RH.dcs.wallclock())
  local left = lives.remaining(player)
  RH.dcs.message("blue", string.format("%s lost a life (%s). Lives remaining: %d.", player, reason, left), 15)
  return left
end

function lives.restore(player, count)
  local rec = lives.prune(player)
  local restored = 0
  for _ = 1, count or 1 do
    if #rec.lost == 0 then break end
    local newestIndex = 1
    for i, t in ipairs(rec.lost) do
      if t > rec.lost[newestIndex] then newestIndex = i end
    end
    table.remove(rec.lost, newestIndex)
    restored = restored + 1
  end
  if restored > 0 then
    RH.dcs.message("blue", string.format("%s's pilot was rescued. Lives remaining: %d.", player, lives.remaining(player)), 15)
  end
  return restored
end

-- Ends a sortie, costing a life on limited airframes. Returns true if this call ended it.
function lives.endSortie(unitName, reason)
  local s = lives.sorties[unitName]
  if not s or s.ended then return false end
  s.ended = true
  if not s.unlimited then lives.lose(s.player, reason) end
  return true
end

function lives.onBirth(e)
  if not e.playerName or e.initiatorCoalition ~= "blue" then return end
  if e.initiatorCategory ~= "helicopter" and e.initiatorCategory ~= "plane" then return end
  local unlimited = lives.isUnlimited(e.initiatorType)
  lives.sorties[e.initiatorName] = { player = e.playerName, typeName = e.initiatorType, unlimited = unlimited }
  if unlimited then return end

  local left = lives.remaining(e.playerName)
  if left <= 0 then
    RH.dcs.messageToUnit(e.initiatorName, string.format(
      "You have no lives left for this airframe. Next life returns in %s, or when your pilot is rescued. Utility helicopters have unlimited lives.",
      util.formatDuration(lives.nextRestoreIn(e.playerName))), 20)
    lives.sorties[e.initiatorName].ended = true
    RH.after(10, function() RH.dcs.destroyUnit(e.initiatorName) end)
  else
    RH.dcs.messageToUnit(e.initiatorName, string.format("Lives remaining: %d of %d.", left, cfg().max), 10)
  end
end

function lives.onLost(e)
  if not e.initiatorName then return end
  local reason = e.id == "ejection" and "ejected" or (e.id == "crash" and "crashed" or "killed")
  lives.endSortie(e.initiatorName, reason)
end

-- Leaving the aircraft away from a FARP, airfield or ship strands the crew: a life is lost and a CSAR is created.
function lives.onPlayerLeave(e)
  local s = lives.sorties[e.initiatorName]
  if not s or s.ended then return end
  local atBase = e.pos and e.onGround and RH.dcs.nearBase(e.pos, cfg().baseRadius)
  if atBase then
    s.ended = true
    return
  end
  lives.endSortie(e.initiatorName, "left the aircraft away from a base")
  if e.pos and RH.csar and RH.csar.spawnStranded then
    RH.csar.spawnStranded(e.pos, s.player, s.typeName)
  end
end

-- Friendly fire: a life is lost and guided weapons fail until the pilot lands at a FARP.
function lives.onKill(e)
  if not e.playerName or e.initiatorCoalition ~= "blue" then return end
  if e.targetCoalition ~= "blue" and e.targetCoalition ~= "neutral" then return end
  if e.targetCategory ~= "ground" and e.targetCategory ~= "helicopter" and e.targetCategory ~= "plane" then return end
  if e.targetIsCsarPilot then return end
  lives.weaponsLocked[e.playerName] = true
  lives.lose(e.playerName, "friendly fire")
  RH.dcs.messageToUnit(e.initiatorName, "FRIENDLY FIRE. Your weapons will fail until you land at a FARP.", 20)
  RH.dcs.notify("teamkill", { player = e.playerName, target = e.targetType })
end

function lives.onShot(e)
  if e.playerName and lives.weaponsLocked[e.playerName] and e.weapon then
    RH.after(cfg().teamkillWeaponDelay, function() RH.dcs.destroyWeapon(e.weapon) end)
  end
end

function lives.onLand(e)
  if e.playerName and lives.weaponsLocked[e.playerName] and e.place then
    lives.weaponsLocked[e.playerName] = nil
    RH.dcs.messageToUnit(e.initiatorName, "Weapons released. Fly safe.", 10)
  end
end

function lives.start()
  RH.events.on("birth", lives.onBirth)
  RH.events.on("pilotDead", lives.onLost)
  RH.events.on("ejection", lives.onLost)
  RH.events.on("crash", lives.onLost)
  RH.events.on("playerLeave", lives.onPlayerLeave)
  RH.events.on("kill", lives.onKill)
  RH.events.on("shot", lives.onShot)
  RH.events.on("land", lives.onLand)
end

return lives
