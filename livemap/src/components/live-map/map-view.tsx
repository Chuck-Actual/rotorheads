"use client";

import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { useEffect, useMemo } from "react";
import { Circle, CircleMarker, MapContainer, Marker, Popup, TileLayer, Tooltip, useMap } from "react-leaflet";
import type { Snapshot } from "@/lib/livemap-types";
import { airframe, isUtility } from "@/lib/format";
import type { LayerState } from "./layers";

export type FocusTarget = { lat: number; lon: number; zoom?: number; key: number };

const OUTPOST_COLORS: Record<string, string> = {
  yellow: "#facc15",
  blue: "#3b82f6",
  red: "#ef4444",
};

function divIcon(className: string, html: string, size = 28) {
  return L.divIcon({ className: `rh-icon ${className}`, html, iconSize: [size, size], iconAnchor: [size / 2, size / 2] });
}

function arrow(heading: number, color: string) {
  const deg = Number.isFinite(Number(heading)) ? Number(heading) : 0;
  return `<svg viewBox="0 0 24 24" width="22" height="22" style="transform: rotate(${deg}deg)"><path d="M12 2 L19 21 L12 17 L5 21 Z" fill="${color}" stroke="#0b1220" stroke-width="1.2"/></svg>`;
}

function FlyTo({ focus }: { focus: FocusTarget | null }) {
  const map = useMap();
  useEffect(() => {
    if (focus) map.flyTo([focus.lat, focus.lon], focus.zoom ?? 12, { duration: 0.8 });
  }, [focus, map]);
  return null;
}

