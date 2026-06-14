import { useEffect, useMemo, useRef, useState } from "react";
import {
  Search, Activity, X, ArrowLeft, Download, Moon, Sun,
  ChevronRight, Layers, CalendarDays, RotateCcw, AlertTriangle,
  TrendingUp, TrendingDown, LineChart, CheckCircle2,
} from "lucide-react";
import {
  indexData, searchParams, flagFor, refFor, fmt,
  FLAG_HSL, SERIES_COLORS,
  type HealthData, type Indexed, type Measurement, type ParamCatalog, type Flag,
} from "@/lib/health";
import {
  PANELS, panelMembers, latestFlag, attentionParams, passesFilter,
  type Panel, type RangeFilter,
} from "@/lib/panels";
import { Sparkline } from "@/components/Sparkline";
import { TrendChart } from "@/components/TrendChart";
import { InstallButton } from "@/components/InstallButton";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

type SortKey = keyof Pick<Measurement, "date" | "parameter" | "value" | "unit" | "ref_text" | "flag" | "lab"> | "sources";

export default function App() {
  const [idx, setIdx] = useState<Indexed | null>(null);
  const [needPick, setNeedPick] = useState(false);
  const [dark, setDark] = useState(false);

  const [selected, setSelected] = useState<string[]>([]);
  const [activeCat, setActiveCat] = useState<string | null>(null);
  const [activePanel, setActivePanel] = useState<string | null>(null);
  const [rangeFilter, setRangeFilter] = useState<RangeFilter>("all");
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [hi, setHi] = useState(-1);

  const [dateFrom, setDateFrom] = useState<string | null>(null);
  const [dateTo, setDateTo] = useState<string | null>(null);
  const [normalize, setNormalize] = useState(false);

  const [sortKey, setSortKey] = useState<SortKey>("date");
  const [sortDir, setSortDir] = useState(-1);

  const searchRef = useRef<HTMLDivElement>(null);

  // ---- load ----
  useEffect(() => {
    fetch("./health_data.json")
      .then((r) => { if (!r.ok) throw new Error(); return r.json(); })
      .then((d: HealthData) => setIdx(indexData(d)))
      .catch(() => setNeedPick(true));
  }, []);

  useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
  }, [dark]);

  useEffect(() => {
    const h = (e: MouseEvent) => {
      if (searchRef.current && !searchRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", h);
    return () => document.removeEventListener("mousedown", h);
  }, []);

  const onFile = (f: File) => {
    const rd = new FileReader();
    rd.onload = () => {
      try { setIdx(indexData(JSON.parse(rd.result as string))); setNeedPick(false); }
      catch (e) { alert("Bad JSON: " + (e as Error).message); }
    };
    rd.readAsText(f);
  };

  // ---- derived ----
  const results = useMemo(() => (idx ? searchParams(idx, query) : []), [idx, query]);

  const catGroups = useMemo(() => {
    if (!idx) return [];
    const order = idx.data.summary.categories;
    const map: Record<string, ParamCatalog[]> = {};
    for (const p of idx.data.parameters) (map[p.category] ||= []).push(p);
    return order
      .filter((c) => map[c]?.length)
      .map((c) => ({
        cat: c,
        params: map[c].slice().sort((a, b) => (b.numeric_count || 0) - (a.numeric_count || 0)),
      }));
  }, [idx]);

  const trendable = useMemo(
    () =>
      idx
        ? idx.data.parameters
            .filter((p) => (p.numeric_count || 0) >= 3)
            .sort((a, b) => (b.numeric_count || 0) - (a.numeric_count || 0))
        : [],
    [idx]
  );

  // panels available in this dataset (with member counts)
  const panels = useMemo(() => {
    if (!idx) return [] as Array<{ panel: Panel; members: string[]; attention: number }>;
    return PANELS.map((panel) => {
      const members = panelMembers(idx, panel);
      const attention = attentionParams(idx, members).length;
      return { panel, members, attention };
    }).filter((p) => p.members.length > 0);
  }, [idx]);

  // attention across ALL parameters (latest reading out of range)
  const attention = useMemo(() => {
    if (!idx) return [] as { name: string; flag: Flag }[];
    return attentionParams(idx, idx.data.parameters.map((p) => p.parameter));
  }, [idx]);

  // visible cards = trendable, narrowed by active panel + range filter
  const visibleCards = useMemo(() => {
    if (!idx) return [] as ParamCatalog[];
    let list = trendable;
    if (activePanel) {
      const panel = PANELS.find((p) => p.key === activePanel);
      if (panel) {
        const set = new Set(panelMembers(idx, panel));
        // include ALL panel members (even <3 pts) when a panel is active
        list = panel.members
          .filter((m) => idx.catalog[m] && set.has(m))
          .map((m) => idx.catalog[m]);
      }
    }
    if (rangeFilter !== "all") {
      list = list.filter((p) => {
        const lf = latestFlag(idx, p.parameter);
        return passesFilter(lf?.flag ?? null, rangeFilter);
      });
    }
    return list;
  }, [idx, trendable, activePanel, rangeFilter]);

  const tableRows = useMemo(() => {
    if (!idx) return [];
    let rows: Measurement[] = [];
    for (const n of selected) {
      rows = rows.concat(
        (idx.byParam[n] || []).filter((m) => {
          if (dateFrom && m.date < dateFrom) return false;
          if (dateTo && m.date > dateTo) return false;
          return true;
        })
      );
    }
    const k = sortKey;
    rows.sort((a, b) => {
      let va: string | number = (a as never)[k] ?? "";
      let vb: string | number = (b as never)[k] ?? "";
      if (k === "value") { va = a.value ?? -Infinity; vb = b.value ?? -Infinity; }
      if (k === "sources") { va = (a.sources || []).join(","); vb = (b.sources || []).join(","); }
      if (va < vb) return -1 * sortDir;
      if (va > vb) return 1 * sortDir;
      return 0;
    });
    return rows;
  }, [idx, selected, dateFrom, dateTo, sortKey, sortDir]);

  // ---- actions ----
  const toggleParam = (name: string, additive = true) => {
    setSelected((prev) => {
      const i = prev.indexOf(name);
      if (i >= 0) return prev.filter((x) => x !== name);
      return additive ? [...prev, name] : [name];
    });
  };
  const openParam = (name: string) => { setSelected([name]); setQuery(""); setOpen(false); };
  const compareSet = (names: string[]) => { if (names.length) setSelected(names.slice(0, 8)); };

  const sortBy = (k: SortKey) => {
    if (sortKey === k) setSortDir((d) => -d);
    else { setSortKey(k); setSortDir(k === "date" ? -1 : 1); }
  };

  const exportCSV = () => {
    const cols = ["date", "parameter", "value", "value_text", "unit", "ref_low", "ref_high", "ref_text", "flag", "lab", "sources"] as const;
    const lines = [cols.join(",")];
    for (const m of tableRows) {
      lines.push(
        cols
          .map((c) => {
            let v: unknown = c === "sources" ? (m.sources || []).join("; ") : (m as never)[c];
            if (v == null) v = "";
            let str = String(v);
            if (/[",\n]/.test(str)) str = '"' + str.replace(/"/g, '""') + '"';
            return str;
          })
          .join(",")
      );
    }
    const blob = new Blob([lines.join("\n")], { type: "text/csv" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = (selected.join("_").replace(/[^\w]+/g, "-") || "health") + ".csv";
    a.click();
    URL.revokeObjectURL(a.href);
  };

  // ---- file-pick fallback ----
  if (needPick) {
    return (
      <div className="min-h-screen grid place-items-center p-6">
        <Card className="max-w-md w-full">
          <CardContent className="pt-6 space-y-3">
            <div className="flex items-center gap-2 text-lg font-semibold">
              <Activity className="size-5" /> Health Trends Explorer
            </div>
            <p className="text-sm text-muted-foreground">
              Couldn't auto-load <code className="font-mono text-xs">health_data.json</code>. Pick the file to continue.
            </p>
            <Input type="file" accept="application/json,.json" onChange={(e) => e.target.files?.[0] && onFile(e.target.files[0])} />
          </CardContent>
        </Card>
      </div>
    );
  }

  if (!idx) {
    return (
      <div className="min-h-screen grid place-items-center text-muted-foreground">
        <div className="flex items-center gap-2 animate-pulse"><Activity className="size-4" /> Loading lab history…</div>
      </div>
    );
  }

  const s = idx.data.summary;
  const inChart = selected.length > 0;

  return (
    <div className="min-h-screen">
      {/* ===== Header ===== */}
      <header className="sticky top-0 z-30 border-b bg-background/80 backdrop-blur-xl">
        <div className="px-5 lg:px-8 h-16 flex items-center gap-4">
          {/* Brand */}
          <div className="flex items-center gap-3 shrink-0">
            <div className="grid place-items-center size-9 rounded-xl bg-primary text-primary-foreground shadow-sm">
              <Activity className="size-5" />
            </div>
            <div className="leading-none">
              <div className="font-semibold tracking-tight text-[15px]">{idx.data.patient}</div>
              <div className="text-xs text-muted-foreground mt-1">Diagnostic lab history</div>
            </div>
          </div>

          {/* Stats — quiet, inline, pipe-separated */}
          <div className="hidden lg:flex items-center gap-2 text-xs text-muted-foreground/90 pl-4 ml-1 border-l">
            <Stat label="measurements" value={s.total_measurements.toLocaleString()} />
            <Stat label="parameters" value={String(s.unique_parameters)} />
            <Stat label="years" value={`${s.date_range[0].slice(0, 4)}–${s.date_range[1].slice(0, 4)}`} />
          </div>

          <div className="ml-auto flex items-center gap-2 flex-1 justify-end max-w-[480px]">
            {/* Search */}
            <div ref={searchRef} className="relative flex-1 min-w-0">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-muted-foreground pointer-events-none" />
                <Input
                  value={query}
                  onChange={(e) => { setQuery(e.target.value); setOpen(true); setHi(-1); }}
                  onFocus={() => query && setOpen(true)}
                  onKeyDown={(e) => {
                    const list = results.slice(0, 40);
                    if (e.key === "ArrowDown") { e.preventDefault(); setHi((h) => Math.min(h + 1, list.length - 1)); }
                    else if (e.key === "ArrowUp") { e.preventDefault(); setHi((h) => Math.max(h - 1, 0)); }
                    else if (e.key === "Enter") { const p = list[hi] || list[0]; if (p) openParam(p.parameter); }
                    else if (e.key === "Escape") setOpen(false);
                  }}
                  placeholder="Search — try d3, a1c, sugar, b12, tsh…"
                  className="pl-9 h-9 bg-secondary/60 border-transparent focus-visible:bg-background focus-visible:border-input"
                />
                {open && query && (
                  <div className="absolute top-[calc(100%+6px)] left-0 right-0 rounded-lg border bg-popover shadow-lg overflow-hidden z-50 animate-fade-in">
                    <div className="max-h-[360px] overflow-auto scrollbar-thin py-1">
                      {results.length === 0 && (
                        <div className="px-3 py-6 text-center text-sm text-muted-foreground">No matches</div>
                      )}
                      {results.slice(0, 40).map((p, i) => {
                        const lf = latestFlag(idx, p.parameter);
                        return (
                          <button
                            key={p.parameter}
                            onMouseEnter={() => setHi(i)}
                            onClick={() => openParam(p.parameter)}
                            className={cn(
                              "w-full flex items-center justify-between gap-3 px-3 py-2 text-left text-sm",
                              i === hi ? "bg-accent" : "hover:bg-accent/60"
                            )}
                          >
                            <span className="flex items-center gap-2 min-w-0">
                              {lf?.flag && lf.flag !== "Normal" && (
                                <span className="size-1.5 rounded-full shrink-0" style={{ background: FLAG_HSL[lf.flag] }} />
                              )}
                              <span className="font-medium truncate">{p.parameter}</span>
                              <Badge variant="secondary" className="font-normal text-[10px] py-0">{p.category}</Badge>
                            </span>
                            <span className="text-xs text-muted-foreground whitespace-nowrap">
                              {p.numeric_count} pts · {p.latest_value_text ?? "–"} {p.unit}
                            </span>
                          </button>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>

              <InstallButton />

              <Button variant="ghost" size="icon" onClick={() => setDark((d) => !d)} title="Toggle theme">
                {dark ? <Sun className="size-4" /> : <Moon className="size-4" />}
              </Button>
          </div>
        </div>
      </header>

      {/* ===== Body ===== */}
      <div className="flex">
        {/* Sidebar */}
        <aside className="hidden lg:flex flex-col w-[260px] shrink-0 border-r h-[calc(100vh-65px)] sticky top-[65px] overflow-auto scrollbar-thin py-3">
          <button
            onClick={() => setActiveCat(null)}
            className={cn(
              "mx-2 px-3 py-2 rounded-md text-sm flex items-center justify-between transition-colors",
              activeCat === null ? "bg-accent font-medium" : "hover:bg-accent/60"
            )}
          >
            <span className="flex items-center gap-2"><Layers className="size-4" /> All parameters</span>
            <span className="text-xs text-muted-foreground">{idx.data.parameters.length}</span>
          </button>

          <div className="mt-1">
            {catGroups.map(({ cat, params }) => {
              const isOpen = activeCat === cat;
              return (
                <div key={cat}>
                  <button
                    onClick={() => setActiveCat(isOpen ? null : cat)}
                    className={cn(
                      "w-full px-5 py-2 text-sm flex items-center justify-between transition-colors",
                      isOpen ? "text-foreground font-medium" : "text-foreground/80 hover:bg-accent/50"
                    )}
                  >
                    <span className="flex items-center gap-1.5">
                      <ChevronRight className={cn("size-3.5 transition-transform text-muted-foreground", isOpen && "rotate-90")} />
                      {cat}
                    </span>
                    <span className="text-xs text-muted-foreground">{params.length}</span>
                  </button>
                  {isOpen && (
                    <div className="pb-1">
                      {params.map((p) => {
                        const sel = selected.includes(p.parameter);
                        const lf = latestFlag(idx, p.parameter);
                        return (
                          <button
                            key={p.parameter}
                            onClick={() => toggleParam(p.parameter)}
                            title={p.parameter}
                            className={cn(
                              "w-full pl-9 pr-3 py-1.5 flex items-center gap-2 text-[13px] transition-colors",
                              sel ? "bg-accent font-medium" : "hover:bg-accent/50"
                            )}
                          >
                            <span className="shrink-0 opacity-70"><Sparkline rows={idx.byParam[p.parameter] || []} w={40} h={14} /></span>
                            <span className="flex-1 truncate text-left">{p.parameter}</span>
                            {lf?.flag && lf.flag !== "Normal" && (
                              <span className="size-1.5 rounded-full shrink-0" style={{ background: FLAG_HSL[lf.flag] }} />
                            )}
                            <span className="text-[11px] text-muted-foreground whitespace-nowrap">{p.latest_value_text ?? "–"}</span>
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </aside>

        {/* Main */}
        <main className="flex-1 min-w-0 px-5 lg:px-8 py-6">
          {!inChart ? (
            <Dashboard
              idx={idx}
              panels={panels}
              attention={attention}
              activePanel={activePanel}
              setActivePanel={setActivePanel}
              rangeFilter={rangeFilter}
              setRangeFilter={setRangeFilter}
              cards={visibleCards}
              onOpen={openParam}
              onCompare={compareSet}
            />
          ) : (
            <ChartView
              idx={idx}
              selected={selected}
              dark={dark}
              dateFrom={dateFrom}
              dateTo={dateTo}
              normalize={normalize}
              setDateFrom={setDateFrom}
              setDateTo={setDateTo}
              setNormalize={setNormalize}
              tableRows={tableRows}
              sortKey={sortKey}
              sortDir={sortDir}
              sortBy={sortBy}
              onBack={() => setSelected([])}
              onRemove={(n) => toggleParam(n)}
              onExport={exportCSV}
            />
          )}
        </main>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <span className="inline-flex items-baseline gap-1.5 rounded-md px-2 py-1 hover:bg-accent/50 transition-colors">
      <span className="font-semibold text-[13px] text-foreground tabular-nums">{value}</span>
      <span className="text-[11px] text-muted-foreground">{label}</span>
    </span>
  );
}

// ===== Dashboard =====
interface DashboardProps {
  idx: Indexed;
  panels: Array<{ panel: Panel; members: string[]; attention: number }>;
  attention: { name: string; flag: Flag }[];
  activePanel: string | null;
  setActivePanel: (k: string | null) => void;
  rangeFilter: RangeFilter;
  setRangeFilter: (f: RangeFilter) => void;
  cards: ParamCatalog[];
  onOpen: (n: string) => void;
  onCompare: (names: string[]) => void;
}

function Dashboard(p: DashboardProps) {
  const { idx, attention } = p;
  const highCount = attention.filter((a) => a.flag === "High").length;
  const lowCount = attention.filter((a) => a.flag === "Low").length;
  const activePanelObj = p.activePanel ? PANELS.find((x) => x.key === p.activePanel) : null;

  const filters: Array<{ k: RangeFilter; label: string }> = [
    { k: "all", label: "All" },
    { k: "out", label: "Out of range" },
    { k: "high", label: "High" },
    { k: "low", label: "Low" },
  ];

  return (
    <div className="animate-fade-in space-y-5">
      {/* Attention banner */}
      {attention.length > 0 ? (
        <button
          onClick={() => { p.setRangeFilter("out"); p.setActivePanel(null); }}
          className="group w-full text-left rounded-2xl border border-high/25 bg-gradient-to-br from-high/[0.07] to-high/[0.02] hover:border-high/40 transition-colors p-4 sm:p-5"
        >
          <div className="flex items-center gap-4">
            <div className="grid place-items-center size-11 rounded-xl bg-high/12 text-high shrink-0 ring-1 ring-high/15">
              <AlertTriangle className="size-[22px]" strokeWidth={2.2} />
            </div>

            <div className="min-w-0 flex-1">
              <div className="flex items-baseline gap-2 flex-wrap">
                <span className="text-[17px] font-semibold tracking-tight leading-none">
                  {attention.length} need attention
                </span>
                <span className="text-xs text-muted-foreground leading-none">latest reading per test</span>
              </div>
              <div className="flex items-center gap-2.5 mt-2 text-[13px]">
                <span className="inline-flex items-center gap-1.5 font-medium text-high">
                  <TrendingUp className="size-4" strokeWidth={2.4} /> {highCount} high
                </span>
                <span className="text-border">·</span>
                <span className="inline-flex items-center gap-1.5 font-medium text-low">
                  <TrendingDown className="size-4" strokeWidth={2.4} /> {lowCount} low
                </span>
              </div>
            </div>

            <span className="hidden sm:inline-flex items-center gap-1.5 text-sm font-medium text-foreground/70 group-hover:text-foreground transition-colors shrink-0">
              Review
              <ChevronRight className="size-4 group-hover:translate-x-0.5 transition-transform" />
            </span>
          </div>

          {/* chips — single clean row, fade-masked, uniform style */}
          <div className="relative mt-3.5 pt-3.5 border-t border-high/15">
            <div className="flex items-center gap-1.5 overflow-hidden [mask-image:linear-gradient(to_right,black_82%,transparent)]">
              {attention.slice(0, 9).map((a) => (
                <span
                  key={a.name}
                  className="inline-flex items-center gap-1.5 shrink-0 rounded-full border border-border/70 bg-background/60 pl-2 pr-2.5 py-1 text-xs font-medium whitespace-nowrap"
                >
                  <span className="size-1.5 rounded-full" style={{ background: FLAG_HSL[a.flag || "High"] }} />
                  {a.name}
                </span>
              ))}
            </div>
            {attention.length > 9 && (
              <span className="absolute right-0 top-3.5 inline-flex items-center rounded-full bg-high/12 text-high px-2.5 py-1 text-xs font-semibold">
                +{attention.length - 9}
              </span>
            )}
          </div>
        </button>
      ) : (
        <div className="rounded-2xl border border-normal/30 bg-normal/[0.06] p-4 sm:p-5 flex items-center gap-3">
          <div className="grid place-items-center size-10 rounded-xl bg-normal/12 text-normal shrink-0">
            <CheckCircle2 className="size-5" />
          </div>
          <div>
            <div className="font-semibold tracking-tight">All clear</div>
            <div className="text-sm text-muted-foreground">Every latest reading is within its reference range.</div>
          </div>
        </div>
      )}

      {/* Panels rail */}
      <div>
        <div className="flex items-center gap-2 mb-2">
          <h3 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">Panels</h3>
        </div>
        <div className="flex gap-2.5 overflow-x-auto scrollbar-thin pb-1 -mx-1 px-1">
          {p.panels.map(({ panel, members, attention: att }) => {
            const active = p.activePanel === panel.key;
            return (
              <button
                key={panel.key}
                onClick={() => p.setActivePanel(active ? null : panel.key)}
                className={cn(
                  "shrink-0 w-[170px] text-left rounded-xl border p-3 transition-all",
                  active ? "border-foreground/40 bg-accent shadow-sm" : "hover:border-foreground/20 hover:bg-accent/40"
                )}
              >
                <div className="flex items-center justify-between">
                  <span className="font-semibold text-sm">{panel.short}</span>
                  {att > 0 ? (
                    <Badge variant="high" className="text-[10px] px-1.5">{att}</Badge>
                  ) : (
                    <CheckCircle2 className="size-3.5 text-normal" />
                  )}
                </div>
                <div className="text-[11px] text-muted-foreground leading-tight mt-1 line-clamp-2">{panel.desc}</div>
                <div className="text-[11px] text-muted-foreground/70 mt-1.5">{members.length} tests</div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Controls row */}
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2 flex-wrap">
          <h2 className="text-lg font-semibold tracking-tight">
            {activePanelObj ? activePanelObj.name : "Latest snapshot"}
          </h2>
          {activePanelObj && (
            <Button variant="ghost" size="xs" onClick={() => p.setActivePanel(null)}>
              <X className="size-3" /> Clear panel
            </Button>
          )}
          {activePanelObj && p.cards.length > 1 && (
            <Button variant="outline" size="xs" onClick={() => p.onCompare(p.cards.map((c) => c.parameter))}>
              <LineChart className="size-3" /> Compare all
            </Button>
          )}
        </div>

        {/* segmented range filter */}
        <div className="inline-flex items-center rounded-lg border bg-secondary/40 p-0.5 text-xs">
          {filters.map((f) => (
            <button
              key={f.k}
              onClick={() => p.setRangeFilter(f.k)}
              className={cn(
                "px-2.5 py-1 rounded-md transition-colors font-medium",
                p.rangeFilter === f.k ? "bg-background shadow-sm text-foreground" : "text-muted-foreground hover:text-foreground"
              )}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      <p className="text-sm text-muted-foreground -mt-2">
        {p.cards.length} {p.rangeFilter === "all" ? "" : p.rangeFilter === "out" ? "out-of-range " : p.rangeFilter + " "}
        parameter{p.cards.length === 1 ? "" : "s"} · click a card to open its trend
      </p>

      {/* Cards */}
      {p.cards.length === 0 ? (
        <div className="text-center py-16 text-muted-foreground">
          <CheckCircle2 className="size-8 mx-auto mb-2 text-normal" />
          Nothing matches this filter.
        </div>
      ) : (
        <div className="grid gap-3 grid-cols-[repeat(auto-fill,minmax(210px,1fr))]">
          {p.cards.map((cat) => {
            const rows = idx.byParam[cat.parameter] || [];
            const lf = latestFlag(idx, cat.parameter);
            const flag = lf?.flag ?? null;
            const val = cat.latest_value != null ? fmt(cat.latest_value) : cat.latest_value_text ?? "–";
            return (
              <Card
                key={cat.parameter}
                onClick={() => p.onOpen(cat.parameter)}
                className={cn(
                  "group cursor-pointer transition-all hover:shadow-md hover:-translate-y-0.5",
                  flag === "High" || flag === "Low" ? "border-l-2" : "hover:border-foreground/20"
                )}
                style={flag === "High" || flag === "Low" ? { borderLeftColor: FLAG_HSL[flag] } : undefined}
              >
                <CardContent className="p-3.5">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="font-medium text-sm leading-tight truncate">{cat.parameter}</div>
                      <div className="text-[11px] text-muted-foreground">{cat.category}</div>
                    </div>
                    {flag && (
                      <Badge variant={flag.toLowerCase() as "high" | "low" | "normal"} className="shrink-0 text-[10px]">{flag}</Badge>
                    )}
                  </div>
                  <div className="flex items-baseline gap-1.5 mt-2.5">
                    <span className="text-2xl font-semibold tracking-tight tabular-nums">{val}</span>
                    <span className="text-xs text-muted-foreground">{cat.unit}</span>
                  </div>
                  <div className="mt-1.5 -mx-0.5">
                    <Sparkline rows={rows} w={184} h={32} />
                  </div>
                  <div className="flex justify-between text-[11px] text-muted-foreground mt-1.5">
                    <span>{cat.numeric_count} pts</span>
                    <span>{cat.last_date}</span>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ===== Chart View =====
interface ChartViewProps {
  idx: Indexed;
  selected: string[];
  dark: boolean;
  dateFrom: string | null;
  dateTo: string | null;
  normalize: boolean;
  setDateFrom: (v: string | null) => void;
  setDateTo: (v: string | null) => void;
  setNormalize: (v: boolean) => void;
  tableRows: Measurement[];
  sortKey: SortKey;
  sortDir: number;
  sortBy: (k: SortKey) => void;
  onBack: () => void;
  onRemove: (n: string) => void;
  onExport: () => void;
}

function ChartView(p: ChartViewProps) {
  const { idx, selected } = p;
  const title = selected.length === 1 ? selected[0] : `${selected.length} parameters compared`;
  const single = selected.length === 1;
  const cat = single ? idx.catalog[selected[0]] : null;
  const ref = single ? refFor(idx, selected[0]) : null;

  const cols: Array<[SortKey, string, boolean?]> = [
    ["date", "Date"], ["parameter", "Parameter"], ["value", "Value", true],
    ["unit", "Unit"], ["ref_text", "Ref range"], ["flag", "Flag"], ["lab", "Lab"], ["sources", "Source"],
  ];

  return (
    <div className="animate-fade-in space-y-5">
      {/* Chart card */}
      <Card>
        <CardContent className="p-5">
          <div className="flex items-start justify-between gap-3 flex-wrap">
            <div className="min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <h2 className="text-lg font-semibold tracking-tight">{title}</h2>
                {single && cat && <Badge variant="secondary" className="font-normal">{cat.category}</Badge>}
              </div>
              {single && (ref?.lo != null || ref?.hi != null) && (
                <p className="text-xs text-muted-foreground mt-0.5">
                  Reference {ref?.lo ?? "–"} – {ref?.hi ?? "–"} {cat?.unit}
                </p>
              )}
              <div className="flex flex-wrap gap-1.5 mt-2.5">
                {selected.map((n, i) => (
                  <span key={n} className="inline-flex items-center gap-1.5 pl-2 pr-1 py-0.5 rounded-full border bg-secondary/60 text-xs">
                    <span className="size-2 rounded-full" style={{ background: SERIES_COLORS[i % SERIES_COLORS.length] }} />
                    {n}
                    <button onClick={() => p.onRemove(n)} className="rounded-full hover:bg-muted-foreground/20 p-0.5">
                      <X className="size-3" />
                    </button>
                  </span>
                ))}
              </div>
            </div>
            <Button variant="outline" size="sm" onClick={p.onBack}>
              <ArrowLeft className="size-4" /> Dashboard
            </Button>
          </div>

          {/* controls */}
          <div className="flex items-center gap-3 flex-wrap mt-4 text-sm">
            <label className="flex items-center gap-1.5 text-muted-foreground">
              <CalendarDays className="size-4" />
              <input type="date" value={p.dateFrom ?? ""} onChange={(e) => p.setDateFrom(e.target.value || null)}
                className="h-8 rounded-md border bg-transparent px-2 text-xs" />
              <span>→</span>
              <input type="date" value={p.dateTo ?? ""} onChange={(e) => p.setDateTo(e.target.value || null)}
                className="h-8 rounded-md border bg-transparent px-2 text-xs" />
            </label>
            <Button variant="ghost" size="xs" onClick={() => { p.setDateFrom(null); p.setDateTo(null); }}>
              <RotateCcw className="size-3" /> Reset
            </Button>
            <label className="flex items-center gap-1.5 text-xs text-muted-foreground ml-auto cursor-pointer select-none">
              <input type="checkbox" checked={p.normalize} onChange={(e) => p.setNormalize(e.target.checked)} className="accent-foreground" />
              Normalize to % of reference (mixed units)
            </label>
          </div>

          <div className="relative h-[400px] mt-4">
            <TrendChart idx={idx} selected={selected} dateFrom={p.dateFrom} dateTo={p.dateTo} normalize={p.normalize} dark={p.dark} />
          </div>
        </CardContent>
      </Card>

      {/* Table card */}
      <Card>
        <CardContent className="p-5">
          <div className="flex items-center justify-between gap-3 flex-wrap mb-3">
            <h3 className="font-semibold">Data table <span className="text-muted-foreground font-normal text-sm">· {p.tableRows.length} rows</span></h3>
            <Button variant="outline" size="sm" onClick={p.onExport}><Download className="size-4" /> Export CSV</Button>
          </div>
          <div className="max-h-[440px] overflow-auto scrollbar-thin rounded-md border">
            <table className="w-full text-[13px] border-collapse">
              <thead className="sticky top-0 bg-card z-10">
                <tr className="border-b">
                  {cols.map(([k, label, num]) => (
                    <th key={k} onClick={() => p.sortBy(k)}
                      className={cn("text-muted-foreground font-medium px-3 py-2 cursor-pointer select-none whitespace-nowrap hover:text-foreground text-left", num && "text-right")}>
                      {label}
                      {p.sortKey === k && <span className="ml-1 text-[10px]">{p.sortDir > 0 ? "▲" : "▼"}</span>}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {p.tableRows.map((m, i) => {
                  const f = flagFor(m);
                  const val = m.value != null ? fmt(m.value) : m.value_text ?? "";
                  return (
                    <tr key={i} className="border-b last:border-0 hover:bg-accent/40">
                      <td className="px-3 py-1.5 whitespace-nowrap tabular-nums">{m.date}</td>
                      <td className="px-3 py-1.5 whitespace-nowrap">{m.parameter}</td>
                      <td className="px-3 py-1.5 text-right tabular-nums whitespace-nowrap">{val}</td>
                      <td className="px-3 py-1.5 text-muted-foreground whitespace-nowrap">{m.unit}</td>
                      <td className="px-3 py-1.5 text-muted-foreground whitespace-nowrap">{m.ref_text}</td>
                      <td className="px-3 py-1.5 whitespace-nowrap">
                        {f ? (
                          <span className="inline-flex items-center gap-1.5">
                            <span className="size-2 rounded-full" style={{ background: FLAG_HSL[f] }} />{f}
                          </span>
                        ) : <span className="text-muted-foreground">—</span>}
                      </td>
                      <td className="px-3 py-1.5 text-muted-foreground whitespace-nowrap">{m.lab || "—"}</td>
                      <td className="px-3 py-1.5 text-muted-foreground max-w-[260px] truncate" title={(m.sources || []).join(", ")}>
                        {(m.sources || []).join(", ") || "—"}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
