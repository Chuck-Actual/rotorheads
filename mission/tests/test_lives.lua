local function birth(name, typeName, unit)
  RH.events.dispatch({ id = "birth", playerName = name, initiatorName = unit or (name .. "-unit"), initiatorType = typeName,
    initiatorCoalition = "blue", initiatorCategory = "helicopter" })
end

T.test("attack helicopters lose lives, utility helicopters do not", function()
  T.fresh()
  RH.lives.start()
  birth("Viper", "AH-64D_BLK_II")
  RH.events.dispatch({ id = "crash", initiatorName = "Viper-unit" })
  T.eq(RH.lives.remaining("Viper"), 2)
  RH.events.dispatch({ id = "pilotDead", initiatorName = "Viper-unit" })
  T.eq(RH.lives.remaining("Viper"), 2, "one sortie costs at most one life")

  birth("Viper", "UH-1H", "Huey-1")
  RH.events.dispatch({ id = "crash", initiatorName = "Huey-1" })
  T.eq(RH.lives.remaining("Viper"), 2)
end)

T.test("out of lives: aircraft is removed and the player is told when lives return", function()
  local w = T.fresh()
  RH.lives.start()
  for _ = 1, 3 do RH.lives.lose("Ghost", "test") end
  birth("Ghost", "Ka-50")
  T.ok(w.anyMessage("no lives left"))
  w.advance(11)
  T.eq(w.destroyedUnits[1], "Ghost-unit")
end)

T.test("lives come back after 24 hours", function()
  local w = T.fresh()
  RH.lives.lose("Ghost", "test")
  T.eq(RH.lives.remaining("Ghost"), 2)
  w.wall = w.wall + 24 * 3600 + 1
  T.eq(RH.lives.remaining("Ghost"), 3)
end)

T.test("rescue restores a life", function()
  T.fresh()
  RH.lives.lose("Ghost", "test")
  RH.lives.lose("Ghost", "test")
  T.eq(RH.lives.restore("Ghost", 1), 1)
  T.eq(RH.lives.remaining("Ghost"), 2)
end)

T.test("leaving the aircraft away from a base costs a life and creates a CSAR", function()
  local w = T.fresh()
  RH.lives.start()
  local stranded = {}
  RH.csar = { spawnStranded = function(pos, player) table.insert(stranded, player) end }
  RH.logistics.register("RH_FARP_ALPHA", { x = 0, y = 0 })

  birth("Viper", "AH-64D_BLK_II")
  RH.events.dispatch({ id = "playerLeave", initiatorName = "Viper-unit", pos = { x = 100, y = 0, z = 100 }, onGround = true })
  T.eq(RH.lives.remaining("Viper"), 3, "landed at FARP: no penalty")

  birth("Viper", "AH-64D_BLK_II")
  RH.events.dispatch({ id = "playerLeave", initiatorName = "Viper-unit", pos = { x = 50000, y = 0, z = 0 }, onGround = false })
  T.eq(RH.lives.remaining("Viper"), 2)
  T.eq(stranded[1], "Viper")
end)

T.test("friendly fire costs a life and fails weapons until landing at a FARP", function()
  local w = T.fresh()
  RH.lives.start()
  birth("Oops", "Mi-24P")
  RH.events.dispatch({ id = "kill", playerName = "Oops", initiatorName = "Oops-unit", initiatorCoalition = "blue",
    targetCoalition = "blue", targetCategory = "ground", targetType = "M1A2" })
  T.eq(RH.lives.remaining("Oops"), 2)
  RH.events.dispatch({ id = "shot", playerName = "Oops", weapon = "missile-1" })
  w.advance(2)
  T.eq(w.destroyedWeapons[1], "missile-1")
  RH.events.dispatch({ id = "land", playerName = "Oops", initiatorName = "Oops-unit", place = "FARP Alpha" })
  RH.events.dispatch({ id = "shot", playerName = "Oops", weapon = "missile-2" })
  w.advance(2)
  T.eq(#w.destroyedWeapons, 1)
end)

T.test("killing red units is not friendly fire", function()
  T.fresh()
  RH.lives.start()
  RH.events.dispatch({ id = "kill", playerName = "Ace", initiatorName = "a", initiatorCoalition = "blue",
    targetCoalition = "red", targetCategory = "ground" })
  T.eq(RH.lives.remaining("Ace"), 3)
end)
