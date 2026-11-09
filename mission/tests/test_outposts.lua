local function setup()
  local w = T.fresh()
  w.zones = {
    { name = "RH_OUTPOST_TAFTANAZ", point = { x = 0, y = 0 }, radius = 100 },
    { name = "RH_AO_TAFTANAZ", point = { x = 3000, y = 0 }, radius = 2000 },
    { name = "RH_REDHELI_ABU", point = { x = 50000, y = 0 }, radius = 300 },
  }
  for i = 1, 3 do w.statics["container" .. i] = { side = "red", point = { x = i, y = 0 }, alive = true } end
  RH.outposts.start()
  return w
end

local function destroyAll(w)
  for i = 1, 3 do
    w.statics["container" .. i].alive = false
    RH.events.dispatch({ id = "dead", initiatorName = "container" .. i })
  end
end

T.test("destroying all containers opens a yellow contested zone and launches a Havoc", function()
  local w = setup()
  local o = RH.outposts.list[1]
  w.statics.container1.alive = false
  RH.events.dispatch({ id = "dead", initiatorName = "container1" })
  T.eq(RH.outposts.status(o), "intact")
  destroyAll(w)
  T.eq(RH.outposts.status(o), "contested")
  T.eq(o.color, "yellow")
  T.ok(w.drawings["outpost-RH_OUTPOST_TAFTANAZ"] ~= nil)
  local havocs = 0
  for _, g in pairs(w.groups) do if g.kind == "havoc" then havocs = havocs + 1 end end
  T.eq(havocs, 1)
end)

T.test("holding the zone with blue units captures the outpost after the hidden timer", function()
  local w = setup()
  destroyAll(w)
  w.addUnit("blue", { x = 500, y = 0 })
  w.advance(60)
  local o = RH.outposts.list[1]
  T.eq(o.color, "blue")
  T.eq(RH.outposts.status(o), "contested")
  w.advance(RH.config.outpost.holdTimeMax + 60)
  T.eq(RH.outposts.status(o), "captured")
  T.ok(RH.outposts.areaCaptured(RH.factories.areas[1] or { name = "RH_AO_TAFTANAZ", point = { x = 3000, y = 0 } }))
  T.ok(w.anyMessage("captured"))
end)

T.test("red presence in the zone repairs the outpost", function()
  local w = setup()
  destroyAll(w)
  w.addUnit("red", { x = 500, y = 0 })
  w.advance(RH.config.outpost.holdTimeMax + 120)
  local o = RH.outposts.list[1]
  T.eq(RH.outposts.status(o), "intact")
  T.ok(w.statics.container1.alive, "containers respawned")
  T.eq(w.drawings["outpost-RH_OUTPOST_TAFTANAZ"], nil)
end)

T.test("mixed presence keeps the zone yellow and resets the timer", function()
  local w = setup()
  destroyAll(w)
  w.addUnit("blue", { x = 500, y = 0 })
  local red = w.addUnit("red", { x = -500, y = 0 })
  w.advance(RH.config.outpost.holdTimeMax + 60)
  local o = RH.outposts.list[1]
  T.eq(o.color, "yellow")
  T.eq(RH.outposts.status(o), "contested")
  red.alive = false
  w.advance(60)
  T.eq(o.color, "blue")
end)

T.test("captured outposts stay captured after a restart", function()
  local w = setup()
  RH.state.outposts.RH_OUTPOST_TAFTANAZ.status = "captured"
  local saved = RH.util.serialize(RH.state)
  local w2 = T.fresh()
  w2.zones = w.zones
  for i = 1, 3 do w2.statics["container" .. i] = { side = "red", point = { x = i, y = 0 }, alive = true } end
  w2.files["save/campaign.lua"] = saved
  RH.persistence.load()
  RH.outposts.start()
  T.eq(RH.outposts.status(RH.outposts.list[1]), "captured")
  T.eq(w2.statics.container1.alive, false)
end)
