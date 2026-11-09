"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { StateResponse } from "@/lib/livemap-types";

const POLL_MS = 15_000;

export function useLiveState() {
  const [data, setData] = useState<StateResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [fetchedAt, setFetchedAt] = useState<number | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const inFlight = useRef(false);

  const refresh = useCallback(async () => {
    if (inFlight.current) return;
    inFlight.current = true;
    setRefreshing(true);
    try {
      const res = await fetch("/api/state", { cache: "no-store" });
      if (!res.ok) throw new Error(`Server answered ${res.status}`);
      setData((await res.json()) as StateResponse);
      setError(null);
      setFetchedAt(Date.now());
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not reach the live map server");
    } finally {
      inFlight.current = false;
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    const first = setTimeout(refresh, 0);
    const id = setInterval(refresh, POLL_MS);
    return () => {
      clearTimeout(first);
      clearInterval(id);
    };
  }, [refresh]);

  return { data, error, fetchedAt, refreshing, refresh };
}
