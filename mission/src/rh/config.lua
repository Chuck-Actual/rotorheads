RH = RH or {}

-- Every tunable number in the campaign lives here. Values follow the Rotorheads wiki where it gives one.
RH.config = {
  campaignName = "Rotorheads Private",

  -- Folder under Saved Games\DCS\ that holds save files and the live map export.
  saveFolder = "rotorheads",
  saveInterval = 300,
  liveMapInterval = 30,

  -- Must match the restart interval in server/Hooks/rh_hooks.lua.
  restartHours = 5,

  -- Mission Editor naming conventions. See docs/MISSION_EDITOR.md.
  prefixes = {
    factory = "RH_FACTORY_",
    outpost = "RH_OUTPOST_",
    area = "RH_AO_",
    redHeliBase = "RH_REDHELI_",
    redAirBase = "RH_REDAIR_",
    blueZone = "RH_BLUEZONE_",
    farp = "RH_FARP_",
    mash = "MASH",
    convoyRoute = "RH_CONVOY_",
    paraZone = "RH_PARA_",
    redTemplate = "RH_TPL_RED_",
    blueTemplate = "RH_TPL_BLUE_",
    playerHelos = "",
  },

  templates = {
    reinforcements = { "RH_TPL_RED_ARMOR", "RH_TPL_RED_IFV", "RH_TPL_RED_AAA", "RH_TPL_RED_SAM", "RH_TPL_RED_APC", "RH_TPL_RED_ARTY" },
    garrison = { "RH_TPL_RED_ARMOR", "RH_TPL_RED_IFV", "RH_TPL_RED_AAA", "RH_TPL_RED_APC", "RH_TPL_RED_INF" },
    paratroopers = { "RH_TPL_RED_PARA_RPG", "RH_TPL_RED_PARA_MANPADS" },
    repairHelo = "RH_TPL_RED_MI26",
    attackHelo = "RH_TPL_RED_MI28",
    fighters = { "RH_TPL_RED_MIG29", "RH_TPL_RED_F4" },
    factoryTroops = "RH_TPL_RED_INF",
    convoyTruck = "RH_TPL_CONVOY_TRUCK",
    convoyEscort = "RH_TPL_CONVOY_ESCORT",
    insurgents = { "RH_TPL_RED_INSURGENT_TECH", "RH_TPL_RED_INSURGENT_INF" },
  },

  factory = {
    visibilityRange = 5000,
    reinforceInterval = 240,
    reinforceIntervalDamaged = 900,
    maxConvoysPerFactory = 2,
    repairFlightInterval = 1200,
    repairLandingRadius = 400,
    captureRadius = 500,
    captureUnitsRequired = 4,
    smokeInterval = 290,
  },

  area = {
    garrisonGroups = 3,
    radius = 3000,
  },

  outpost = {
    contestedRadius = 1.5 * 1852,
    evaluateInterval = 30,
    holdTimeMin = 600,
    holdTimeMax = 900,
  },

  redAir = {
    detectionRange = 8000,
    checkInterval = 60,
    maxAttackHelos = 3,
    maxFighters = 2,
    areaCooldown = 900,
    fighterCooldown = 600,
    attackHeloTypes = { "AH-64D_BLK_II", "Ka-50", "Ka-50_3", "Mi-24P", "SA342M", "SA342L", "SA342Mistral", "SA342Minigun", "OH58D", "AH-1W" },
  },

  paratroopers = {
    groupsPerRestart = 6,
  },

  lives = {
    max = 3,
    restoreAfter = 24 * 3600,
    -- Utility helicopters fly with unlimited lives.
    unlimitedTypes = { "UH-1H", "UH-60L", "Mi-8MT", "Mi-8MTV2", "CH-47Fbl1", "C-130J-30", "Hercules" },
    baseRadius = 600,
    teamkillWeaponDelay = 1.5,
  },

  farp = {
    cratesForFarp = 9,
    farpCrateMass = 1000,
    minDistanceFarp = 15 * 1852,
    minDistanceLC = 5 * 1852,
    lcAirfieldRadius = 1 * 1852,
    noBuildRadiusFromFarp = 300,
    startingCrates = 40,
    maxCrates = 80,
    zoneRadius = 250,
    -- Crates can only be picked up this close to the logistics tent, not anywhere in the big FARP zone.
    loadRadius = 150,
    displayCirclesFor = 60,
  },

  mash = {
    crates = 4,
    crateMass = 400,
    minSeparation = 16000,
    -- Unlimited for now. A normal MASH holds 30; raise this back to 30 when transport tasks matter.
    capacity = 9999,
    -- Drop off rescued pilots within this distance of the hospital tent.
    radius = 150,
  },

  markers = {
    smokeRange = 15000,
    smokeColors = { green = 0, red = 1, white = 2, orange = 3, blue = 4 },
    illuminationBursts = 6,
    illuminationSpacing = 60,
    illuminationAltitude = 700,
    wpzoneRange = 1852,
    extractRange = 4000,
    extractMaxPilots = 4,
  },

  convoy = {
    restartDelay = 240,
    ambushIntervalMin = 240,
    ambushIntervalMax = 480,
    ambushDistanceMin = 500,
    ambushDistanceMax = 900,
    arrivalRadius = 300,
    cratesPerTruck = 5,
    trucks = 2,
    displayRadius = 6000,
  },

  -- CTLD/MASH/CSAR load points that are not FARP zones: ship unit names from the Mission Editor.
  ships = {
    { unit = "Tarawa", length = 225, width = 32 },
    { unit = "Theodore Roosevelt", length = 330, width = 76 },
  },

  -- Troop squads. Bigger squads only appear usable to airframes that can carry them (CTLD enforces trooplimit).
  -- Each entry needs a late-activated blue infantry group in the Mission Editor with the template name.
  troops = {
    { name = "Standard (12)", template = "RH_TPL_BLUE_INF_STD_12", size = 12, subcat = "Infantry" },
    { name = "Standard (6)", template = "RH_TPL_BLUE_INF_STD_6", size = 6, subcat = "Infantry" },
    { name = "Anti-Tank (12)", template = "RH_TPL_BLUE_INF_AT_12", size = 12, subcat = "Anti-Tank" },
    { name = "Anti-Tank (6)", template = "RH_TPL_BLUE_INF_AT_6", size = 6, subcat = "Anti-Tank" },
    { name = "Anti-Tank (2)", template = "RH_TPL_BLUE_INF_AT_2", size = 2, subcat = "Anti-Tank" },
    { name = "Anti-Air (12)", template = "RH_TPL_BLUE_INF_AA_12", size = 12, subcat = "Anti-Air" },
    { name = "Anti-Air (6)", template = "RH_TPL_BLUE_INF_AA_6", size = 6, subcat = "Anti-Air" },
    { name = "Anti-Air (2)", template = "RH_TPL_BLUE_INF_AA_2", size = 2, subcat = "Anti-Air" },
    { name = "Mortar (10)", template = "RH_TPL_BLUE_INF_MORTAR_10", size = 10, subcat = "Mortar" },
    { name = "Mortar (6)", template = "RH_TPL_BLUE_INF_MORTAR_6", size = 6, subcat = "Mortar" },
    { name = "JTAC (6)", template = "RH_TPL_BLUE_INF_JTAC_6", size = 6, subcat = "JTAC" },
    { name = "JTAC (2)", template = "RH_TPL_BLUE_INF_JTAC_2", size = 2, subcat = "JTAC" },
    { name = "Special Ops (6)", template = "RH_TPL_BLUE_INF_SOF_6", size = 6, subcat = "Special Ops" },
    { name = "Special Ops (4)", template = "RH_TPL_BLUE_INF_SOF_4", size = 4, subcat = "Special Ops" },
  },

  -- Ground model for every CTLD crate. This is the C-130J CDS box, the one a Hercules loads 22 of.
  crateModel = "cds_crate",

  -- Vehicle crates. `crates` is how many small CDS crates must sit within 50 m before Build works.
  -- `mass` is kg per crate. A Humvee is four crates. A Chinook (6 internal) can lift one in a single trip.
  vehicles = {
    { name = "Humvee (JTAC)", template = "RH_TPL_BLUE_HMMWV_JTAC", crates = 4, mass = 300, subcat = "Recon" },
    { name = "Humvee TOW", template = "RH_TPL_BLUE_HMMWV_TOW", crates = 4, mass = 300, subcat = "Anti-Tank" },
    { name = "M1126 Stryker ICV", template = "RH_TPL_BLUE_STRYKER", crates = 2, mass = 1500, subcat = "Armor" },
    { name = "M1128 Stryker MGS", template = "RH_TPL_BLUE_STRYKER_MGS", crates = 3, mass = 1500, subcat = "Armor" },
    { name = "M2A2 Bradley", template = "RH_TPL_BLUE_BRADLEY", crates = 3, mass = 1500, subcat = "Armor" },
    { name = "M1A2 Abrams", template = "RH_TPL_BLUE_ABRAMS", crates = 4, mass = 2000, subcat = "Armor" },
    { name = "Leopard 2", template = "RH_TPL_BLUE_LEO2", crates = 4, mass = 2000, subcat = "Armor" },
    { name = "M109 Paladin", template = "RH_TPL_BLUE_M109", crates = 3, mass = 1500, subcat = "Artillery" },
    { name = "M163 Vulcan", template = "RH_TPL_BLUE_VULCAN", crates = 2, mass = 1200, subcat = "SHORAD" },
    { name = "Gepard", template = "RH_TPL_BLUE_GEPARD", crates = 3, mass = 1500, subcat = "SHORAD" },
    { name = "M1097 Avenger", template = "RH_TPL_BLUE_AVENGER", crates = 2, mass = 1200, subcat = "SHORAD" },
    { name = "Roland ADS", template = "RH_TPL_BLUE_ROLAND", crates = 3, mass = 1500, subcat = "SHORAD" },
    { name = "NASAMS Radar", template = "RH_TPL_BLUE_NASAMS_RADAR", crates = 2, mass = 1500, subcat = "SAM" },
    { name = "NASAMS C2", template = "RH_TPL_BLUE_NASAMS_C2", crates = 2, mass = 1500, subcat = "SAM" },
    { name = "NASAMS Launcher", template = "RH_TPL_BLUE_NASAMS_LN", crates = 2, mass = 1500, subcat = "SAM" },
    { name = "Hawk Site", template = "RH_TPL_BLUE_HAWK", crates = 6, mass = 1500, subcat = "SAM" },
    { name = "M939 Ammo Truck", template = "RH_TPL_BLUE_AMMO", crates = 2, mass = 1000, subcat = "Support" },
    { name = "M978 Fuel Tanker", template = "RH_TPL_BLUE_FUEL", crates = 2, mass = 1500, subcat = "Support" },
  },

  -- Construction kits. These templates are placeholders: the script replaces them with the real structure.
  kits = {
    farp = { name = "FARP crate", template = "RH_TPL_BLUE_FARP_KIT" },
    mash = { name = "MASH crate", template = "RH_TPL_BLUE_MASH_KIT" },
    outpost = { name = "Outpost crate", template = "RH_TPL_BLUE_OUTPOST_KIT", crates = 2, mass = 800 },
    uhRepair = { name = "UH Repair kit", template = "RH_TPL_BLUE_UHREPAIR_KIT", crates = 1, mass = 300, lifetime = 1800 },
  },

  -- Troops weigh 100 kg each (wiki). Internal crate counts are the wiki "Carry Capacity" table.
  -- Only small crates load internally. A Humvee is 4 crates, so a Chinook (6) can haul one in a single trip.
  -- Huey and Black Hawk hold 1, the Hip holds 2, the Hind holds 1. Sling load is a separate single crate.
  troopWeight = 100,
  airframes = {
    ["Mi-8MTV2"] = { crates = true, troops = true, cratelimit = 2, trooplimit = 12, length = 15, maxweight = 4000, csar = 12 },
    ["Mi-8MT"] = { crates = true, troops = true, cratelimit = 2, trooplimit = 12, length = 15, maxweight = 4000, csar = 12 },
    ["Mi-24P"] = { crates = true, troops = true, cratelimit = 1, trooplimit = 6, length = 18, maxweight = 1500, csar = 6 },
    ["UH-1H"] = { crates = true, troops = true, cratelimit = 1, trooplimit = 6, length = 15, maxweight = 1200, csar = 6 },
    ["UH-60L"] = { crates = true, troops = true, cratelimit = 1, trooplimit = 10, length = 16, maxweight = 3500, csar = 10 },
    ["CH-47Fbl1"] = { crates = true, troops = true, cratelimit = 6, trooplimit = 15, length = 20, maxweight = 10000, csar = 20 },
    ["SA342M"] = { crates = false, troops = true, cratelimit = 0, trooplimit = 2, length = 12, maxweight = 400, csar = 2 },
    ["SA342L"] = { crates = false, troops = true, cratelimit = 0, trooplimit = 2, length = 12, maxweight = 400, csar = 2 },
    ["SA342Mistral"] = { crates = false, troops = true, cratelimit = 0, trooplimit = 2, length = 12, maxweight = 400, csar = 2 },
    ["SA342Minigun"] = { crates = false, troops = true, cratelimit = 0, trooplimit = 1, length = 12, maxweight = 400, csar = 2 },
    ["OH58D"] = { crates = false, troops = true, cratelimit = 0, trooplimit = 2, length = 14, maxweight = 400, csar = 2 },
    ["OH-6A"] = { crates = false, troops = true, cratelimit = 0, trooplimit = 4, length = 7, maxweight = 550, csar = 4 },
    ["AH-64D_BLK_II"] = { crates = false, troops = false, cratelimit = 0, trooplimit = 0, length = 17, maxweight = 200, csar = 2 },
    ["Ka-50"] = { crates = false, troops = false, cratelimit = 0, trooplimit = 0, length = 15, maxweight = 200, csar = 2 },
    ["Ka-50_3"] = { crates = false, troops = false, cratelimit = 0, trooplimit = 0, length = 15, maxweight = 200, csar = 2 },
    ["C-130J-30"] = { crates = true, troops = true, cratelimit = 22, trooplimit = 30, length = 35, maxweight = 21500, csar = 30 },
  },
}

-- Optional overrides: define RH_CONFIG_OVERRIDES in a DO SCRIPT trigger that runs before rotorheads.lua.
local function merge(into, from)
  for k, v in pairs(from) do
    if type(v) == "table" and type(into[k]) == "table" and #v == 0 then
      merge(into[k], v)
    else
      into[k] = v
    end
  end
end
if type(RH_CONFIG_OVERRIDES) == "table" then merge(RH.config, RH_CONFIG_OVERRIDES) end

return RH.config
