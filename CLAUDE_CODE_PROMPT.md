# Claude Code prompt — Health Trends Explorer

Copy everything in the block below into Claude Code, run from the `pepe-health` folder
(so `health_data.json` and `SCHEMA.md` are alongside it).

---

Build a **single self-contained `index.html`** (all HTML, CSS, JS inline — no build step, no npm) that is an interactive explorer for my diagnostic lab history. The data is in `health_data.json` in the same folder. Read `SCHEMA.md` first for the exact field definitions, then build to this spec.

## Data loading
- Load `health_data.json` via `fetch('./health_data.json')` on page load. Because some browsers block `fetch` of local files over `file://`, ALSO support a fallback: if `fetch` fails, show a small "Load health_data.json" file picker (`<input type=file>`) that reads the same JSON. The page must work by simply double-clicking the file OR via a local server.
- The JSON has `parameters` (catalog) and `measurements` (rows). Plot from `measurements`.

## Core feature — search a parameter, see its trend across years
1. A prominent **search box** at the top. As I type, show matching parameters. Matching must be fuzzy/alias-aware so that:
   - `d3` or `vit d` → `Vitamin D (25-OH)`
   - `a1c` or `hba1c` → `HbA1c`
   - `sugar` or `glucose` → all three glucose params (Fasting / PP / Random)
   - `b12` → `Vitamin B12`, `chol` → cholesterol params, `tsh` → `TSH`
   Match against `parameter`, `parameter_raw`, and a small built-in alias map; case-insensitive substring is the baseline, plus the alias map for common shorthand.
2. Selecting a parameter draws a **line chart of value vs date** using all its numeric measurements, sorted by date, x-axis = real time scale (years), so spacing reflects actual gaps between tests.
3. **Reference range band**: shade the `ref_low`→`ref_high` region behind the line (use the catalog entry's ref bounds, falling back to the most common ref on the rows). Points outside range get colored markers: red = High, blue = Low, green = Normal (use `flag`; if `flag` is null, derive from ref bounds).
4. **Multi-select / overlay**: let me add several parameters to the same chart to compare (e.g. HbA1c + Fasting Glucose). When units differ, use a secondary y-axis or normalize to % of reference — your call, but make it readable. Each series in its own color with a legend.
5. Hovering a point shows a tooltip: date, value + unit, flag, lab, and source file name.

## Supporting UI
- **Category filter / sidebar**: group the parameter list by `category` (Diabetes, Lipids, CBC, Kidney, Liver, Thyroid, Vitamins, Minerals, Electrolytes, Inflammation, Urine, Other). Clicking a category filters the searchable list. Show each parameter's point count and last value as a sparkline-ish hint if easy.
- **Date-range control**: let me restrict the chart to a window (e.g. last 5 years) with a slider or two date inputs.
- **Data table view**: below the chart, a sortable table of the currently selected parameter(s): date, value, unit, ref range, flag, lab, source. Clicking a column sorts. Include a "Copy/Export CSV" button for the current view.
- **Latest snapshot dashboard** (landing state before any search): a grid of cards, one per trendable parameter (catalog `numeric_count >= 3`), showing the latest value, its flag color, and a tiny inline sparkline of the full history. Clicking a card opens its full trend. Default sort: most-measured parameters first.

## Look & feel
- Clean, clinical, readable. Light theme, system font stack, responsive (works on a laptop and a phone). Use **Chart.js from CDN** (`https://cdn.jsdelivr.net/npm/chart.js`) and its time-scale adapter (`chartjs-adapter-date-fns`); everything else hand-rolled, no frameworks.
- Header shows patient name, total measurements, parameter count, and date range from `summary`.
- Flag colors consistent everywhere: High=#e23 / Low=#37c / Normal=#2a8.

## Robustness
- Handle parameters with non-numeric rows (`value: null`) — skip them in the line but list them in the table.
- Never crash on missing `ref_low`/`ref_high`/`lab`/`flag`.
- All ~159 parameters should be reachable via search even though only ~80 are trendable; for a parameter with <2 points, show the value(s) as labeled dots, not a line.

## Deliverable
One file: `index.html`. After building, start a quick local server (`python3 -m http.server`) and verify: the dashboard renders, searching "d3" charts Vitamin D, searching "a1c" charts HbA1c with a reference band, overlay of two params works, the table exports CSV, and it also opens correctly via the file-picker fallback. Fix anything that doesn't.

---

### Optional follow-ups you can ask Claude Code afterwards
- "Add a moving-average / trend line and a slope indicator (improving vs worsening) per parameter."
- "Add a printable PDF summary of all out-of-range latest values."
- "Group glucose + HbA1c into a 'Diabetes control' combined view with target zones."
- "Re-run extraction on new reports and append to health_data.json" (point it back at `SCHEMA.md`).
