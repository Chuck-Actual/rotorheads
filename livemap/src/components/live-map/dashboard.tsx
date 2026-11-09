"use client";

import dynamic from "next/dynamic";
import { AlertTriangle, Clock, LifeBuoy, RefreshCw, RotateCcw, Users } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ago, clock, duration } from "@/lib/format";
import { cn } from "@/lib/utils";
import { DEFAULT_LAYERS, type LayerId, type LayerState } from "./layers";
import type { FocusTarget } from "./map-view";
import { SidePanel } from "./side-panel";
import { useLiveState } from "./use-live-state";

const MapView = dynamic(() => import("./map-view"), {
  ssr: false,
  loading: () => <MapPlaceholder />,
});

function MapPlaceholder() {
  return (
    <div className="flex h-full w-full items-center justify-center bg-[#0b1220] text-sm text-muted-foreground">
      Loading map…
    </div>
  );
}

function Stat({ icon, label, value, tone }: { icon: React.ReactNode; label: string; value: string; tone?: string }) {
  return (
    <div className="flex items-center gap-2 rounded-md border border-border/60 bg-card/60 px-2.5 py-1.5">
      <span className={cn("text-muted-foreground", tone)}>{icon}</span>
      <span className="leading-tight">
        <span className="block text-[10px] uppercase tracking-wider text-muted-foreground">{label}</span>
        <span className="font-mono text-sm font-semibold">{value}</span>
      </span>
    </div>
  );
}

export function Dashboard() {
  const { data, error, fetchedAt, refreshing, refresh } = useLiveState();
  const [layers, setLayers] = useState<LayerState>(DEFAULT_LAYERS);
  const [focus, setFocus] = useState<FocusTarget | null>(null);
  const [now, setNow] = useState(0);

  useEffect(() => {
    const tick = () => setNow(Date.now());
    const first = setTimeout(tick, 0);
    const id = setInterval(tick, 1000);
    return () => {
      clearTimeout(first);
      clearInterval(id);
    };
  }, []);

  const onFocus = useCallback((lat: number, lon: number, zoom?: number) => {
    setFocus({ lat, lon, zoom, key: Date.now() });
  }, []);

  const onToggleLayer = useCallback((id: LayerId, on: boolean) => {
    setLayers((prev) => ({ ...prev, [id]: on }));
  }, []);

  const s = data?.snapshot;
  const sinceFetch = fetchedAt && now > fetchedAt ? Math.floor((now - fetchedAt) / 1000) : 0;
  const timeOfDay = s ? s.timeOfDay + sinceFetch : 0;
  const restartIn = s ? s.restartIn - sinceFetch : 0;
  const isDemo = data?.source === "demo";

  return (
    <div className="dark flex h-dvh flex-col bg-background text-foreground">
      <header className="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-border px-4 py-3">
        <div className="mr-auto flex items-center gap-3">
          <div className="flex size-9 items-center justify-center rounded-md bg-sky-600 font-mono text-sm font-black tracking-tighter text-white">
            RH
          </div>
          <div>
            <h1 className="text-base font-semibold leading-tight">{s?.campaign ?? "Rotorheads Live Map"}</h1>
            <p className="text-xs text-muted-foreground">
              {s ? `${s.theatre} theatre` : "Connecting to server…"}
              {data && (
                <>
                  {" · "}
                  {isDemo ? "demo data" : `updated ${ago(now - data.receivedAt)}`}
                </>
              )}
            </p>
          </div>
          {data &&
            (isDemo ? (
              <Badge variant="outline" className="border-amber-500/40 bg-amber-500/10 text-amber-300">
                Demo
              </Badge>
            ) : (
              <Badge variant="outline" className="border-emerald-500/40 bg-emerald-500/10 text-emerald-300">
                <span className="mr-1 inline-block size-1.5 animate-pulse rounded-full bg-emerald-400" />
                Live
              </Badge>
            ))}
        </div>
        {s ? (
          <div className="flex flex-wrap items-center gap-2">
            <Stat icon={<Clock className="size-4" />} label="In-game" value={clock(timeOfDay)} />
            <Stat icon={<RotateCcw className="size-4" />} label="Restart in" value={duration(restartIn)} />
            <Stat icon={<Users className="size-4" />} label="Pilots" value={String(s.players.length)} />
            <Stat
              icon={<LifeBuoy className="size-4" />}
              label="CSAR"
              value={String(s.csar.length)}
              tone={s.csar.length > 0 ? "text-sky-400" : undefined}
            />
          </div>
        ) : (
          <div className="flex gap-2">
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-10 w-24" />
            ))}
          </div>
        )}
        <Button variant="outline" size="sm" onClick={refresh} disabled={refreshing} aria-label="Refresh now">
          <RefreshCw className={cn("size-4", refreshing && "animate-spin")} />
          <span className="hidden sm:inline">Refresh</span>
        </Button>
      </header>

      <main className="flex min-h-0 flex-1 flex-col lg:flex-row">
        <div className="relative h-[55dvh] min-h-[320px] lg:order-2 lg:h-auto lg:flex-1">
          {s ? <MapView snapshot={s} layers={layers} focus={focus} /> : <MapPlaceholder />}
        </div>
        <aside className="flex min-h-0 flex-1 flex-col border-t border-border lg:order-1 lg:w-[380px] lg:flex-none lg:border-r lg:border-t-0">
          {error && (
            <Alert variant="destructive" className="m-3 mb-0 w-auto">
              <AlertTriangle />
              <AlertTitle>Live map unreachable</AlertTitle>
              <AlertDescription>
                {error}. {s ? "Showing the last known picture." : "Retrying every 15 seconds."}
              </AlertDescription>
            </Alert>
          )}
          {isDemo && (
            <Alert className="m-3 mb-0 w-auto border-amber-500/30 bg-amber-500/5">
              <AlertTitle>No DCS server connected</AlertTitle>
              <AlertDescription>
                You are looking at a sample Syria campaign. Point <code>LIVEMAP_STATE_FILE</code> at your server&apos;s
                livemap.json, or push it to <code>/api/ingest</code>, to see your own war.
              </AlertDescription>
            </Alert>
          )}
          {s ? (
            <SidePanel snapshot={s} layers={layers} onToggleLayer={onToggleLayer} focus={onFocus} />
          ) : (
            <div className="space-y-3 p-4">
              <Skeleton className="h-8 w-full" />
              {[0, 1, 2, 3, 4].map((i) => (
                <Skeleton key={i} className="h-12 w-full" />
              ))}
            </div>
          )}
        </aside>
      </main>
    </div>
  );
}
