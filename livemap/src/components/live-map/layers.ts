export const LAYERS = [
  { id: "threats", label: "Spotted REDFOR", hint: "Red blobs fade over 30 minutes" },
  { id: "redAir", label: "Enemy aircraft", hint: "Havocs, Halos and fighters" },
  { id: "players", label: "Pilots", hint: "Player aircraft" },
  { id: "csar", label: "CSAR", hint: "Downed pilots awaiting rescue" },
  { id: "farps", label: "FARPs & LCs", hint: "Crate stock on hover" },
  { id: "mashes", label: "MASH", hint: "Capacity 30 each" },
  { id: "objectives", label: "Outposts & factories", hint: "Contested zones in yellow" },
  { id: "blueZones", label: "Blue zones", hint: "Friendly areas of operation" },
  { id: "marks", label: "F10 marks", hint: "Player map markers" },
  { id: "convoy", label: "Convoy escort", hint: "Side mission" },
] as const;

export type LayerId = (typeof LAYERS)[number]["id"];
export type LayerState = Record<LayerId, boolean>;

export const DEFAULT_LAYERS: LayerState = Object.fromEntries(LAYERS.map((l) => [l.id, true])) as LayerState;
