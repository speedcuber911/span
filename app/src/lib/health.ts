// ---------- types ----------
export interface Measurement {
  date: string;
  parameter: string;
  parameter_raw: string;
  category: string;
  value: number | null;
  value_text: string;
  unit: string;
  ref_low: number | null;
  ref_high: number | null;
  ref_text: string;
  flag: "High" | "Low" | "Normal" | null;
  lab: string | null;
  sources: string[];
}

export interface ParamCatalog {
  parameter: string;
  category: string;
  unit: string;
  count: number;
  numeric_count: number;
  first_date: string;
  last_date: string;
  latest_value: number | null;
  latest_value_text: string | null;
  ref_low: number | null;
  ref_high: number | null;
}

export interface HealthData {
  patient: string;
  generated: string;
  source_folder: string;
  summary: {
    total_measurements: number;
    unique_parameters: number;
    date_range: [string, string];
    categories: string[];
  };
  parameters: ParamCatalog[];
  measurements: Measurement[];
}

export type Flag = "High" | "Low" | "Normal" | null;

// ---------- alias map ----------
export const ALIASES: Record<string, string[]> = {
  d3: ["vitamin d", "25-oh", "25 oh"], "vit d": ["vitamin d"], vitd: ["vitamin d"],
  a1c: ["hba1c", "glycosylated", "glycated"], hba1c: ["hba1c"],
  sugar: ["glucose"], glucose: ["glucose"], fbs: ["glucose fasting", "fasting"],
  ppbs: ["glucose pp", "post prandial", "glucose post"],
  b12: ["vitamin b12", "b-12", "cobalamin"], "b 12": ["vitamin b12"],
  chol: ["cholesterol"], cholesterol: ["cholesterol"], ldl: ["ldl"], hdl: ["hdl"],
  tg: ["triglyceride"], trig: ["triglyceride"],
  tsh: ["tsh", "thyroid stimulating"], t3: ["t3"], t4: ["t4"],
  hb: ["hemoglobin", "haemoglobin"], hgb: ["hemoglobin", "haemoglobin"],
  wbc: ["wbc", "leukocyte", "white"], rbc: ["rbc", "red"], plt: ["platelet"], platelet: ["platelet"],
  creat: ["creatinine"], urea: ["urea"], bun: ["urea nitrogen", "bun"], uric: ["uric acid"],
  sgpt: ["sgpt", "alt"], sgot: ["sgot", "ast"], alt: ["alt", "sgpt"], ast: ["ast", "sgot"],
  bili: ["bilirubin"],
  na: ["sodium"], k: ["potassium"], cl: ["chloride"], ca: ["calcium"], mg: ["magnesium"],
  phos: ["phosphor"],
  crp: ["c-reactive", "crp"], esr: ["esr", "sedimentation"], ferritin: ["ferritin"], iron: ["iron"],
  folate: ["folate", "folic"], psa: ["psa", "prostate"],
};

// ---------- index ----------
export interface Indexed {
  data: HealthData;
  catalog: Record<string, ParamCatalog>;
  byParam: Record<string, Measurement[]>;
}

export function indexData(data: HealthData): Indexed {
  const byParam: Record<string, Measurement[]> = {};
  for (const m of data.measurements) {
    (byParam[m.parameter] ||= []).push(m);
  }
  for (const k in byParam) {
    byParam[k].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
  }
  const catalog: Record<string, ParamCatalog> = {};
  for (const p of data.parameters) catalog[p.parameter] = p;
  return { data, catalog, byParam };
}

// ---------- flag derivation ----------
export function flagFor(m: Measurement): Flag {
  if (m.flag) return m.flag;
  if (m.value == null) return null;
  if (m.ref_high != null && m.value > m.ref_high) return "High";
  if (m.ref_low != null && m.value < m.ref_low) return "Low";
  if (m.ref_low != null || m.ref_high != null) return "Normal";
  return null;
}

