# Health Data Schema — `health_data.json`

Patient: **Anoop Prakash Sharma** · 1,536 measurements · 159 parameters · 2001–2026
Built from ~80 diagnostic reports in the "Anoop Diagnostic Reports" Google Drive folder.

## Top-level shape

```json
{
  "patient": "Anoop Prakash Sharma",
  "generated": "2026-06-11T10:55:00",
  "source_folder": "Anoop Diagnostic Reports (Google Drive)",
  "summary": {
    "total_measurements": 1536,
    "unique_parameters": 159,
    "date_range": ["2001-05-02", "2026-05-10"],
    "categories": ["CBC","Diabetes","Electrolytes","Inflammation","Kidney","Lipids","Liver","Minerals","Other","Thyroid","Urine","Vitamins"]
  },
  "parameters": [ ParameterCatalogEntry, ... ],
  "measurements": [ Measurement, ... ]
}
```

## `Measurement` (the rows you plot)

```json
{
  "date": "2024-07-01",            // ISO YYYY-MM-DD — the x-axis value
  "parameter": "HbA1c",            // CANONICAL name — group/search on this
  "parameter_raw": "Glycosylated Haemoglobin (HbA1c)", // as printed in the report
  "category": "Diabetes",          // one of summary.categories
  "value": 6.7,                    // numeric (null if result is non-numeric)
  "value_text": "6.7",             // raw printed value; holds text like "Negative","Trace" when value is null
  "unit": "%",                     // normalized unit (see notes)
  "ref_low": 4.0,                  // numeric low bound of normal range (nullable)
  "ref_high": 5.6,                 // numeric high bound of normal range (nullable)
  "ref_text": "4.0 - 5.6",         // raw reference range string
  "flag": "High",                  // "High" | "Low" | "Normal" | null
  "lab": "Tata 1mg",               // lab/provider if known (nullable)
  "sources": ["Anoop full body comprehensive blood test July 2024.pdf"] // source report file(s)
}
```

## `ParameterCatalogEntry` (drives the search list / dropdown)

```json
{
  "parameter": "HbA1c",
  "category": "Diabetes",
  "unit": "%",
  "count": 32,              // total rows
  "numeric_count": 32,      // rows with a numeric value (plottable points)
  "first_date": "2011-02-05",
  "last_date": "2026-05-10",
  "latest_value": 7.0,
  "latest_value_text": "7.0",
  "ref_low": 4.0,
  "ref_high": 5.6
}
```

## Normalization already applied (so trends are valid)

- **Units consolidated**: `mg/dl`, `mg/dL`, `mg%` → `mg/dL`; `ng/ml`/`ng/mL` → `ng/mL`; `uIU/ml`/`µIU/mL`/`mIU/L` → `µIU/mL`; etc. Every parameter now sits on **one scale**, so points across years are directly comparable.
- **Cell-count scale fixes**: WBC and Platelet counts reported in absolute cells, lakhs, or thousands were all converted to `10³/µL`; RBC to `10⁶/µL`.
- **Outlier guards**: physiologically impossible values (e.g. a misparsed Creatinine of 77) were dropped to `value: null` but the row is kept (searchable via `value_text`).
- **Dedup**: identical (date, parameter, value, unit) across duplicate report files collapsed into one row; the duplicate filenames are preserved in `sources`.

## Notes for building the UI

- **Search** on `parameter` (canonical) but also match `parameter_raw` and aliases so a user typing "D3" finds `Vitamin D (25-OH)`, "sugar" finds the glucose params, "a1c" finds `HbA1c`.
- **Trendable parameters**: 80 have ≥3 numeric points. Sort the catalog by `numeric_count` desc for the default list.
- **Reference band**: shade `ref_low`→`ref_high` behind the line; color points by `flag`.
- A few rows are non-numeric (`value: null`) — show them as markers/notes, don't break the line.
