T.test("live map export includes campaign objects and spotted threats", function()
  local w = T.fresh()
  w.zones = {
    { name = "RH_OUTPOST_A", point = { x = 0, y = 0 }, radius = 100 },
    { name = "RH_FACTORY_B", point = { x = 50000, y = 0 }, radius = 100 },
  }
  RH.outposts.discover()
  RH.factories.discover()
  RH.logistics.register("RH_FARP_ALPHA", { x = 1000, y = 1000 })
  RH.logistics.registerMash("MASH 01", { x = 2000, y = 0 })
  w.addUnit("blue", { x = 1000, y = 0 })
  w.addUnit("red", { x = 3000, y = 0 }, { isAA = true, typeName = "ZSU-23-4 Shilka" })
  w.addUnit("red", { x = 40000, y = 0 }, { typeName = "T-72B" })
  w.players = { { name = "Viper", typeName = "AH-64D_BLK_II", coalition = "blue", pos = { x = 0, y = 0 }, heading = 90, altitude = 120 } }

  local snap = RH.livemap.export()
  T.eq(snap.theatre, "Syria")
  T.eq(#snap.outposts, 1)
  T.eq(#snap.factories, 0, "unrevealed factory hidden")
  T.eq(#snap.farps, 1)
  T.eq(#snap.mashes, 1)
  T.eq(#snap.threats, 1, "only the unit near a blue unit is spotted")
  T.eq(snap.threats[1].kind, "aa")
  T.eq(snap.players[1].lives, 3)
  T.ok(type(snap.players[1].lat) == "number")
  local json = w.files["save/livemap.json"]
  T.ok(json and json:find('"theatre":"Syria"'), "JSON written")
end)

T.test("sightings linger for 30 minutes then expire", function()
  local w = T.fresh()
  w.addUnit("blue", { x = 0, y = 0 })
  local red = w.addUnit("red", { x = 2000, y = 0 })
  RH.livemap.snapshot()
  red.alive = false
  w.wall = w.wall + 600
  T.eq(#RH.livemap.snapshot().threats, 1)
  w.wall = w.wall + 1800
  T.eq(#RH.livemap.snapshot().threats, 0)
end)
