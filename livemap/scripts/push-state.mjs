#!/usr/bin/env node
// Runs on the DCS server machine. Watches livemap.json and pushes it to a hosted live map.
//
//   LIVEMAP_URL=https://your-map.example.com LIVEMAP_INGEST_TOKEN=... \
//   node push-state.mjs "C:\Users\YOU\Saved Games\DCS.dcs_serverrelease\rotorheads\livemap.json"

import { readFile, stat } from "node:fs/promises";

const file = process.argv[2];
const url = process.env.LIVEMAP_URL;
const token = process.env.LIVEMAP_INGEST_TOKEN;
const intervalMs = Number(process.env.PUSH_INTERVAL_MS ?? 15000);

if (!file || !url || !token) {
  console.error("Usage: LIVEMAP_URL=... LIVEMAP_INGEST_TOKEN=... node push-state.mjs <path to livemap.json>");
  process.exit(1);
}

let lastMtime = 0;

async function push() {
  try {
    const { mtimeMs } = await stat(file);
    if (mtimeMs === lastMtime) return;
    const body = await readFile(file, "utf8");
    const res = await fetch(new URL("/api/ingest", url), {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body,
    });
    if (!res.ok) {
      console.error(`${new Date().toISOString()} push failed: ${res.status} ${await res.text()}`);
      return;
    }
    lastMtime = mtimeMs;
    console.log(`${new Date().toISOString()} pushed ${body.length} bytes`);
  } catch (err) {
    console.error(`${new Date().toISOString()} ${err instanceof Error ? err.message : err}`);
  }
}

await push();
setInterval(push, intervalMs);
