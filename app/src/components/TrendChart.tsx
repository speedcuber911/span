import { useMemo } from "react";
import { Line } from "react-chartjs-2";
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  TimeScale,
  Tooltip,
  Legend,
  Filler,
  type ChartOptions,
  type Plugin,
} from "chart.js";
import "chartjs-adapter-date-fns";
import {
  flagFor, refFor, FLAG_HSL, SERIES_COLORS, fmt,
  type Indexed, type Measurement,
} from "@/lib/health";

ChartJS.register(LineElement, PointElement, LinearScale, TimeScale, Tooltip, Legend, Filler);

interface Props {
  idx: Indexed;
  selected: string[];
  dateFrom: string | null;
  dateTo: string | null;
  normalize: boolean;
  dark: boolean;
}

export function TrendChart({ idx, selected, dateFrom, dateTo, normalize, dark }: Props) {
  const inRange = (name: string) =>
    (idx.byParam[name] || []).filter((m) => {
      if (dateFrom && m.date < dateFrom) return false;
      if (dateTo && m.date > dateTo) return false;
      return true;
    });

  const units = new Set(selected.map((n) => (idx.catalog[n] || {}).unit || ""));
  const mixedUnits = units.size > 1;
  const useNorm = normalize && mixedUnits;
  const single = selected.length === 1;

  const grid = dark ? "rgba(148,163,184,0.12)" : "rgba(15,23,42,0.06)";
  const tick = dark ? "rgba(226,232,240,0.7)" : "rgba(51,65,85,0.8)";

  const { datasets } = useMemo(() => {
    const ds = selected.map((name, i) => {
      const col = SERIES_COLORS[i % SERIES_COLORS.length];
      const rows = inRange(name).filter((m) => m.value != null) as (Measurement & { value: number })[];
      const ref = refFor(idx, name);
      const pts = rows.map((m) => ({
        x: m.date,
        y: useNorm && ref.hi ? (m.value / ref.hi) * 100 : m.value,
        raw: m,
      }));
      const ptColors = rows.map((m) => FLAG_HSL[flagFor(m) || ""] || col);
      return {
        label:
          name +
          (useNorm
            ? " (% of ref)"
            : (idx.catalog[name] || {}).unit
            ? ` (${(idx.catalog[name] || {}).unit})`
            : ""),
        data: pts,
        borderColor: col,
        backgroundColor: col + "20",
        pointBackgroundColor: ptColors,
        pointBorderColor: dark ? "#0b1220" : "#fff",
        pointBorderWidth: 1.5,
        pointRadius: rows.length < 2 ? 6 : 3.5,
        pointHoverRadius: 6,
        borderWidth: 2,
        tension: 0.25,
        spanGaps: true,
        fill: single && !useNorm,
        yAxisID: mixedUnits && !useNorm ? (i === 0 ? "y" : "y2") : "y",
        showLine: rows.length >= 2,
      };
    });
    return { datasets: ds };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected, dateFrom, dateTo, useNorm, mixedUnits, single, dark, idx]);

  // reference-band plugin (single param, not normalized)
  const bandPlugin = useMemo<Plugin<"line">>(() => {
    return {
      id: "refband",
      beforeDatasetsDraw(chart) {
        if (!single || useNorm) return;
        const ref = refFor(idx, selected[0]);
        if (ref.lo == null && ref.hi == null) return;
        const { ctx, chartArea, scales } = chart;
        const ys = scales.y as { getPixelForValue: (v: number) => number };
        if (!ys) return;
        const top = ref.hi != null ? ys.getPixelForValue(ref.hi) : chartArea.top;
        const bot = ref.lo != null ? ys.getPixelForValue(ref.lo) : chartArea.bottom;
        ctx.save();
        ctx.fillStyle = dark ? "rgba(45,212,160,0.10)" : "rgba(16,150,110,0.08)";
        ctx.fillRect(chartArea.left, Math.min(top, bot), chartArea.right - chartArea.left, Math.abs(bot - top));
        ctx.strokeStyle = dark ? "rgba(45,212,160,0.4)" : "rgba(16,150,110,0.35)";
        ctx.setLineDash([4, 4]);
        ctx.lineWidth = 1;
        if (ref.hi != null) { ctx.beginPath(); ctx.moveTo(chartArea.left, top); ctx.lineTo(chartArea.right, top); ctx.stroke(); }
        if (ref.lo != null) { ctx.beginPath(); ctx.moveTo(chartArea.left, bot); ctx.lineTo(chartArea.right, bot); ctx.stroke(); }
        ctx.restore();
      },
    };
  }, [single, useNorm, selected, idx, dark]);

  const options: ChartOptions<"line"> = useMemo(
    () => ({
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 300 },
      interaction: { mode: "nearest", intersect: false },
      plugins: {
        legend: {
          display: selected.length > 1,
          position: "top",
          labels: { usePointStyle: true, pointStyle: "circle", boxWidth: 7, color: tick, font: { size: 12 } },
        },
        tooltip: {
          backgroundColor: dark ? "#0b1220" : "#0f172a",
          padding: 10,
          cornerRadius: 8,
          titleFont: { size: 12, weight: "bold" },
          bodyFont: { size: 12 },
          displayColors: true,
          callbacks: {
            title: (it) => (it[0].raw as { raw: Measurement }).raw.date,
            label: (it) => {
              const m = (it.raw as { raw: Measurement }).raw;
              const f = flagFor(m);
              return ` ${m.parameter}: ${fmt(m.value)} ${m.unit || ""}${f ? `  [${f}]` : ""}`;
            },
            afterLabel: (it) => {
              const m = (it.raw as { raw: Measurement }).raw;
              return `lab: ${m.lab || "—"}\nsource: ${(m.sources || []).join(", ") || "—"}`;
            },
          },
        },
      },
      scales: {
        x: {
          type: "time",
          time: { unit: "year", tooltipFormat: "yyyy-MM-dd" },
          grid: { color: grid },
          border: { display: false },
          ticks: { color: tick, font: { size: 11 } },
        },
        y: {
          grid: { color: grid },
          border: { display: false },
          ticks: { color: tick, font: { size: 11 } },
          title: {
            display: single && !useNorm,
            text: (idx.catalog[selected[0]] || {}).unit || "",
            color: tick,
          },
        },
        ...(mixedUnits && !useNorm
          ? {
              y2: {
                position: "right" as const,
                grid: { drawOnChartArea: false },
                border: { display: false },
                ticks: { color: tick, font: { size: 11 } },
                title: { display: true, text: (idx.catalog[selected[1]] || {}).unit || "", color: tick },
              },
            }
          : {}),
      },
    }),
    [selected, single, useNorm, mixedUnits, grid, tick, dark, idx]
  );

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return <Line data={{ datasets } as any} options={options} plugins={[bandPlugin]} />;
}
