import { timingSafeEqual } from "node:crypto";
import { isSnapshot, storeIngested } from "@/lib/state-store";

const MAX_BODY_BYTES = 2 * 1024 * 1024;

function authorized(request: Request) {
  const token = process.env.LIVEMAP_INGEST_TOKEN;
  if (!token) return false;
  const header = request.headers.get("authorization") ?? "";
  const given = Buffer.from(header.replace(/^Bearer\s+/i, ""));
  const expected = Buffer.from(token);
  return given.length === expected.length && timingSafeEqual(given, expected);
}

async function readLimited(request: Request, maxBytes: number): Promise<string | null> {
  if (Number(request.headers.get("content-length") ?? 0) > maxBytes) return null;
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString("utf8");
}

// The DCS host pushes livemap.json here (see scripts/push-state.mjs).
export async function POST(request: Request) {
  if (!process.env.LIVEMAP_INGEST_TOKEN) {
    return Response.json({ error: "Ingest is disabled. Set LIVEMAP_INGEST_TOKEN to enable it." }, { status: 503 });
  }
  if (!authorized(request)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }
  const text = await readLimited(request, MAX_BODY_BYTES);
  if (text === null) {
    return Response.json({ error: "Snapshot too large" }, { status: 413 });
  }
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return Response.json({ error: "Body must be JSON" }, { status: 400 });
  }
  if (!isSnapshot(body)) {
    return Response.json({ error: "Body is not a live map snapshot" }, { status: 422 });
  }
  storeIngested(body);
  return Response.json({ ok: true });
}