// most-common ref bounds for a param (catalog first, then mode of rows)
export function refFor(idx: Indexed, name: string): { lo: number | null; hi: number | null } {
  const c = idx.catalog[name] || ({} as ParamCatalog);
  let lo = c.ref_low ?? null;
  let hi = c.ref_high ?? null;
  if (lo == null || hi == null) {
    const counts: Record<string, { n: number; lo: number | null; hi: number | null }> = {};
    for (const m of idx.byParam[name] || []) {
      if (m.ref_low != null || m.ref_high != null) {
        const key = `${m.ref_low}|${m.ref_high}`;
        (counts[key] ||= { n: 0, lo: m.ref_low, hi: m.ref_high }).n++;
      }
    }
    let best: { n: number; lo: number | null; hi: number | null } | null = null;
    for (const k in counts) if (!best || counts[k].n > best.n) best = counts[k];
    if (best) {
      if (lo == null) lo = best.lo;
      if (hi == null) hi = best.hi;
    }
  }
  return { lo, hi };
}

// ---------- search ----------
export function searchParams(idx: Indexed, query: string): ParamCatalog[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const aliasHits = ALIASES[q] || null;
  const scored: Array<[number, number, ParamCatalog]> = [];
  for (const p of idx.data.parameters) {
    const name = (p.parameter || "").toLowerCase();
    const raws = (idx.byParam[p.parameter] || []).map((m) => (m.parameter_raw || "").toLowerCase());
    let score = -1;
    if (name === q) score = 100;
    else if (name.startsWith(q)) score = 80;
    else if (name.includes(q)) score = 60;
    else if (raws.some((r) => r.includes(q))) score = 40;

    if (aliasHits) {
      for (const sub of aliasHits) {
        if (name.includes(sub) || raws.some((r) => r.includes(sub))) {
          score = Math.max(score, 55);
          break;
        }
      }
    }
    for (const key in ALIASES) {
      if (key.startsWith(q) || q.startsWith(key)) {
        for (const sub of ALIASES[key]) {
          if (name.includes(sub) || raws.some((r) => r.includes(sub))) {
            score = Math.max(score, 45);
            break;
          }
        }
      }
    }
    if (score >= 0) scored.push([score, p.numeric_count || 0, p]);
  }
  scored.sort((a, b) => b[0] - a[0] || b[1] - a[1]);
  return scored.map((s) => s[2]);
}

// ---------- format ----------
export function fmt(v: number | null | undefined): string {
  if (v == null) return "";
  if (Number.isInteger(v)) return String(v);
  return (Math.round(v * 1000) / 1000).toString();
}

export const FLAG_HSL: Record<string, string> = {
  High: "hsl(var(--high))",
  Low: "hsl(var(--low))",
  Normal: "hsl(var(--normal))",
};

export const SERIES_COLORS = [
  "#2563eb", "#ea580c", "#16a34a", "#9333ea",
  "#db2777", "#0891b2", "#ca8a04", "#475569",
];

// inline sparkline path data
export function sparkPath(
  rows: Measurement[],
  w: number,
  h: number
): { d: string; cx: number; cy: number; last: Measurement } | null {
  const nums = rows.filter((m) => m.value != null) as (Measurement & { value: number })[];
  if (nums.length < 2) return null;
  const xs = nums.map((m) => +new Date(m.date));
  const ys = nums.map((m) => m.value);
  const x0 = Math.min(...xs), x1 = Math.max(...xs);
  const y0 = Math.min(...ys), y1 = Math.max(...ys);
  const px = (v: number) => (x1 === x0 ? w / 2 : 2 + ((v - x0) / (x1 - x0)) * (w - 4));
  const py = (v: number) => (y1 === y0 ? h / 2 : h - 2 - ((v - y0) / (y1 - y0)) * (h - 4));
  let d = "";
  nums.forEach((_, i) => {
    d += (i ? "L" : "M") + px(xs[i]).toFixed(1) + " " + py(ys[i]).toFixed(1) + " ";
  });
  const li = nums.length - 1;
  return { d, cx: px(xs[li]), cy: py(ys[li]), last: nums[li] };
}
