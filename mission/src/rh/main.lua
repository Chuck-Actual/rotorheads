RH = RH or {}

local util = RH.util

-- Chat commands arrive from the server hook (server/Hooks/rh_hooks.lua) via net.dostring_in.
local chat = {}
RH.chat = chat

function chat.handle(playerName, text)
  local cmd = util.trim(text or ""):lower()
  if cmd == "-lives" then
    local left = RH.lives.remaining(playerName)
    local msg = string.format("%s: %d of %d lives.", playerName, left, RH.config.lives.max)
    if left < RH.config.lives.max then
      msg = msg .. " Next life returns in " .. util.formatDuration(RH.lives.nextRestoreIn(playerName)) .. "."
    end
    RH.dcs.message("blue", msg, 15)
  elseif cmd == "-farps" then
    local lines = {}
    for _, farp in ipairs(RH.logistics.farps()) do
      table.insert(lines, string.format("%s%s: %s", farp.name, farp.lc and " (LC)" or "", RH.logistics.stockText(farp)))
    end
    RH.dcs.message("blue", #lines > 0 and table.concat(lines, "\n") or "No FARPs yet.", 20)
  elseif cmd == "-mash" then
    RH.dcs.message("blue", RH.logistics.mashStatus(), 15)
  elseif cmd == "-save" then
    RH.persistence.save()
    RH.dcs.message("all", "Campaign saved. Ground units are in the save. RH_Editor.miz, beside your mission, is the copy the Mission Editor can open.", 12)
  end
end

-- Called by the hook shortly before an automatic restart.
function RH.shutdown()
  RH.persistence.save()
  if RH.livemap then RH.livemap.export() end
  if RH.ctld and RH.ctld.instance then RH.ctld.instance:__Save(1) end
  if RH.csar and RH.csar.instance then RH.csar.instance:__Save(1) end
end

function RH.start()
  util.log("starting %s", RH.config.campaignName)
  -- math.randomseed is removed by DCS's MissionScripting.lua, and math.random works without it.
  if math.randomseed then math.randomseed(RH.dcs.wallclock()) end
  if not RH.dcs.filesEnabled() then
    util.log("io/lfs/os are sanitized: running WITHOUT saving. Edit Scripts\\MissionScripting.lua (see README).")
    RH.dcs.message("all", "ROTORHEADS WARNING: MissionScripting.lua is not desanitized, so the campaign will NOT be saved. See README step 1.", 60)
  end
  RH.persistence.load()
  if RH.world and RH.world.readOfficialSave then RH.world.readOfficialSave() end
  if RH.world and RH.world.installOfficialSave then RH.world.installOfficialSave() end
  if RH.world and RH.world.restore then RH.world.restore() end
  RH.events.install()

  RH.logistics.start()
  RH.outposts.start()
  RH.factories.start()
  RH.redair.start()
  RH.paratroopers.spawn()
  RH.lives.start()
  RH.markers.start()
  RH.convoy.start()
  RH.ctld.create()
  RH.csar.start()
  RH.livemap.start()
  RH.persistence.start()

  RH.persistence.save()
  RH.dcs.message("all", RH.config.campaignName .. " is live. F10 > CSAR > Report on duty to hear downed pilots. Chat: -lives, -farps, -mash", 30)
end

return RH
