"use client";

import { Crosshair, Factory as FactoryIcon, HeartPulse, LifeBuoy, Package, Plane, Shield, Truck } from "lucide-react";
import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { airframe, isUtility } from "@/lib/format";
import type { Snapshot } from "@/lib/livemap-types";
import { cn } from "@/lib/utils";
import { LAYERS, type LayerId, type LayerState } from "./layers";

type Focus = (lat: number, lon: number, zoom?: number) => void;

function Section({ title, icon, children }: { title: string; icon: ReactNode; children: ReactNode }) {
  return (
    <section className="space-y-2">
      <h3 className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        {icon}
        {title}
      </h3>
      {children}
    </section>
  );
}

function Row({ onClick, children, className }: { onClick?: () => void; children: ReactNode; className?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex w-full items-center justify-between gap-3 rounded-md border border-border/60 bg-card/60 px-3 py-2 text-left text-sm transition-colors hover:bg-accent focus-visible:outline-2",
        className,
      )}
    >
      {children}
    </button>
  );
}

function Empty({ children }: { children: ReactNode }) {
  return <p className="rounded-md border border-dashed border-border px-3 py-4 text-center text-sm text-muted-foreground">{children}</p>;
}

function Meter({ value, max, tone }: { value: number; max: number; tone: "blue" | "red" | "amber" }) {
  const pct = Math.min(100, Math.round((value / Math.max(1, max)) * 100));
  const color = tone === "red" ? "bg-red-500" : tone === "amber" ? "bg-amber-400" : "bg-sky-500";
  return (
    <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
      <div className={cn("h-full rounded-full", color)} style={{ width: `${pct}%` }} />
    </div>
  );
}

const FACTORY_BADGE: Record<string, string> = {
  active: "bg-red-500/15 text-red-300 border-red-500/30",
  destroyed: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  captured: "bg-sky-500/15 text-sky-300 border-sky-500/30",
};

