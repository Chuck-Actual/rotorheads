local function setup()
  local w = T.fresh()
  RH.logistics.register("LC Bassel", { x = 0, y = 0 }, { lc = true })
  RH.logistics.register("RH_FARP_BRAVO", { x = 30000, y = 0 }, { crates = 5 })
  return w
end

local function trucks(w)
  for name, g in pairs(w.groups) do
    if g.alias == "Supply convoy" then return name, g end
  end
end

T.test("convoy runs from an LC to the FARP with the fewest crates", function()
  local w = setup()
  local c = RH.convoy.begin()
  T.ok(c ~= nil, "convoy should start")
  T.eq(c.origin, "LC Bassel")
  T.eq(c.destination, "RH_FARP_BRAVO")
  T.ok(w.drawings.convoy ~= nil, "escort circle drawn")
  local _, g = trucks(w)
  T.eq(g.routedTo.x, 30000)
end)

T.test("ambush halts the convoy until the insurgents are dead", function()
  local w = setup()
  RH.convoy.start()
  w.advance(150)
  local c = RH.convoy.active
  T.ok(c ~= nil)
  w.advance(RH.config.convoy.ambushIntervalMax + 30, 5)
  T.ok(c.halted, "convoy should be halted by an ambush")
  T.ok(c.ambush ~= nil)
  local _, g = trucks(w)
  T.ok(g.held)
  T.ok(#w.smokes >= 1)
  w.groups[c.ambush].alive = 0
  w.advance(20)
  T.ok(not c.halted)
  T.eq(g.held, false)
end)

T.test("arrival delivers 5 crates per surviving truck", function()
  local w = setup()
  RH.convoy.begin()
  local _, g = trucks(w)
  g.alive = 2
  g.pos = { x = 29900, y = 0 }
  RH.convoy.tick()
  T.eq(RH.state.farps.RH_FARP_BRAVO.crates, 15)
  T.eq(RH.convoy.active, nil)
  T.ok(w.anyMessage("delivered 10 crates"))
end)

T.test("a destroyed convoy fails and a new one starts later", function()
  local w = setup()
  RH.convoy.begin()
  local _, g = trucks(w)
  g.alive = 0
  RH.convoy.tick()
  T.eq(RH.convoy.active, nil)
  T.ok(w.anyMessage("destroyed"))
  w.advance(RH.config.convoy.restartDelay + 5)
  RH.convoy.tick()
  T.ok(RH.convoy.active ~= nil)
end)
