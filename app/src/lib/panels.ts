import type { Indexed, Measurement, Flag } from "@/lib/health";
import { flagFor } from "@/lib/health";

export interface Panel {
  key: string;
  name: string;
  short: string;
  desc: string;
  // canonical parameter names that belong to this panel (matched against catalog)
  members: string[];
}

// Curated clinical panels. Member names use canonical `parameter` values from the
// dataset; only those that actually exist are shown. A param may appear in >1 panel.
export const PANELS: Panel[] = [
  {
    key: "lft", name: "Liver Function (LFT)", short: "LFT", desc: "Liver enzymes, bilirubin & proteins",
    members: [
      "SGPT (ALT)", "ALT", "SGOT (AST)", "AST", "AST/ALT Ratio",
      "Bilirubin Total", "Bilirubin Direct", "Bilirubin Indirect",
      "ALP", "Alkaline Phosphatase", "GGT",
      "Total Protein", "Albumin", "Globulin", "A/G Ratio",
    ],
  },
  {
    key: "kft", name: "Kidney Function (KFT)", short: "KFT", desc: "Renal markers & clearance",
    members: [
      "Creatinine", "Urea", "Blood Urea", "BUN", "BUN/Creatinine Ratio",
      "Uric Acid", "eGFR", "Urine Albumin", "Sodium", "Potassium",
    ],
  },
  {
    key: "lipid", name: "Lipid Profile", short: "Lipid", desc: "Cholesterol & cardiovascular risk",
    members: [
      "Cholesterol Total", "LDL Cholesterol", "HDL Cholesterol", "Triglycerides",
      "VLDL Cholesterol", "Non-HDL Cholesterol", "TC/HDL Ratio", "LDL/HDL Ratio",
      "APO-A1", "APO-B", "Apolipoprotein A1", "Apolipoprotein B", "Apo B / Apo A1 Ratio",
      "Lipoprotein (a)", "Lipoprotein(a)",
    ],
  },
  {
    key: "thyroid", name: "Thyroid Profile", short: "Thyroid", desc: "TSH, T3/T4 & antibodies",
    members: [
      "TSH", "T3", "T3 Total", "T4", "T4 Total", "FT3", "FT4",
      "Anti-TPO Antibody", "Anti-TG Antibody",
    ],
  },
  {
    key: "diabetes", name: "Diabetes Panel", short: "Diabetes", desc: "Glucose control & insulin",
    members: [
      "HbA1c", "Glucose Fasting", "Glucose PP", "Glucose Random",
      "Estimated Avg Glucose", "eAG", "Insulin Fasting", "HOMA-IR",
      "C-Peptide", "C-Peptide Fasting", "Fructosamine",
    ],
  },
  {
    key: "cbc", name: "Complete Blood Count", short: "CBC", desc: "Cells, hemoglobin & indices",
    members: [
      "Hemoglobin", "RBC Count", "WBC", "WBC Count", "Platelet Count",
      "Hematocrit", "Hematocrit (PCV)", "MCV", "MCH", "MCHC", "RDW", "RDW-SD", "MPV",
      "Neutrophils %", "Lymphocytes %", "Monocytes %", "Eosinophils %", "Basophils %",
      "ANC", "ALC", "AMC", "AEC", "ABC",
    ],
  },
  {
    key: "iron", name: "Iron Studies", short: "Iron", desc: "Iron stores & binding capacity",
    members: ["Iron", "Ferritin", "TIBC", "UIBC", "Transferrin Saturation"],
  },
  {
    key: "electrolytes", name: "Electrolytes", short: "Lytes", desc: "Sodium, potassium & balance",
    members: ["Sodium", "Potassium", "Chloride", "Bicarbonate", "Calcium", "Magnesium", "Phosphorus", "Phosphorous"],
  },
  {
    key: "vitamins", name: "Vitamins", short: "Vit", desc: "D, B12 & folate status",
    members: ["Vitamin D", "Vitamin D (25-OH)", "Vitamin B12", "Folate", "Folic Acid"],
  },
  {
    key: "inflammation", name: "Inflammation", short: "Inflam", desc: "CRP, ESR & autoimmune markers",
    members: ["CRP", "hsCRP", "ESR", "Anti Nuclear Antibodies", "Anti-CCP", "RA Factor", "ASO Titre"],
  },
];

// Resolve panel members that actually exist in the dataset.
export function panelMembers(idx: Indexed, panel: Panel) {
  return panel.members.filter((m) => idx.catalog[m]);
}

// latest numeric reading + its derived flag for a parameter
export function latestFlag(idx: Indexed, name: string): { m: Measurement; flag: Flag } | null {
  const rows = idx.byParam[name] || [];
  const lastNum = [...rows].reverse().find((x) => x.value != null);
  if (!lastNum) return null;
  return { m: lastNum, flag: flagFor(lastNum) };
}

export type RangeFilter = "all" | "out" | "high" | "low";

export function passesFilter(flag: Flag, f: RangeFilter): boolean {
  if (f === "all") return true;
  if (f === "out") return flag === "High" || flag === "Low";
  if (f === "high") return flag === "High";
  if (f === "low") return flag === "Low";
  return true;
}

// params whose LATEST reading is out of range (across trendable set caller decides)
export function attentionParams(idx: Indexed, names: string[]): { name: string; flag: Flag }[] {
  const out: { name: string; flag: Flag }[] = [];
  for (const name of names) {
    const lf = latestFlag(idx, name);
    if (lf && (lf.flag === "High" || lf.flag === "Low")) out.push({ name, flag: lf.flag });
  }
  return out;
}
