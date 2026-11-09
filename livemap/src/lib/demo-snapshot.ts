import type { Snapshot, Threat } from "./livemap-types";

// A plausible Latakia -> Aleppo front on the Syria map, used when no DCS server is connected.
// Aircraft positions drift with the clock so the demo feels alive.

const MSR: Array<[number, number]> = [
  [35.864, 36.802],
  [35.842, 36.742],
  [35.826, 36.689],
  [35.814, 36.641],
  [35.808, 36.612],
];

function orbit(center: [number, number], radiusDeg: number, periodSec: number, t: number, phase = 0) {
  const a = ((t / periodSec) * 2 * Math.PI + phase) % (2 * Math.PI);
  const lat = center[0] + Math.sin(a) * radiusDeg;
  const lon = center[1] + Math.cos(a) * radiusDeg * 1.2;
  const heading = Math.round(((Math.atan2(Math.cos(a), -Math.sin(a)) * 180) / Math.PI + 360) % 360);
  return { lat: +lat.toFixed(5), lon: +lon.toFixed(5), heading };
}

function along(path: Array<[number, number]>, fraction: number) {
  const f = Math.min(0.9999, Math.max(0, fraction)) * (path.length - 1);
  const i = Math.floor(f);
  const r = f - i;
  const [a, b] = [path[i], path[i + 1]];
  return { lat: +(a[0] + (b[0] - a[0]) * r).toFixed(5), lon: +(a[1] + (b[1] - a[1]) * r).toFixed(5) };
}

export function demoSnapshot(nowMs = Date.now()): Snapshot {
  const t = nowMs / 1000;
  const missionTime = Math.floor(t % (5 * 3600));

  const threats: Threat[] = [];
  MSR.forEach(([lat, lon], i) => {
    threats.push({ kind: i % 2 === 0 ? "aa" : "ground", type: i % 2 === 0 ? "ZSU-23-4 Shilka" : "BMP-2", lat, lon, age: (i * 300) % 1700 });
    threats.push({ kind: "ground", type: "T-72B", lat: lat + 0.004, lon: lon - 0.006, age: (i * 420 + 200) % 1700 });
  });
  threats.push(
    { kind: "aa", type: "SA-8 Osa", lat: 35.61, lon: 36.585, age: 120 },
    { kind: "ground", type: "BTR-80", lat: 35.605, lon: 36.6, age: 600 },
    { kind: "aa", type: "SA-13 Strela-10", lat: 35.95, lon: 36.74, age: 900 },
    { kind: "ground", type: "Ural-375", lat: 35.958, lon: 36.758, age: 1500 },
  );

  const convoyPos = along(
    [
      [35.401, 35.948],
      [35.52, 36.08],
      [35.64, 36.21],
      [35.7, 36.47],
    ],
    (t % 2400) / 2400,
  );

  return {
    campaign: "Rotorheads Private",
    theatre: "Syria",
    generatedAt: Math.floor(t),
    missionTime,
    timeOfDay: Math.floor((8 * 3600 + missionTime) % 86400),
    restartIn: 5 * 3600 - missionTime,
    factories: [
      { name: "Saraqib", status: "destroyed", lat: 35.866, lon: 36.812 },
      { name: "Idlib", status: "active", lat: 35.932, lon: 36.634 },
      { name: "Jisr al-Shughur", status: "captured", lat: 35.81, lon: 36.33 },
    ],
    outposts: [
      { name: "Ariha", status: "contested", color: "blue", radius: 2778, lat: 35.813, lon: 36.607 },
      { name: "Kafr Nabl", status: "intact", color: null, radius: 2778, lat: 35.613, lon: 36.562 },
      { name: "Taftanaz", status: "intact", color: null, radius: 2778, lat: 35.97, lon: 36.785 },
      { name: "Mhambal", status: "captured", color: null, radius: 2778, lat: 35.767, lon: 36.444 },
    ],
    farps: [
      { name: "LC Bassel Al-Assad", lc: true, crates: -1, built: false, lat: 35.401, lon: 35.948 },
      { name: "FARP Alpha", lc: false, crates: 34, built: false, lat: 35.78, lon: 36.29 },
      { name: "FARP Bravo", lc: false, crates: 12, built: true, lat: 35.7, lon: 36.47 },
      { name: "FARP Charlie", lc: false, crates: 51, built: true, lat: 35.5, lon: 36.33 },
    ],
    mashes: [
      { name: "MASH 01", patients: 17, capacity: 30, lat: 35.62, lon: 36.25 },
      { name: "MASH 02", patients: 29, capacity: 30, lat: 35.74, lon: 36.4 },
    ],
    blueZones: [
      { name: "Alpha AO", radius: 12000, lat: 35.78, lon: 36.29 },
      { name: "Bravo AO", radius: 10000, lat: 35.7, lon: 36.47 },
      { name: "Charlie AO", radius: 10000, lat: 35.5, lon: 36.33 },
    ],
    threats,
    redAir: [
      { kind: "havoc", type: "Mi-28N", ...orbit([35.83, 36.66], 0.03, 600, t) },
      { kind: "halo", type: "Mi-26", heading: 290, ...along([[35.73, 37.1], [35.866, 36.812]], (t % 1800) / 1800) },
      { kind: "fighter", type: "MiG-29A", ...orbit([35.95, 37.0], 0.12, 400, t, 2) },
    ],
    players: [
      { name: "Viper 1-1", type: "AH-64D_BLK_II", coalition: "blue", altitude: 60, lives: 2, ...orbit([35.8, 36.56], 0.02, 500, t) },
      { name: "Viper 1-2", type: "AH-64D_BLK_II", coalition: "blue", altitude: 55, lives: 3, ...orbit([35.8, 36.56], 0.02, 500, t, 0.4) },
      { name: "Dustoff 2", type: "UH-60L", coalition: "blue", altitude: 150, ...orbit([35.66, 36.38], 0.05, 900, t, 1) },
      { name: "Big Windy", type: "CH-47Fbl1", coalition: "blue", altitude: 300, ...orbit([35.6, 36.2], 0.08, 1500, t, 3) },
      { name: "Hip Hop", type: "Mi-8MTV2", coalition: "blue", altitude: 90, ...orbit([35.75, 36.32], 0.02, 700, t, 2) },
      { name: "Scout 3", type: "OH58D", coalition: "blue", altitude: 40, lives: 1, ...orbit([35.62, 36.52], 0.015, 400, t, 5) },
      { name: "Hog 1", type: "A-10C_2", coalition: "blue", altitude: 4200, lives: 3, ...orbit([35.65, 36.15], 0.15, 300, t, 4) },
    ],
    csar: [
      { name: "CSAR-1", description: "Viper 1-1 (AH-64D)", lat: 35.829, lon: 36.653 },
      { name: "CSAR-2", description: "Scout 3 (OH-58D)", lat: 35.64, lon: 36.548 },
      { name: "CSAR-3", description: "Ghost 2 (Ka-50)", lat: 35.9, lon: 36.69 },
    ],
    marks: [
      { text: "SA-8 here, avoid north valley", lat: 35.615, lon: 36.58 },
      { text: "-wpzone", lat: 35.805, lon: 36.59 },
      { text: "LZ for Ariha assault", lat: 35.79, lon: 36.57 },
    ],
    convoy: { from: "LC Bassel Al-Assad", to: "FARP Bravo", underAttack: Math.floor(t / 300) % 3 === 0, ...convoyPos },
  };
}
