RH = RH or {}

local util = RH.util

-- Persistent campaign state. Everything under RH.state is written to the save file.
RH.state = RH.state or {
  version = 1,
  factories = {},
  outposts = {},
  farps = {},
  mashes = {},
  redForces = {},
  blueOutposts = {},
  lives = {},
  stats = { restarts = 0 },
}

-- Event bus -----------------------------------------------------------------

local events = { handlers = {} }
RH.events = events

function events.on(id, fn)
  events.handlers[id] = events.handlers[id] or {}
  table.insert(events.handlers[id], fn)
end

function events.dispatch(event)
  local list = events.handlers[event.id]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, event)
    if not ok then util.log("event %s handler error: %s", tostring(event.id), tostring(err)) end
  end
end

-- The adapter translates raw DCS events into plain tables with string ids ("dead", "birth", "shot", ...).
function events.install()
  RH.dcs.installEventHandler(events.dispatch)
end

-- Repeating jobs --------------------------------------------------------------

function RH.every(interval, fn, firstDelay)
  local function tick()
    local ok, err = pcall(fn)
    if not ok then util.log("scheduled job error: %s", tostring(err)) end
    return RH.dcs.now() + interval
  end
  RH.dcs.schedule(tick, firstDelay or interval)
end

function RH.after(delay, fn)
  RH.dcs.schedule(function()
    local ok, err = pcall(fn)
    if not ok then util.log("delayed job error: %s", tostring(err)) end
    return nil
  end, delay)
end

-- Persistence -----------------------------------------------------------------

local persistence = {}
RH.persistence = persistence

function persistence.path(file)
  return RH.dcs.savePath(file)
end

function persistence.load()
  local raw = RH.dcs.readFile(persistence.path("campaign.lua"))
  if not raw then
    util.log("no campaign save found, starting a fresh campaign")
    return false
  end
  local data, err = util.deserialize(raw)
  if type(data) ~= "table" then
    util.log("campaign save unreadable (%s), starting fresh", tostring(err))
    return false
  end
  for k, v in pairs(data) do RH.state[k] = v end
  RH.state.stats = RH.state.stats or { restarts = 0 }
  RH.state.stats.restarts = (RH.state.stats.restarts or 0) + 1
  util.log("campaign save loaded (restart #%d)", RH.state.stats.restarts)
  return true
end

function persistence.save()
  if RH.world and RH.world.capture then RH.world.capture() end
  if RH.logistics and RH.logistics.captureStocks then RH.logistics.captureStocks() end
  RH.state.savedAt = RH.dcs.wallclock()
  local ok = RH.dcs.writeFile(persistence.path("campaign.lua"), util.serialize(RH.state))
  if RH.ctld and RH.ctld.instance and RH.ctld.instance.__Save then
    local inst = RH.ctld.instance
    inst:__Save(1, inst.filepath, inst.filename)
  end
  if ok then util.log("campaign saved") end
  return ok
end

function persistence.start()
  RH.every(RH.config.saveInterval, persistence.save)
end

return RH
