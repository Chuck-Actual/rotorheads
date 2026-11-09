export function clock(secondsOfDay: number) {
  const s = ((Math.floor(secondsOfDay) % 86400) + 86400) % 86400;
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export function duration(seconds: number) {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m`;
  return `${m}m ${String(s % 60).padStart(2, "0")}s`;
}

export function ago(ms: number) {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  return `${Math.floor(m / 60)}h ago`;
}

const AIRFRAMES: Record<string, string> = {
  "AH-64D_BLK_II": "AH-64D Apache",
  "UH-60L": "UH-60L Black Hawk",
  "CH-47Fbl1": "CH-47F Chinook",
  "Mi-8MTV2": "Mi-8 Hip",
  "Mi-24P": "Mi-24P Hind",
  "UH-1H": "UH-1H Huey",
  OH58D: "OH-58D Kiowa",
  "OH-6A": "OH-6A Cayuse",
  "Ka-50": "Ka-50 Black Shark",
  "Ka-50_3": "Ka-50 Black Shark III",
  SA342M: "SA342M Gazelle",
  SA342L: "SA342L Gazelle",
  "C-130J-30": "C-130J-30 Hercules",
  "A-10C_2": "A-10C II",
};

export function airframe(type: string) {
  return AIRFRAMES[type] ?? type;
}

const UTILITY = new Set(["UH-1H", "UH-60L", "Mi-8MT", "Mi-8MTV2", "CH-47Fbl1", "C-130J-30", "Hercules"]);

export function isUtility(type: string) {
  return UTILITY.has(type);
}
