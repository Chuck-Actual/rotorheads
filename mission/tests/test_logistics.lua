local NM = 1852

local function setup()
  local w = T.fresh()
  w.airbases = {
    { name = "Bassel Al-Assad", point = { x = 0, y = 0 }, kind = "airdrome", coalition = "blue" },
    { name = "Aleppo", point = { x = 200000, y = 0 }, kind = "airdrome", coalition = "red" },
    { name = "Hama", point = { x = 0, y = 150000 }, kind = "airdrome", coalition = "neutral" },
  }
  RH.logistics.register("LC Bassel", { x = 500, y = 0 }, { lc = true, airbase = "Bassel Al-Assad" })
  RH.logistics.register("RH_FARP_ALPHA", { x = 40000, y = 0 })
  return w
end

T.test("a FARP pad is granted 10 tons and 40 missiles once, then restarts keep the saved count", function()
  T.fresh()
  local stock, fresh = RH.logistics.ensurePadStock("static1-4")
  T.ok(fresh)
  T.eq(stock.fuelKg, 10000)
  T.eq(stock.missiles["weapons.missiles.AGM_114K"], 40)
  T.eq(stock.missiles["weapons.missiles.AGM_114L"], 40)
  T.eq(stock.missiles["weapons.missiles.Vikhr_M"], 40)
  stock.fuelKg = 4000
  stock.missiles["weapons.missiles.AGM_114K"] = 12
  stock.missiles["weapons.missiles.AGM_114L"] = 7
  stock.missiles["weapons.missiles.Vikhr_M"] = 0
  local again, second = RH.logistics.ensurePadStock("static1-4")
  T.ok(not second)
  T.eq(again.fuelKg, 4000)
  T.eq(again.missiles["weapons.missiles.AGM_114K"], 12)
  T.eq(again.missiles["weapons.missiles.AGM_114L"], 7)
  T.eq(again.missiles["weapons.missiles.Vikhr_M"], 0)
end)

T.test("a new FARP starts with no crates and general supply is worth five", function()
  setup()
  T.eq(RH.state.farps.RH_FARP_ALPHA.crates, 0)
  T.eq(RH.logistics.crateWorth("General supply x10"), 5)
  T.eq(RH.logistics.crateWorth("Humvee TOW"), 1)
  T.ok(not RH.logistics.takeCrates(RH.state.farps.RH_FARP_ALPHA, 1))
end)

T.test("FARP stock is consumed and refilled up to the cap", function()
  setup()
  local farp = RH.state.farps.RH_FARP_ALPHA
  farp.crates = 40
  T.ok(RH.logistics.takeCrates(farp, 10))
  T.eq(farp.crates, 30)
  T.ok(not RH.logistics.takeCrates(farp, 1000), "cannot take more than stock")
  local added = RH.logistics.returnCrates(farp, 1000)
  T.eq(farp.crates, RH.config.farp.maxCrates)
  T.eq(added, RH.config.farp.maxCrates - 30)
end)

T.test("Logistics Centers have unlimited crates", function()
  setup()
  local lc = RH.state.farps["LC Bassel"]
  T.ok(RH.logistics.hasUnlimitedCrates(lc))
  T.ok(RH.logistics.takeCrates(lc, 100000))
end)

