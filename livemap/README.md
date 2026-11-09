# Rotorheads Live Map

Web map for the private Rotorheads-style DCS campaign in this repo. See the [root README](../README.md) for the full setup.

```bash
npm install
npm run dev   # http://localhost:4317
```

Data sources, in priority order:

1. `LIVEMAP_STATE_FILE`: path to `livemap.json` written by the mission (when the map runs on the DCS machine).
2. `POST /api/ingest` with `Authorization: Bearer $LIVEMAP_INGEST_TOKEN` (see `scripts/push-state.mjs`).
3. Built-in demo snapshot of a Syria campaign.
