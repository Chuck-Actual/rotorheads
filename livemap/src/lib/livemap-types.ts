// Mirrors the JSON written by mission/src/rh/livemap.lua.

export type LatLon = { lat: number; lon: number };

export type FactoryStatus = "active" | "destroyed" | "captured";
export type OutpostStatus = "intact" | "contested" | "captured";
export type ZoneColor = "yellow" | "blue" | "red" | null;

export type Factory = LatLon & { name: string; status: FactoryStatus };
export type Outpost = LatLon & { name: string; status: OutpostStatus; color?: ZoneColor; radius: number };
export type Farp = LatLon & { name: string; lc: boolean; crates: number; built: boolean };
export type Mash = LatLon & { name: string; patients: number; capacity: number };
export type BlueZone = LatLon & { name: string; radius: number };
export type Threat = LatLon & { kind: "aa" | "ground"; type: string; age: number };
export type RedAircraft = LatLon & { kind: "havoc" | "halo" | "helo" | "fighter"; type: string; heading: number };
export type Player = LatLon & {
  name: string;
  type: string;
  coalition: "blue" | "red";
  heading: number;
  altitude: number;
  lives?: number;
};
export type Csar = LatLon & { name: string; description: string };
export type Mark = LatLon & { text: string };
export type Convoy = LatLon & { from: string; to: string; underAttack: boolean };

export type Snapshot = {
  campaign: string;
  theatre: string;
  generatedAt: number;
  missionTime: number;
  timeOfDay: number;
  restartIn: number;
  factories: Factory[];
  outposts: Outpost[];
  farps: Farp[];
  mashes: Mash[];
  blueZones: BlueZone[];
  threats: Threat[];
  redAir: RedAircraft[];
  players: Player[];
  csar: Csar[];
  marks: Mark[];
  convoy?: Convoy | null;
};

export type StateSource = "file" | "ingest" | "demo";

export type StateResponse = {
  source: StateSource;
  receivedAt: number;
  snapshot: Snapshot;
};
