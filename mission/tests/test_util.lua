T.test("serialize round-trips nested tables", function()
  T.fresh()
  local u = RH.util
  local data = { a = 1, b = "two \"quoted\"", list = { 1, 2, 3 }, nested = { ["key with space"] = true, x = 1.5 } }
  local back = u.deserialize(u.serialize(data))
  T.eq(back.a, 1)
  T.eq(back.b, "two \"quoted\"")
  T.eq(#back.list, 3)
  T.eq(back.nested["key with space"], true)
  T.eq(back.nested.x, 1.5)
end)

T.test("deserialize rejects code", function()
  T.fresh()
  local result = RH.util.deserialize("os.exit(1)")
  T.eq(result, nil)
end)

T.test("toJSON encodes arrays, objects and escapes", function()
  T.fresh()
  local json = RH.util.toJSON({ list = { 1, 2 }, empty = {}, s = "a\"b\n", flag = false })
  T.eq(json, '{"empty":[],"flag":false,"list":[1,2],"s":"a\\"b\\n"}')
end)

T.test("config overrides merge into nested tables", function()
  RH = nil
  RH_CONFIG_OVERRIDES = { lives = { max = 5 }, campaignName = "Test" }
  dofile("src/rh/util.lua")
  dofile("src/rh/config.lua")
  T.eq(RH.config.lives.max, 5)
  T.eq(RH.config.lives.restoreAfter, 24 * 3600)
  T.eq(RH.config.campaignName, "Test")
  RH_CONFIG_OVERRIDES = nil
end)

T.test("persistence saves and loads campaign state", function()
  local w = T.fresh()
  RH.state.factories.F1 = { status = "captured" }
  RH.persistence.save()
  RH.state.factories = {}
  T.ok(RH.persistence.load(), "load should succeed")
  T.eq(RH.state.factories.F1.status, "captured")
  T.eq(RH.state.stats.restarts, 1)
end)