T.test("FARP must be 1 mile from other FARPs and Logistics Centers", function()
  setup()
  local mile = RH.config.farp.minSeparation
  local ok, reason = RH.logistics.validateFarpSite({ x = 40000 + mile * 0.5, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("needs 1 mile"), reason)
  ok, reason = RH.logistics.validateFarpSite({ x = mile * 0.5, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("Logistics Center"), reason)
  ok = RH.logistics.validateFarpSite({ x = 40000 + mile * 1.1, y = 0 })
  T.eq(ok, true)
end)

T.test("a FARP 10 NM from an airfield with no LC is allowed", function()
  setup()
  local ok, kind = RH.logistics.validateFarpSite({ x = 0, y = 150000 - 10 * NM })
  T.eq(ok, true)
  T.eq(kind, "farp")
end)

T.test("a helicopter pad is not a Logistics Center and does not block a FARP", function()
  local w = setup()
  table.insert(w.airbases, { name = "HS02", point = { x = 9000, y = 0 }, kind = "airdrome", coalition = "blue", logistics = false })
  local ok, kind = RH.logistics.validateFarpSite({ x = 9000, y = 400 })
  T.eq(ok, true)
  T.eq(kind, "farp")
end)

T.test("building within 1 NM of a friendly airfield makes an LC", function()
  local w = setup()
  local ok, kind, airfield = RH.logistics.validateFarpSite({ x = 0, y = 150000 + 0.5 * NM })
  T.eq(ok, true)
  T.eq(kind, "lc")
  T.eq(airfield.name, "Hama")
  local farp = RH.logistics.buildFarp({ x = 0, y = 150000 + 0.5 * NM }, "Viper")
  T.eq(farp.name, "LC Hama")
  T.ok(farp.lc)
  T.eq(farp.pending, true)
  T.eq(#w.farpsSpawned, 0)
  RH.logistics.start()
  T.eq(farp.built, true)
  T.eq(farp.pending, false)
  T.eq(w.farpsSpawned[1], "LC Hama")
  local again, why = RH.logistics.validateFarpSite({ x = 100, y = 150000 })
  T.eq(again, false)
  T.ok(why:find("1 mile"), why)
end)

T.test("FARP stocks guns, rockets, and air-to-air missiles, not air-to-ground", function()
  T.fresh()
  T.eq(RH.logistics.farpSupplyCount("shells", "weapons.shells.M230_HEDP M789"), 5000)
  T.eq(RH.logistics.farpSupplyCount("nurs", "weapons.nurs.HYDRA_70_M151"), 999)
  T.eq(RH.logistics.farpSupplyCount("containers", "weapons.containers.APK-9"), nil)
  T.eq(RH.logistics.farpSupplyCount("gunmounts", "weapons.gunmounts.{CH47_AFT_M134D}"), 99)
  T.eq(RH.logistics.farpSupplyCount("missiles", "weapons.missiles.AIM_9X"), 99)
  T.eq(RH.logistics.farpSupplyCount("missiles", "weapons.missiles.FIM_92C"), 99)
  T.eq(RH.logistics.farpSupplyCount("missiles", "weapons.missiles.Mistral"), 99)
  local keptOff = {
    "AGM_114K", "AGM_114", "Vikhr_M", "SA9M311", "ADM_141A", "ADM_141B", "AM39",
    "CM-400AKG", "M30", "M31", "HY-2", "Kh25MP_PRGS1VP", "Kh-66_Grom", "X_28",
    "LD-10", "M39A1", "M48", "P_500", "P_700", "S_25L", "SCUD_RAKETA", "V-1",
    "YJ-12", "YJ-62", "YJ-82", "P_9M117", "AGR_20A",
  }
  for _, name in ipairs(keptOff) do
    local item = "weapons.missiles." .. name
    T.eq(RH.logistics.farpSupplyCount("missiles", item), nil)
    T.ok(RH.logistics.keepHauledWeapon(item))
  end
  T.ok(not RH.logistics.keepHauledWeapon("weapons.missiles.AIM_9X"))
  T.ok(not RH.logistics.keepHauledWeapon("weapons.nurs.HYDRA_70_M151"))
  T.ok(not RH.logistics.keepHauledWeapon("weapons.containers.APK-9"))
  T.eq(RH.logistics.farpAirframeCount("UH-1H"), 999)
  T.eq(RH.logistics.farpAirframeCount("AH-64D_BLK_II"), 999)
  T.eq(RH.logistics.farpAirframeCount("C-130J-30"), 0)
end)

T.test("a FARP brings the services DCS needs to rearm and refuel", function()
  T.fresh()
  local types = {}
  for _, piece in ipairs(RH.config.farp.services) do types[piece.typeName] = true end
  T.ok(types["FARP Tent"])
  T.ok(types["FARP Fuel Depot"])
  T.ok(types["FARP Ammo Dump Coating"])
  T.ok(types["Hummer"])
  T.ok(not types["M 818"])
end)

T.test("a marked FARP waits for the next restart and then spawns empty", function()
  local w = setup()
  local mile = RH.config.farp.minSeparation
  local farp = RH.logistics.buildFarp({ x = 40000 + mile * 2, y = 0 }, "Viper")
  T.eq(farp.name, "FARP 01")
  T.eq(farp.crates, 0)
  T.eq(farp.liquids, nil)
  T.eq(farp.pending, true)
  T.ok(w.files["save/campaign.lua"]:find("FARP 01"), "mark is written immediately")
  RH.logistics.spawnBuilt()
  T.eq(farp.built, true)
  T.eq(farp.liquids, nil)
  T.eq(farp.ammoItems, nil)
end)

T.test("cannot build an LC at a red airfield", function()
  setup()
  local ok, reason = RH.logistics.validateFarpSite({ x = 200000, y = 500 })
  T.eq(ok, false)
  T.ok(reason:find("REDFOR"), reason)
end)

T.test("MASH needs a blue zone and 16 km separation", function()
  local w = setup()
  w.zones = { { name = "RH_BLUEZONE_WEST", point = { x = 0, y = 0 }, radius = 60000 } }
  local ok, reason = RH.logistics.validateMashSite({ x = 100000, y = 100000 })
  T.eq(ok, false)
  T.ok(reason:find("blue zone"), reason)
  T.ok(RH.logistics.buildMash({ x = 10000, y = 0 }, "Medic"))
  ok, reason = RH.logistics.validateMashSite({ x = 20000, y = 0 })
  T.eq(ok, false)
  T.ok(reason:find("16 km"), reason)
  T.ok(RH.logistics.buildMash({ x = 30000, y = 0 }, "Medic"))
  T.eq(#w.mashesSpawned, 2)
end)

T.test("MASH capacity and transport tasks", function()
  setup()
  RH.logistics.registerMash("MASH 01", { x = 0, y = 0 })
  T.eq(RH.logistics.admitPatients("MASH 01", 25), 25)
  T.eq(RH.logistics.admitPatients("MASH 01", 10), 10)
  T.ok(not RH.logistics.mashFull("MASH 01"))
  T.eq(RH.logistics.startTransport("herc", "MASH 01", 30), 30)
  T.eq(RH.state.mashes["MASH 01"].patients, 5)
  T.eq(RH.logistics.completeTransport("herc"), 30)
end)

T.test("FARP crate template is copied from the Humvee so Get crates can list it", function()
  T.fresh()
  dofile("src/rh/ctld.lua")
  _DATABASE = { Templates = { Groups = {
    RH_TPL_BLUE_HMMWV_TOW = {
      GroupName = "RH_TPL_BLUE_HMMWV_TOW",
      Template = { name = "RH_TPL_BLUE_HMMWV_TOW", units = { { name = "tow" } } },
    },
  } } }
  T.ok(RH.ctld.ensureKitTemplate("RH_TPL_BLUE_FARP_KIT"))
  local kit = _DATABASE.Templates.Groups.RH_TPL_BLUE_FARP_KIT
  T.eq(kit.Template.name, "RH_TPL_BLUE_FARP_KIT")
  T.eq(kit.Template.units[1].name, "tow")
  kit.Template.units[1].name = "changed"
  T.eq(_DATABASE.Templates.Groups.RH_TPL_BLUE_HMMWV_TOW.Template.units[1].name, "tow")
  _DATABASE = nil
end)

T.test("captured outposts extend the blue zone", function()
  local w = setup()
  w.zones = { { name = "RH_OUTPOST_KAFR", point = { x = 90000, y = 0 }, radius = 200 } }
  RH.outposts.discover()
  T.ok(not RH.logistics.inBlueZone({ x = 90000, y = 0 }))
  RH.state.outposts.RH_OUTPOST_KAFR = { status = "captured" }
  T.ok(RH.logistics.inBlueZone({ x = 90000, y = 1000 }))
end)
