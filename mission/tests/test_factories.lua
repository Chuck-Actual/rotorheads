local function setup()
  local w = T.fresh()
  w.zones = {
    { name = "RH_FACTORY_IDLIB", point = { x = 0, y = 0 }, radius = 300 },
    { name = "RH_AO_SARAQIB", point = { x = 20000, y = 0 }, radius = 3000 },
    { name = "RH_AO_ARIHA", point = { x = 0, y = 20000 }, radius = 3000 },
    { name = "RH_REDHELI_ABU", point = { x = -30000, y = 0 }, radius = 300 },
  }
  w.statics.hall1 = { side = "red", point = { x = 50, y = 0 }, alive = true }
  w.statics.hall2 = { side = "red", point = { x = -50, y = 0 }, alive = true }
  RH.outposts.start()
  RH.factories.start()
  return w
end

local function groupsWithAlias(w, prefix)
  local out = {}
  for name, g in pairs(w.groups) do
    if g.alias:sub(1, #prefix) == prefix and g.alive > 0 then table.insert(out, name) end
  end
  return out
end

local function destroyFactory(w)
  for _, n in ipairs({ "hall1", "hall2" }) do
    w.statics[n].alive = false
    RH.events.dispatch({ id = "dead", initiatorName = n })
  end
end

T.test("areas of operation start garrisoned", function()
  local w = setup()
  T.eq(#groupsWithAlias(w, "Garrison"), 2 * RH.config.area.garrisonGroups)
end)

T.test("killed garrison groups are replaced by convoys from the factory", function()
  local w = setup()
  for _, name in ipairs(groupsWithAlias(w, "Garrison RH_AO_SARAQIB")) do w.groups[name].alive = 0 end
  w.advance(RH.config.factory.reinforceInterval + 60)
  local convoys = groupsWithAlias(w, "Convoy")
  T.ok(#convoys >= 1, "a convoy should spawn")
  T.ok(#convoys <= RH.config.factory.maxConvoysPerFactory)
  local g = w.groups[convoys[1]]
  T.ok(RH.util.distance(g.routedTo, { x = 20000, y = 0 }) < 3000, "convoy routed to the depleted AO")
end)

T.test("destroying both buildings disables the factory and pops red smoke", function()
  local w = setup()
  destroyFactory(w)
  local f = RH.factories.list[1]
  T.eq(RH.factories.status(f), "destroyed")
  w.advance(31)
  T.ok(#w.smokes >= 1)
  T.eq(w.smokes[1].color, RH.config.markers.smokeColors.red)
  T.eq(w.notifications[1].kind, "factory_destroyed")
end)

T.test("a Mi-26 that lands at the ruins repairs the factory", function()
  local w = setup()
  destroyFactory(w)
  w.advance(RH.config.factory.repairFlightInterval + 60)
  local halos = groupsWithAlias(w, "Mi-26")
  T.eq(#halos, 1)
  local halo = w.groups[halos[1]]
  halo.pos = { x = 100, y = 0 }
  halo.landed = true
  w.advance(31)
  T.eq(RH.factories.status(RH.factories.list[1]), "active")
  T.ok(w.statics.hall1.alive)
  T.ok(#groupsWithAlias(w, "Factory troops") == 1)
end)

T.test("four blue units at the ruins capture the factory on the next restart", function()
  local w = setup()
  destroyFactory(w)
  for i = 1, 4 do w.addUnit("blue", { x = 100 + i, y = 0 }) end
  w.advance(31)
  T.ok(RH.state.factories.RH_FACTORY_IDLIB.captureHeld)
  local saved = RH.util.serialize(RH.state)

  local w2 = T.fresh()
  w2.zones = w.zones
  w2.statics.hall1 = { side = "red", point = { x = 50, y = 0 }, alive = true }
  w2.statics.hall2 = { side = "red", point = { x = -50, y = 0 }, alive = true }
  w2.files["save/campaign.lua"] = saved
  RH.persistence.load()
  RH.outposts.start()
  RH.factories.start()
  T.eq(RH.factories.status(RH.factories.list[1]), "captured")
  T.eq(w2.statics.hall1.alive, false)
  T.eq(#groupsWithAlias(w2, "Garrison"), 0, "no supplier left, so no garrisons")
end)

T.test("an uncaptured destroyed factory is rebuilt on restart", function()
  local w = setup()
  destroyFactory(w)
  local saved = RH.util.serialize(RH.state)
  local w2 = T.fresh()
  w2.zones = w.zones
  w2.statics.hall1 = { side = "red", point = { x = 50, y = 0 }, alive = true }
  w2.statics.hall2 = { side = "red", point = { x = -50, y = 0 }, alive = true }
  w2.files["save/campaign.lua"] = saved
  RH.persistence.load()
  RH.outposts.start()
  RH.factories.start()
  T.eq(RH.factories.status(RH.factories.list[1]), "active")
end)

T.test("red garrisons come back where they were after a restart", function()
  local w = setup()
  local names = groupsWithAlias(w, "Garrison")
  T.ok(#names >= 1)
  w.groups[names[1]].pos = { x = 1234, y = 5678 }
  RH.factories.syncLive()
  local saved = RH.util.serialize(RH.state)

  local w2 = T.fresh()
  w2.zones = w.zones
  w2.statics.hall1 = { side = "red", point = { x = 50, y = 0 }, alive = true }
  w2.statics.hall2 = { side = "red", point = { x = -50, y = 0 }, alive = true }
  w2.files["save/campaign.lua"] = saved
  RH.persistence.load()
  RH.outposts.start()
  RH.factories.start()
  local found = false
  for _, g in pairs(w2.groups) do
    if g.alive > 0 and g.pos.x == 1234 and g.pos.y == 5678 then found = true end
  end
  T.ok(found, "the garrison is restored at its saved position")
  local alive = 0
  for _, g in pairs(w2.groups) do
    if g.alive > 0 and g.alias:sub(1, 8) == "Garrison" then alive = alive + 1 end
  end
  T.eq(alive, 2 * RH.config.area.garrisonGroups, "restored groups fill the garrison, they are not added again")
end)

T.test("factories are revealed only when a blue unit is within 5 km", function()
  local w = setup()
  w.advance(31)
  T.eq(w.drawings["factory-RH_FACTORY_IDLIB"], nil)
  w.addUnit("blue", { x = 4000, y = 0 }, { ground = false })
  w.advance(31)
  T.ok(w.drawings["factory-RH_FACTORY_IDLIB"] ~= nil)
end)
