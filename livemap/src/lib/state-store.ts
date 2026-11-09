import { readFile } from "node:fs/promises";
import { demoSnapshot } from "./demo-snapshot";
import type { Snapshot, StateResponse } from "./livemap-types";

// Snapshots older than this are treated as stale and the demo is shown instead.
const STALE_AFTER_MS = 10 * 60 * 1000;

let ingested: { snapshot: Snapshot; receivedAt: number } | null = null;

export function isSnapshot(value: unknown): value is Snapshot {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.theatre === "string" &&
    typeof v.generatedAt === "number" &&
    Array.isArray(v.farps) &&
    Array.isArray(v.players) &&
    Array.isArray(v.threats)
  );
}

export function storeIngested(snapshot: Snapshot) {
  ingested = { snapshot, receivedAt: Date.now() };
}

async function fromFile(): Promise<StateResponse | null> {
  const path = process.env.LIVEMAP_STATE_FILE;
  if (!path) return null;
  try {
    const raw = await readFile(path, "utf8");
    const parsed: unknown = JSON.parse(raw);
    if (!isSnapshot(parsed)) return null;
    return { source: "file", receivedAt: parsed.generatedAt * 1000, snapshot: parsed };
  } catch {
    return null;
  }
}

export async function currentState(): Promise<StateResponse> {
  const file = await fromFile();
  if (file) return file;
  if (ingested && Date.now() - ingested.receivedAt < STALE_AFTER_MS) {
    return { source: "ingest", receivedAt: ingested.receivedAt, snapshot: ingested.snapshot };
  }
  return { source: "demo", receivedAt: Date.now(), snapshot: demoSnapshot() };
}
