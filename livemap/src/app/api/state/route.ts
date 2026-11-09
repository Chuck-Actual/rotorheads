import { connection } from "next/server";
import { currentState } from "@/lib/state-store";

export async function GET() {
  await connection();
  const state = await currentState();
  return Response.json(state, { headers: { "Cache-Control": "no-store" } });
}