function FrontTab({ s, focus }: { s: Snapshot; focus: Focus }) {
  const outposts = [...s.outposts].sort((a, b) => (a.status === "contested" ? -1 : b.status === "contested" ? 1 : 0));
  return (
    <div className="space-y-5">
      <Section title="Factories" icon={<FactoryIcon className="size-3.5" />}>
        {s.factories.length === 0 ? (
          <Empty>No factories spotted yet. They show up once a blue unit gets within 5 km.</Empty>
        ) : (
          s.factories.map((f) => (
            <Row key={f.name} onClick={() => focus(f.lat, f.lon, 12)}>
              <span className="font-medium">{f.name}</span>
              <Badge variant="outline" className={FACTORY_BADGE[f.status]}>
                {f.status}
              </Badge>
            </Row>
          ))
        )}
      </Section>
      <Section title="Outposts" icon={<Shield className="size-3.5" />}>
        {outposts.length === 0 ? (
          <Empty>No outposts in this campaign.</Empty>
        ) : (
          outposts.map((o) => (
            <Row key={o.name} onClick={() => focus(o.lat, o.lon, 12)}>
              <span className="font-medium">{o.name}</span>
              <Badge
                variant="outline"
                className={
                  o.status === "captured"
                    ? FACTORY_BADGE.captured
                    : o.status === "contested"
                      ? o.color === "blue"
                        ? "border-sky-500/40 bg-sky-500/15 text-sky-300"
                        : o.color === "red"
                          ? FACTORY_BADGE.active
                          : "border-yellow-500/40 bg-yellow-500/15 text-yellow-300"
                      : FACTORY_BADGE.active
                }
              >
                {o.status === "contested" ? `contested · ${o.color ?? "yellow"}` : o.status === "intact" ? "REDFOR" : "captured"}
              </Badge>
            </Row>
          ))
        )}
      </Section>
      <Section title="Spotted threats" icon={<Crosshair className="size-3.5" />}>
        <div className="grid grid-cols-2 gap-2 text-sm">
          <div className="rounded-md border border-border/60 bg-card/60 p-3">
            <div className="text-2xl font-semibold text-rose-400">{s.threats.filter((t) => t.kind === "aa").length}</div>
            <div className="text-muted-foreground">air defence reports</div>
          </div>
          <div className="rounded-md border border-border/60 bg-card/60 p-3">
            <div className="text-2xl font-semibold text-red-400">{s.threats.filter((t) => t.kind === "ground").length}</div>
            <div className="text-muted-foreground">ground contacts</div>
          </div>
        </div>
        {s.redAir.length > 0 && (
          <div className="space-y-2 pt-1">
            {s.redAir.map((a, i) => (
              <Row key={i} onClick={() => focus(a.lat, a.lon, 11)}>
                <span className="flex items-center gap-2">
                  <Plane className="size-3.5 text-red-400" />
                  {a.kind === "havoc" ? "Mi-28 Havoc" : a.kind === "halo" ? "Mi-26 Halo (repair flight)" : a.type}
                </span>
                <span className="font-mono text-xs text-muted-foreground">{String(a.heading).padStart(3, "0")}°</span>
              </Row>
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function CsarTab({ s, focus }: { s: Snapshot; focus: Focus }) {
  return (
    <Section title={`Downed pilots (${s.csar.length})`} icon={<LifeBuoy className="size-3.5" />}>
      {s.csar.length === 0 ? (
        <Empty>No downed pilots. Good flying.</Empty>
      ) : (
        s.csar.map((c) => (
          <Row key={c.name} onClick={() => focus(c.lat, c.lon, 13)}>
            <span>
              <span className="block font-medium">{c.description}</span>
              <span className="font-mono text-xs text-muted-foreground">
                {c.lat.toFixed(3)}, {c.lon.toFixed(3)}
              </span>
            </span>
            <span className="text-xs text-sky-300">Locate</span>
          </Row>
        ))
      )}
      <p className="text-xs text-muted-foreground">
        Deliver rescued pilots to a MASH, airfield or ship to give their lives back. Place a <code>-extract</code> marker to
        move up to four nearby pilots to an LZ.
      </p>
    </Section>
  );
}

function LogisticsTab({ s, focus }: { s: Snapshot; focus: Focus }) {
  return (
    <div className="space-y-5">
      <Section title="FARPs & Logistics Centers" icon={<Package className="size-3.5" />}>
        {s.farps.length === 0 ? (
          <Empty>No FARPs yet. Bring 9 FARP crates from a Logistics Center to build one.</Empty>
        ) : (
          s.farps.map((f) => {
            const unlimited = f.lc || f.crates < 0;
            return (
              <Row key={f.name} onClick={() => focus(f.lat, f.lon, 12)} className="flex-col items-stretch">
                <span className="flex items-center justify-between">
                  <span className="font-medium">{f.name}</span>
                  <span className={cn("text-xs", !unlimited && f.crates < 10 ? "text-amber-300" : "text-muted-foreground")}>
                    {unlimited ? "unlimited" : `${f.crates} crates`}
                  </span>
                </span>
                {!unlimited && <Meter value={f.crates} max={80} tone={f.crates < 10 ? "amber" : "blue"} />}
              </Row>
            );
          })
        )}
      </Section>
      <Section title="MASH" icon={<HeartPulse className="size-3.5" />}>
        {s.mashes.length === 0 ? (
          <Empty>No MASH built. Four MASH crates inside a blue zone make one.</Empty>
        ) : (
          s.mashes.map((m) => (
            <Row key={m.name} onClick={() => focus(m.lat, m.lon, 12)} className="flex-col items-stretch">
              <span className="flex items-center justify-between">
                <span className="font-medium">{m.name}</span>
                <span className={cn("text-xs", m.patients >= m.capacity ? "text-red-300" : "text-muted-foreground")}>
                  {m.patients}/{m.capacity}
                  {m.patients >= m.capacity ? " · full" : ""}
                </span>
              </span>
              <Meter value={m.patients} max={m.capacity} tone={m.patients >= m.capacity - 3 ? "red" : "blue"} />
            </Row>
          ))
        )}
      </Section>
      <Section title="Convoy escort" icon={<Truck className="size-3.5" />}>
        {s.convoy ? (
          <Row onClick={() => focus(s.convoy!.lat, s.convoy!.lon, 11)}>
            <span>
              <span className="block font-medium">
                {s.convoy.from} → {s.convoy.to}
              </span>
              <span className="text-xs text-muted-foreground">Armed UHs: keep the insurgents off the trucks</span>
            </span>
            {s.convoy.underAttack ? (
              <Badge variant="outline" className={FACTORY_BADGE.active}>
                under attack
              </Badge>
            ) : (
              <Badge variant="outline">en route</Badge>
            )}
          </Row>
        ) : (
          <Empty>No convoy running. A new one departs a few minutes after the last.</Empty>
        )}
      </Section>
    </div>
  );
}

function PilotsTab({ s, focus }: { s: Snapshot; focus: Focus }) {
  return (
    <Section title={`Pilots online (${s.players.length})`} icon={<Plane className="size-3.5" />}>
      {s.players.length === 0 ? (
        <Empty>Nobody is flying right now.</Empty>
      ) : (
        s.players.map((p) => (
          <Row key={p.name} onClick={() => focus(p.lat, p.lon, 12)}>
            <span>
              <span className="block font-medium">{p.name}</span>
              <span className="text-xs text-muted-foreground">
                {airframe(p.type)} · {p.altitude} m
              </span>
            </span>
            {isUtility(p.type) || p.lives === undefined ? (
              <span className="text-xs text-sky-300">∞ lives</span>
            ) : (
              <span className="flex gap-1" aria-label={`${p.lives} of 3 lives`}>
                {[0, 1, 2].map((i) => (
                  <span key={i} className={cn("size-2 rounded-full", i < (p.lives ?? 0) ? "bg-emerald-400" : "bg-muted")} />
                ))}
              </span>
            )}
          </Row>
        ))
      )}
    </Section>
  );
}

function LayersTab({ layers, onToggle }: { layers: LayerState; onToggle: (id: LayerId, on: boolean) => void }) {
  return (
    <div className="space-y-2">
      {LAYERS.map((l) => (
        <label
          key={l.id}
          className="flex cursor-pointer items-center justify-between gap-3 rounded-md border border-border/60 bg-card/60 px-3 py-2"
        >
          <span>
            <span className="block text-sm font-medium">{l.label}</span>
            <span className="text-xs text-muted-foreground">{l.hint}</span>
          </span>
          <Switch checked={layers[l.id]} onCheckedChange={(on) => onToggle(l.id, on)} />
        </label>
      ))}
    </div>
  );
}

export function SidePanel({
  snapshot,
  layers,
  onToggleLayer,
  focus,
}: {
  snapshot: Snapshot;
  layers: LayerState;
  onToggleLayer: (id: LayerId, on: boolean) => void;
  focus: Focus;
}) {
  return (
    <Tabs defaultValue="front" className="flex h-full min-h-0 flex-col gap-0">
      <div className="border-b border-border px-3 py-2">
        <TabsList className="w-full">
          <TabsTrigger value="front">Front</TabsTrigger>
          <TabsTrigger value="csar">
            CSAR
            {snapshot.csar.length > 0 && (
              <span className="ml-1 rounded-full bg-sky-500/20 px-1.5 text-[10px] text-sky-300">{snapshot.csar.length}</span>
            )}
          </TabsTrigger>
          <TabsTrigger value="logistics">Logistics</TabsTrigger>
          <TabsTrigger value="pilots">Pilots</TabsTrigger>
          <TabsTrigger value="layers">Layers</TabsTrigger>
        </TabsList>
      </div>
      <ScrollArea className="min-h-0 flex-1">
        <div className="p-4">
          <TabsContent value="front">
            <FrontTab s={snapshot} focus={focus} />
          </TabsContent>
          <TabsContent value="csar">
            <CsarTab s={snapshot} focus={focus} />
          </TabsContent>
          <TabsContent value="logistics">
            <LogisticsTab s={snapshot} focus={focus} />
          </TabsContent>
          <TabsContent value="pilots">
            <PilotsTab s={snapshot} focus={focus} />
          </TabsContent>
          <TabsContent value="layers">
            <LayersTab layers={layers} onToggle={onToggleLayer} />
          </TabsContent>
        </div>
      </ScrollArea>
    </Tabs>
  );
}