function FitOnce({ snapshot }: { snapshot: Snapshot }) {
  const map = useMap();
  const theatre = snapshot.theatre;
  useEffect(() => {
    const pts: Array<[number, number]> = [
      ...snapshot.farps.map((f) => [f.lat, f.lon] as [number, number]),
      ...snapshot.outposts.map((o) => [o.lat, o.lon] as [number, number]),
      ...snapshot.factories.map((f) => [f.lat, f.lon] as [number, number]),
    ];
    if (pts.length > 1) map.fitBounds(L.latLngBounds(pts), { padding: [40, 40] });
    // Only re-fit when the theatre changes, not on every poll.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [theatre, map]);
  return null;
}

export default function MapView({
  snapshot,
  layers,
  focus,
}: {
  snapshot: Snapshot;
  layers: LayerState;
  focus: FocusTarget | null;
}) {
  const icons = useMemo(
    () => ({
      farp: divIcon("rh-farp", "F", 22),
      lc: divIcon("rh-lc", "LC", 26),
      mash: divIcon("rh-mash", "+", 22),
      factory: (status: string) => divIcon(`rh-factory rh-factory-${status}`, "&#9881;", 26),
      csar: divIcon("rh-csar", "", 22),
      convoy: (attack: boolean) => divIcon(`rh-convoy ${attack ? "rh-convoy-attack" : ""}`, "&#9951;", 24),
    }),
    [],
  );

  return (
    <MapContainer center={[35.7, 36.4]} zoom={9} className="h-full w-full" zoomControl preferCanvas>
      <TileLayer
        className="rh-tiles"
        attribution="Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics"
        url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        maxZoom={17}
      />
      <FitOnce snapshot={snapshot} />
      <FlyTo focus={focus} />

      {layers.blueZones &&
        snapshot.blueZones.map((z) => (
          <Circle
            key={`bz-${z.name}`}
            center={[z.lat, z.lon]}
            radius={z.radius}
            pathOptions={{ color: "#3b82f6", weight: 1, opacity: 0.5, fillOpacity: 0.06, dashArray: "4 6" }}
          >
            <Tooltip sticky>{z.name}</Tooltip>
          </Circle>
        ))}

      {layers.objectives &&
        snapshot.outposts.map((o) => {
          const color =
            o.status === "captured" ? "#3b82f6" : o.status === "contested" ? OUTPOST_COLORS[o.color ?? "yellow"] : "#ef4444";
          return o.status === "intact" ? (
            <CircleMarker
              key={`op-${o.name}`}
              center={[o.lat, o.lon]}
              radius={7}
              pathOptions={{ color: "#7f1d1d", fillColor: "#ef4444", fillOpacity: 0.9, weight: 2 }}
            >
              <Tooltip>REDFOR outpost {o.name}</Tooltip>
            </CircleMarker>
          ) : (
            <Circle
              key={`op-${o.name}`}
              center={[o.lat, o.lon]}
              radius={o.radius}
              pathOptions={{ color, weight: 2, fillOpacity: 0.15 }}
            >
              <Tooltip>
                {o.status === "captured" ? `Captured outpost ${o.name}` : `Contested outpost ${o.name} (${o.color ?? "yellow"})`}
              </Tooltip>
            </Circle>
          );
        })}

      {layers.objectives &&
        snapshot.factories.map((f) => (
          <Marker key={`fac-${f.name}`} position={[f.lat, f.lon]} icon={icons.factory(f.status)}>
            <Tooltip>
              Factory {f.name}: {f.status}
            </Tooltip>
          </Marker>
        ))}

      {layers.threats &&
        snapshot.threats.map((t, i) => {
          const freshness = Math.max(0.15, 1 - t.age / 1800);
          return (
            <CircleMarker
              key={`th-${i}`}
              center={[t.lat, t.lon]}
              radius={t.kind === "aa" ? 9 : 14}
              pathOptions={{
                stroke: t.kind === "aa",
                color: "#fecaca",
                weight: 1.5,
                fillColor: t.kind === "aa" ? "#f43f5e" : "#dc2626",
                fillOpacity: (t.kind === "aa" ? 0.8 : 0.35) * freshness,
              }}
            >
              <Tooltip>
                {t.kind === "aa" ? "Air defence" : "Ground unit"}: {t.type}
              </Tooltip>
            </CircleMarker>
          );
        })}

      {layers.farps &&
        snapshot.farps.map((f) => (
          <Marker key={`farp-${f.name}`} position={[f.lat, f.lon]} icon={f.lc ? icons.lc : icons.farp}>
            <Tooltip>
              {f.name} · {f.crates < 0 || f.lc ? "unlimited crates" : `${f.crates} crates`}
            </Tooltip>
          </Marker>
        ))}

      {layers.mashes &&
        snapshot.mashes.map((m) => (
          <Marker key={`mash-${m.name}`} position={[m.lat, m.lon]} icon={icons.mash}>
            <Tooltip>
              {m.name} · {m.patients}/{m.capacity} patients
            </Tooltip>
          </Marker>
        ))}

      {layers.convoy && snapshot.convoy && (
        <>
          <Circle
            center={[snapshot.convoy.lat, snapshot.convoy.lon]}
            radius={6000}
            pathOptions={{ color: "#facc15", weight: 1.5, fillOpacity: 0.05, dashArray: "6 6" }}
          />
          <Marker position={[snapshot.convoy.lat, snapshot.convoy.lon]} icon={icons.convoy(snapshot.convoy.underAttack)}>
            <Tooltip>
              Convoy {snapshot.convoy.from} → {snapshot.convoy.to}
              {snapshot.convoy.underAttack ? " · UNDER ATTACK" : ""}
            </Tooltip>
          </Marker>
        </>
      )}

      {layers.csar &&
        snapshot.csar.map((c) => (
          <Marker key={`csar-${c.name}`} position={[c.lat, c.lon]} icon={icons.csar}>
            <Popup>
              <strong>Downed pilot</strong>
              <br />
              {c.description}
            </Popup>
            <Tooltip>CSAR: {c.description}</Tooltip>
          </Marker>
        ))}

      {layers.redAir &&
        snapshot.redAir.map((a, i) => (
          <Marker
            key={`ra-${i}`}
            position={[a.lat, a.lon]}
            icon={divIcon("rh-redair", arrow(a.heading, a.kind === "fighter" ? "#fb923c" : "#ef4444"), 22)}
          >
            <Tooltip>
              {a.kind === "havoc" ? "Mi-28 Havoc" : a.kind === "halo" ? "Mi-26 Halo" : a.type}
            </Tooltip>
          </Marker>
        ))}

      {layers.players &&
        snapshot.players.map((p) => (
          <Marker
            key={`pl-${p.name}`}
            position={[p.lat, p.lon]}
            icon={divIcon("rh-player", arrow(p.heading, isUtility(p.type) ? "#38bdf8" : "#a5b4fc"), 22)}
          >
            <Tooltip>
              {p.name} · {airframe(p.type)} · {p.altitude} m
              {p.lives !== undefined ? ` · ${p.lives} lives` : ""}
            </Tooltip>
          </Marker>
        ))}

      {layers.marks &&
        snapshot.marks.map((m, i) => (
          <Marker key={`mk-${i}`} position={[m.lat, m.lon]} icon={divIcon("rh-mark", "", 14)}>
            <Tooltip>{m.text}</Tooltip>
          </Marker>
        ))}
    </MapContainer>
  );
}
