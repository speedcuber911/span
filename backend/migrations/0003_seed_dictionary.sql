-- =============================================================================
-- Project Span — Migration 0003: Canonical parameter dictionary + optimal bands
-- (conservative starter set; expand only after clinical review — §11 decision 4)
--
-- LOINC codes: only those confidently confirmed; else loinc_status='unmapped'.
-- Optimal bands: ONLY the well-cited set from §11 decision 4:
--   apoB <60 mg/dL, HbA1c <5.5%, ALT <20 U/L, uric acid <5.0 mg/dL,
--   omega-3 index ≥8%, vitamin D 40–60 ng/mL.
-- Lp(a): TWO separate params (mg/dL and nmol/L) — never convert (§11 decision 6).
-- Creatinine: SPLIT into serum vs urine (§11 decision 6, LOINC split).
--
-- PhenoAge inputs required: albumin, creatinine_serum, glucose_fasting,
--   crp, lymphocyte_pct, mcv, rdw, alp, wbc, (plus age from profiles).
-- FIB-4 inputs: age, ast, platelets, alt.
-- TyG inputs: triglycerides, glucose_fasting.
-- eGFR inputs: creatinine_serum (+ sex/age from profiles).
-- NAFLD-NFS inputs: albumin, ast, alt, platelets (+ bmi/diabetes from profiles).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- SOURCES (citations referenced by optimal_bands)
-- ---------------------------------------------------------------------------
INSERT INTO sources (id, tier, kind, title, citation_text, url, pmid, claim_supported) VALUES
  ('attia_apob_60',     3, 'expert_opinion',
   'Attia P. Outlive: The Science and Art of Longevity',
   'Attia P (2023). Outlive. Harmony Books. Expert opinion on apoB <60 mg/dL optimal target.',
   'https://peterattiamd.com', NULL,
   'apoB <60 mg/dL as a longevity-oriented optimal target (expert opinion; discuss with clinician)'),

  ('attia_hba1c_55',    3, 'expert_opinion',
   'Attia P. HbA1c optimal target <5.5%',
   'Attia P (2023). Outlive. Expert opinion: HbA1c <5.5% as optimal metabolic health marker.',
   'https://peterattiamd.com', NULL,
   'HbA1c <5.5% as a longevity-oriented optimal target (expert opinion; discuss with clinician)'),

  ('attia_alt_20',      3, 'expert_opinion',
   'Attia P. ALT optimal target <20 U/L',
   'Attia P (2023). Outlive. Expert opinion: ALT <20 U/L as a hepatic health marker.',
   'https://peterattiamd.com', NULL,
   'ALT <20 U/L as a longevity-oriented optimal target (expert opinion; discuss with clinician)'),

  ('attia_uric_50',     3, 'expert_opinion',
   'Attia P. Uric acid optimal target <5.0 mg/dL',
   'Attia P (2023). Outlive. Expert opinion: uric acid <5.0 mg/dL optimal.',
   'https://peterattiamd.com', NULL,
   'Uric acid <5.0 mg/dL optimal (expert opinion; discuss with clinician)'),

  ('harris_omega3_8pct', 1, 'peer_reviewed',
   'Harris WS et al. Omega-3 Index ≥8%',
   'Harris WS, Von Schacky C (2004). The Omega-3 Index: A new risk factor for death from coronary heart disease? Prev Med. PMID 15208005.',
   'https://pubmed.ncbi.nlm.nih.gov/15208005/', '15208005',
   'Omega-3 index ≥8% associated with lower cardiovascular risk (peer reviewed)'),

  ('endocrine_vitd_4060', 1, 'guideline',
   'Endocrine Society: Vitamin D 40–60 ng/mL optimal',
   'Holick MF et al. (2011). Evaluation, Treatment, and Prevention of Vitamin D Deficiency. J Clin Endocrinol Metab 96(7):1911–30. PMID 21646368.',
   'https://pubmed.ncbi.nlm.nih.gov/21646368/', '21646368',
   'Vitamin D 25-OH 40–60 ng/mL as optimal range per Endocrine Society guidelines');


-- ---------------------------------------------------------------------------
-- CANONICAL PARAMETERS
-- Columns: canonical_param_id, display_name, loinc_code, loinc_status,
--   category, specimen, canonical_unit, plausibility_low, plausibility_high,
--   default_ref_low, default_ref_high, aliases, alias_regexes,
--   polarity, hallmark_tags, horseman_tags, organ_system, is_ratio, is_derived
-- ---------------------------------------------------------------------------

-- ============ DIABETES / GLUCOSE ============================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('hba1c', 'HbA1c (Glycated Haemoglobin)', '4548-4', 'mapped',
   'Diabetes', 'whole_blood', '%', 3.0, 20.0, 4.0, 5.6,
   ARRAY['glycated haemoglobin', 'glycosylated haemoglobin', 'hba1c', 'a1c', 'hgba1c',
         'hemoglobin a1c', 'haemoglobin a1c', 'glycohemoglobin'],
   'lower_better',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'metabolic'),

  ('glucose_fasting', 'Glucose (Fasting)', '1558-6', 'mapped',
   'Diabetes', 'plasma', 'mg/dL', 40.0, 800.0, 70.0, 99.0,
   ARRAY['fasting glucose', 'fasting blood glucose', 'fbg', 'fasting plasma glucose',
         'fpg', 'blood sugar fasting', 'glucose fasting'],
   'lower_better',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'metabolic'),

  ('glucose_pp', 'Glucose (Post-Prandial / 2hr PP)', '14760-3', 'mapped',
   'Diabetes', 'plasma', 'mg/dL', 40.0, 1000.0, NULL, 140.0,
   ARRAY['pp glucose', 'post prandial glucose', '2hr pp', 'postprandial glucose',
         'glucose pp', '2 hour pp glucose'],
   'lower_better',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'metabolic'),

  ('fasting_insulin', 'Fasting Insulin', '20448-7', 'mapped',
   'Diabetes', 'serum', 'µIU/mL', 0.5, 300.0, 2.6, 24.9,
   ARRAY['insulin fasting', 'fasting serum insulin', 'serum insulin', 'insulin'],
   'lower_better',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'metabolic');

-- ============ LIPIDS ========================================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('total_cholesterol', 'Total Cholesterol', '2093-3', 'mapped',
   'Lipids', 'serum', 'mg/dL', 60.0, 700.0, NULL, 199.0,
   ARRAY['cholesterol total', 'total cholesterol', 'cholesterol', 'tc', 'serum cholesterol'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd'],
   'cardiovascular'),

  ('ldl_cholesterol', 'LDL Cholesterol', '2089-1', 'mapped',
   'Lipids', 'serum', 'mg/dL', 20.0, 500.0, NULL, 99.0,
   ARRAY['ldl', 'ldl-c', 'ldl cholesterol', 'low density lipoprotein', 'calculated ldl'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd'],
   'cardiovascular'),

  ('hdl_cholesterol', 'HDL Cholesterol', '2085-9', 'mapped',
   'Lipids', 'serum', 'mg/dL', 15.0, 150.0, 40.0, NULL,
   ARRAY['hdl', 'hdl-c', 'hdl cholesterol', 'high density lipoprotein', 'good cholesterol'],
   'higher_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd'],
   'cardiovascular'),

  ('triglycerides', 'Triglycerides', '2571-8', 'mapped',
   'Lipids', 'serum', 'mg/dL', 20.0, 5000.0, NULL, 149.0,
   ARRAY['tg', 'trigs', 'triglycerides', 'serum triglycerides', 'trig', 'triglyceride'],
   'lower_better',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic', 'ascvd'],
   'cardiovascular'),

  ('apob', 'Apolipoprotein B (ApoB)', '1884-6', 'mapped',
   'Lipids', 'serum', 'mg/dL', 20.0, 300.0, NULL, 100.0,
   ARRAY['apolipoprotein b', 'apo b', 'apo-b', 'apob100'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd'],
   'cardiovascular'),

  -- Lp(a) — TWO SEPARATE params per §11 decision 6; NEVER auto-convert between them
  ('lpa_mgdl', 'Lipoprotein(a) — mg/dL', '10835-7', 'mapped',
   'Lipids', 'serum', 'mg/dL', 0.0, 500.0, NULL, 30.0,
   ARRAY['lp(a)', 'lpa', 'lipoprotein a', 'lipoprotein(a) mg/dl'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd'],
   'cardiovascular'),

  ('lpa_nmol', 'Lipoprotein(a) — nmol/L', '43583-2', 'mapped',
   'Lipids', 'serum', 'nmol/L', 0.0, 1000.0, NULL, 75.0,
   ARRAY['lp(a) nmol', 'lipoprotein(a) nmol/l', 'lpa nmol'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd'],
   'cardiovascular');

-- ============ KIDNEY ========================================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  -- SPLIT: serum creatinine for eGFR / kidney trending
  ('creatinine_serum', 'Creatinine (Serum)', '2160-0', 'mapped',
   'Kidney', 'serum', 'mg/dL', 0.2, 30.0, 0.6, 1.2,
   ARRAY['creatinine', 'serum creatinine', 's.creatinine', 'creatinine serum', 'scr'],
   'lower_better',
   ARRAY['loss_of_proteostasis'],
   ARRAY['metabolic'],
   'kidney'),

  -- SPLIT: urine creatinine (different LOINC; do NOT mix with serum for eGFR)
  ('creatinine_urine', 'Creatinine (Urine)', '2161-8', 'mapped',
   'Urine', 'urine', 'mg/dL', 10.0, 4000.0, NULL, NULL,
   ARRAY['urine creatinine', 'urinary creatinine', 'urine creatinine (spot)'],
   NULL,
   ARRAY[],
   ARRAY[],
   'kidney'),

  ('egfr', 'eGFR (CKD-EPI 2021)', '62238-1', 'mapped',
   'Kidney', 'serum', 'mL/min/1.73m²', 1.0, 200.0, 60.0, NULL,
   ARRAY['egfr', 'gfr', 'glomerular filtration rate', 'estimated gfr', 'ckd-epi egfr',
         'egfr (ckd-epi)', 'egfr ckd epi'],
   'higher_better',
   ARRAY['loss_of_proteostasis'],
   ARRAY['metabolic'],
   'kidney'),

  ('urea', 'Blood Urea Nitrogen / Urea', '3094-0', 'mapped',
   'Kidney', 'serum', 'mg/dL', 5.0, 250.0, 7.0, 20.0,
   ARRAY['bun', 'urea nitrogen', 'blood urea', 'urea serum', 'blood urea nitrogen',
         'serum urea'],
   'lower_better',
   ARRAY['loss_of_proteostasis'],
   ARRAY['metabolic'],
   'kidney'),

  ('uric_acid', 'Uric Acid', '3084-1', 'mapped',
   'Kidney', 'serum', 'mg/dL', 1.0, 20.0, 2.6, 7.2,
   ARRAY['uric acid', 'serum uric acid', 'urate', 'gout marker'],
   'lower_better',
   ARRAY['deregulated_nutrient_sensing', 'chronic_inflammation'],
   ARRAY['metabolic'],
   'kidney');

-- ============ LIVER =========================================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('alt', 'ALT (Alanine Aminotransferase)', '1742-6', 'mapped',
   'Liver', 'serum', 'U/L', 1.0, 3000.0, 7.0, 40.0,
   ARRAY['alt', 'sgpt', 'alanine aminotransferase', 'alanine transaminase', 'alt/sgpt'],
   'lower_better',
   ARRAY['chronic_inflammation', 'mitochondrial_dysfunction'],
   ARRAY['metabolic'],
   'liver'),

  ('ast', 'AST (Aspartate Aminotransferase)', '1920-8', 'mapped',
   'Liver', 'serum', 'U/L', 1.0, 5000.0, 10.0, 40.0,
   ARRAY['ast', 'sgot', 'aspartate aminotransferase', 'aspartate transaminase', 'ast/sgot'],
   'lower_better',
   ARRAY['chronic_inflammation', 'mitochondrial_dysfunction'],
   ARRAY['metabolic'],
   'liver'),

  ('alp', 'ALP (Alkaline Phosphatase)', '6768-6', 'mapped',
   'Liver', 'serum', 'U/L', 10.0, 2000.0, 44.0, 147.0,
   ARRAY['alp', 'alkaline phosphatase', 'alk phos', 'sap'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['metabolic'],
   'liver'),

  ('albumin', 'Albumin (Serum)', '1751-7', 'mapped',
   'Liver', 'serum', 'g/dL', 1.0, 7.0, 3.5, 5.0,
   ARRAY['albumin', 'serum albumin', 's.albumin', 'alb'],
   'higher_better',
   ARRAY['loss_of_proteostasis'],
   ARRAY['metabolic'],
   'liver'),

  ('bilirubin_total', 'Bilirubin (Total)', '1975-2', 'mapped',
   'Liver', 'serum', 'mg/dL', 0.1, 30.0, 0.2, 1.2,
   ARRAY['total bilirubin', 'bilirubin total', 'bilirubin', 't.bil', 'tbil'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['metabolic'],
   'liver'),

  ('bilirubin_direct', 'Bilirubin (Direct)', '1968-7', 'mapped',
   'Liver', 'serum', 'mg/dL', 0.0, 20.0, 0.0, 0.3,
   ARRAY['direct bilirubin', 'conjugated bilirubin', 'd.bil', 'dbil'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['metabolic'],
   'liver'),

  ('ggt', 'GGT (Gamma-Glutamyl Transferase)', '2324-2', 'mapped',
   'Liver', 'serum', 'U/L', 1.0, 2000.0, 8.0, 61.0,
   ARRAY['ggt', 'gamma-glutamyl transferase', 'gamma gt', 'ggtp'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['metabolic'],
   'liver');

-- ============ THYROID =======================================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('tsh', 'TSH (Thyroid Stimulating Hormone)', '3016-3', 'mapped',
   'Thyroid', 'serum', 'µIU/mL', 0.001, 100.0, 0.4, 4.0,
   ARRAY['tsh', 'thyroid stimulating hormone', 'thyrotropin', 'sensitive tsh', 'ultrasensitive tsh'],
   'range_optimal',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'endocrine_thyroid'),

  ('t3_total', 'T3 Total (Triiodothyronine)', '3051-0', 'mapped',
   'Thyroid', 'serum', 'ng/dL', 40.0, 400.0, 80.0, 200.0,
   ARRAY['t3 total', 'total t3', 'triiodothyronine', 't3', 'serum t3 total'],
   'range_optimal',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'endocrine_thyroid'),

  ('t3_free', 'Free T3', '3054-4', 'mapped',
   'Thyroid', 'serum', 'pg/mL', 0.5, 20.0, 2.0, 4.4,
   ARRAY['free t3', 'ft3', 'free triiodothyronine', 'ft3 free'],
   'range_optimal',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'endocrine_thyroid'),

  ('t4_total', 'T4 Total (Thyroxine)', '3026-2', 'mapped',
   'Thyroid', 'serum', 'µg/dL', 1.0, 30.0, 5.0, 12.0,
   ARRAY['t4 total', 'total t4', 'thyroxine', 't4', 'serum t4'],
   'range_optimal',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'endocrine_thyroid'),

  ('t4_free', 'Free T4', '3024-7', 'mapped',
   'Thyroid', 'serum', 'ng/dL', 0.3, 10.0, 0.89, 1.76,
   ARRAY['free t4', 'ft4', 'free thyroxine', 'ft4 free'],
   'range_optimal',
   ARRAY['deregulated_nutrient_sensing'],
   ARRAY['metabolic'],
   'endocrine_thyroid');

-- ============ CBC (Complete Blood Count) ====================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('hemoglobin', 'Hemoglobin', '718-7', 'mapped',
   'CBC', 'whole_blood', 'g/dL', 4.0, 22.0, 12.0, 17.5,
   ARRAY['hemoglobin', 'haemoglobin', 'hb', 'hgb'],
   'range_optimal',
   ARRAY['stem_cell_exhaustion'],
   ARRAY['metabolic'],
   'hematologic'),

  ('wbc', 'WBC (White Blood Cell Count)', '6690-2', 'mapped',
   'CBC', 'whole_blood', '10³/µL', 0.5, 100.0, 4.0, 11.0,
   ARRAY['wbc', 'white blood cells', 'white blood cell count', 'tlc', 'total leucocyte count',
         'total leukocyte count', 'leukocyte count', 'wbc count'],
   'range_optimal',
   ARRAY['chronic_inflammation', 'stem_cell_exhaustion'],
   ARRAY['inflammation_immune'],
   'inflammation_immune'),

  ('rbc', 'RBC (Red Blood Cell Count)', '789-8', 'mapped',
   'CBC', 'whole_blood', '10⁶/µL', 1.0, 10.0, 4.0, 5.9,
   ARRAY['rbc', 'red blood cells', 'red blood cell count', 'erythrocytes'],
   'range_optimal',
   ARRAY['stem_cell_exhaustion'],
   ARRAY['metabolic'],
   'hematologic'),

  ('platelets', 'Platelets', '777-3', 'mapped',
   'CBC', 'whole_blood', '10³/µL', 10.0, 2000.0, 150.0, 400.0,
   ARRAY['platelets', 'platelet count', 'thrombocytes', 'plt'],
   'range_optimal',
   ARRAY['stem_cell_exhaustion'],
   ARRAY['metabolic'],
   'hematologic'),

  ('mcv', 'MCV (Mean Corpuscular Volume)', '787-2', 'mapped',
   'CBC', 'whole_blood', 'fL', 50.0, 130.0, 80.0, 100.0,
   ARRAY['mcv', 'mean corpuscular volume', 'mean cell volume'],
   'range_optimal',
   ARRAY['stem_cell_exhaustion'],
   ARRAY['metabolic'],
   'hematologic'),

  ('rdw', 'RDW (Red Cell Distribution Width)', '788-0', 'mapped',
   'CBC', 'whole_blood', '%', 10.0, 30.0, 11.5, 14.5,
   ARRAY['rdw', 'red cell distribution width', 'red blood cell distribution width', 'rdw-cv'],
   'lower_better',
   ARRAY['stem_cell_exhaustion'],
   ARRAY['metabolic'],
   'hematologic'),

  ('neutrophils_pct', 'Neutrophils %', '770-8', 'mapped',
   'CBC', 'whole_blood', '%', 1.0, 98.0, 40.0, 75.0,
   ARRAY['neutrophils', 'neutrophil %', 'polymorphonuclears', 'pmn', 'neutrophil percentage',
         'seg neutrophils', 'segs'],
   'range_optimal',
   ARRAY['chronic_inflammation'],
   ARRAY['inflammation_immune'],
   'inflammation_immune'),

  ('lymphocyte_pct', 'Lymphocytes %', '736-9', 'mapped',
   'CBC', 'whole_blood', '%', 1.0, 95.0, 20.0, 40.0,
   ARRAY['lymphocytes', 'lymphocyte %', 'lymph %', 'lymphocyte percentage', 'lymphocytes %'],
   'range_optimal',
   ARRAY['chronic_inflammation', 'stem_cell_exhaustion'],
   ARRAY['inflammation_immune'],
   'inflammation_immune'),

  ('monocyte_pct', 'Monocytes %', '5905-5', 'mapped',
   'CBC', 'whole_blood', '%', 0.0, 30.0, 2.0, 10.0,
   ARRAY['monocytes', 'monocyte %', 'monocyte percentage'],
   'range_optimal',
   ARRAY['chronic_inflammation'],
   ARRAY['inflammation_immune'],
   'inflammation_immune'),

  ('eosinophil_pct', 'Eosinophils %', '713-8', 'mapped',
   'CBC', 'whole_blood', '%', 0.0, 60.0, 1.0, 6.0,
   ARRAY['eosinophils', 'eosinophil %', 'eosinophil percentage', 'eos'],
   'range_optimal',
   ARRAY['chronic_inflammation'],
   ARRAY['inflammation_immune'],
   'inflammation_immune'),

  ('basophil_pct', 'Basophils %', '706-2', 'mapped',
   'CBC', 'whole_blood', '%', 0.0, 10.0, 0.0, 2.0,
   ARRAY['basophils', 'basophil %', 'basophil percentage'],
   'range_optimal',
   ARRAY[],
   ARRAY[],
   'hematologic'),

  ('hematocrit', 'Hematocrit (PCV)', '4544-3', 'mapped',
   'CBC', 'whole_blood', '%', 10.0, 70.0, 36.0, 52.0,
   ARRAY['hematocrit', 'haematocrit', 'pcv', 'packed cell volume', 'hct'],
   'range_optimal',
   ARRAY['stem_cell_exhaustion'],
   ARRAY['metabolic'],
   'hematologic');

-- ============ INFLAMMATION ==================================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('crp', 'CRP (C-Reactive Protein)', '1988-5', 'mapped',
   'Inflammation', 'serum', 'mg/L', 0.1, 500.0, NULL, 5.0,
   ARRAY['crp', 'c-reactive protein', 'c reactive protein', 'hscrp', 'hs-crp',
         'high sensitivity crp', 'ultra sensitive crp'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd', 'metabolic'],
   'inflammation_immune'),

  ('esr', 'ESR (Erythrocyte Sedimentation Rate)', '4537-7', 'mapped',
   'Inflammation', 'whole_blood', 'mm/hr', 0.0, 200.0, NULL, 20.0,
   ARRAY['esr', 'erythrocyte sedimentation rate', 'sed rate', 'westergren'],
   'lower_better',
   ARRAY['chronic_inflammation'],
   ARRAY['metabolic'],
   'inflammation_immune');

-- ============ VITAMINS / MINERALS ===========================================

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high, default_ref_low, default_ref_high,
   aliases, polarity, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('vitamin_d', '25-OH Vitamin D', '14635-7', 'mapped',
   'Vitamins', 'serum', 'ng/mL', 3.0, 200.0, 30.0, 100.0,
   ARRAY['vitamin d', '25-oh vitamin d', '25 oh vitamin d', 'vitamin d3', '25-hydroxyvitamin d',
         'calcidiol', 'cholecalciferol 25-oh', 'd3 25-oh', 'vitamin d (25-oh)'],
   'higher_better',
   ARRAY['epigenetic_alterations', 'chronic_inflammation'],
   ARRAY['metabolic'],
   'micronutrient_bone'),

  ('vitamin_b12', 'Vitamin B12 (Cobalamin)', '2132-9', 'mapped',
   'Vitamins', 'serum', 'pg/mL', 50.0, 10000.0, 200.0, 900.0,
   ARRAY['vitamin b12', 'b12', 'cobalamin', 'cyanocobalamin', 'vit b12', 'serum b12'],
   'range_optimal',
   ARRAY['epigenetic_alterations'],
   ARRAY['metabolic'],
   'micronutrient_bone'),

  ('ferritin', 'Ferritin', '2276-4', 'mapped',
   'Minerals', 'serum', 'ng/mL', 2.0, 10000.0, 12.0, 300.0,
   ARRAY['ferritin', 'serum ferritin', 'ferritin level'],
   'range_optimal',
   ARRAY['stem_cell_exhaustion'],
   ARRAY['metabolic'],
   'micronutrient_bone'),

  ('sodium', 'Sodium (Serum)', '2951-2', 'mapped',
   'Electrolytes', 'serum', 'mmol/L', 100.0, 180.0, 136.0, 145.0,
   ARRAY['sodium', 'na', 'serum sodium', 's.sodium', 'sodium serum'],
   'range_optimal',
   ARRAY[],
   ARRAY[],
   'kidney'),

  ('potassium', 'Potassium (Serum)', '2823-3', 'mapped',
   'Electrolytes', 'serum', 'mmol/L', 1.5, 10.0, 3.5, 5.0,
   ARRAY['potassium', 'k', 'serum potassium', 's.potassium', 'potassium serum'],
   'range_optimal',
   ARRAY[],
   ARRAY[],
   'kidney'),

  ('calcium', 'Calcium (Serum)', '17861-6', 'mapped',
   'Minerals', 'serum', 'mg/dL', 4.0, 16.0, 8.6, 10.2,
   ARRAY['calcium', 'ca', 'serum calcium', 's.calcium', 'total calcium'],
   'range_optimal',
   ARRAY[],
   ARRAY['metabolic'],
   'micronutrient_bone'),

  ('magnesium', 'Magnesium (Serum)', '19123-9', 'mapped',
   'Minerals', 'serum', 'mg/dL', 0.5, 6.0, 1.7, 2.4,
   ARRAY['magnesium', 'mg', 'serum magnesium', 's.magnesium'],
   'range_optimal',
   ARRAY[],
   ARRAY['metabolic'],
   'micronutrient_bone'),

  -- omega-3 index (not standard serum, but RBC-based)
  ('omega3_index', 'Omega-3 Index (EPA+DHA %)', '91512-8', 'candidate',
   'Vitamins', 'rbc', '%', 0.5, 20.0, NULL, NULL,
   ARRAY['omega-3 index', 'omega 3 index', 'epa+dha %', 'omega-3 fatty acids index'],
   'higher_better',
   ARRAY['chronic_inflammation'],
   ARRAY['ascvd'],
   'cardiovascular');

-- ============ DERIVED / COMPUTED RATIOS (analysis layer computes these) =====

INSERT INTO canonical_parameters
  (canonical_param_id, display_name, loinc_code, loinc_status, category, specimen,
   canonical_unit, plausibility_low, plausibility_high,
   aliases, polarity, is_ratio, is_derived, hallmark_tags, horseman_tags, organ_system)
VALUES
  ('nlr', 'NLR (Neutrophil-to-Lymphocyte Ratio)', NULL, 'unmapped',
   'Inflammation', NULL, 'ratio', 0.1, 50.0,
   ARRAY['nlr', 'neutrophil lymphocyte ratio', 'n/l ratio'],
   'lower_better', true, true,
   ARRAY['chronic_inflammation'], ARRAY['metabolic', 'cancer'],
   'inflammation_immune'),

  ('aar', 'AAR / De Ritis Ratio (AST:ALT)', NULL, 'unmapped',
   'Liver', NULL, 'ratio', 0.1, 20.0,
   ARRAY['aar', 'de ritis ratio', 'ast/alt', 'ast:alt ratio'],
   'range_optimal', true, true,
   ARRAY['chronic_inflammation'], ARRAY['metabolic'],
   'liver'),

  ('plr', 'PLR (Platelet-to-Lymphocyte Ratio)', NULL, 'unmapped',
   'Inflammation', NULL, 'ratio', 10.0, 1000.0,
   ARRAY['plr', 'platelet lymphocyte ratio', 'p/l ratio'],
   'lower_better', true, true,
   ARRAY['chronic_inflammation'], ARRAY['metabolic'],
   'inflammation_immune'),

  ('tyg', 'TyG Index (Triglyceride-Glucose)', NULL, 'unmapped',
   'Diabetes', NULL, 'ln(mg²/dL²)', 6.0, 12.0,
   ARRAY['tyg', 'tyg index', 'triglyceride glucose index', 'trig glucose index'],
   'lower_better', false, true,
   ARRAY['deregulated_nutrient_sensing'], ARRAY['metabolic'],
   'metabolic'),

  ('fib4', 'FIB-4 (Liver Fibrosis Score)', NULL, 'unmapped',
   'Liver', NULL, 'score', 0.1, 20.0,
   ARRAY['fib4', 'fib-4', 'fibrosis 4', 'fibrosis-4 index', 'fib4 score'],
   'lower_better', false, true,
   ARRAY['chronic_inflammation'], ARRAY['metabolic'],
   'liver'),

  ('phenoage', 'PhenoAge (Biological Age)', NULL, 'unmapped',
   'Other', NULL, 'years', 0.0, 120.0,
   ARRAY['phenoage', 'phenotypic age', 'biological age', 'bio age', 'levine age'],
   'lower_better', false, true,
   ARRAY['hallmarks_composite'], ARRAY['metabolic', 'ascvd', 'cancer', 'neuro'],
   NULL);

-- ---------------------------------------------------------------------------
-- UNIT RULES (common conversions for the most error-prone parameters)
-- Unit errors are the #1 implementation risk (§12 risk #1).
-- ---------------------------------------------------------------------------

-- CRP: mg/L → mg/dL  (factor 0.1); canonical is mg/L
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('crp', 'mg/l',   'identity', 1.0,  0, 0.1,  500.0, 'canonical unit'),
  ('crp', 'mg/dl',  'linear',   10.0, 0, 0.1,  500.0, 'mg/dL × 10 → mg/L'),
  ('crp', 'ug/ml',  'alias',    1.0,  0, 0.1,  500.0, 'µg/mL = mg/L'),
  ('crp', 'nmol/l', 'linear',   0.1047, 0, 0.1, 500.0, 'nmol/L ÷ 9.524 → mg/L (MW=115,000)');

-- Creatinine serum: mg/dL canonical; µmol/L input → mg/dL
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('creatinine_serum', 'mg/dl',   'identity', 1.0,     0, 0.2,  30.0, 'canonical'),
  ('creatinine_serum', 'umol/l',  'linear',   0.01131, 0, 0.2,  30.0, 'µmol/L ÷ 88.42 → mg/dL'),
  ('creatinine_serum', 'mmol/l',  'linear',   11.31,   0, 0.2,  30.0, 'mmol/L × 88.42 ÷ 1000 (rare)');

-- Glucose: mg/dL canonical; mmol/L input
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('glucose_fasting', 'mg/dl',  'identity', 1.0,  0, 40.0, 800.0, 'canonical'),
  ('glucose_fasting', 'mmol/l', 'linear',   18.0, 0, 40.0, 800.0, 'mmol/L × 18 → mg/dL'),
  ('glucose_pp',      'mg/dl',  'identity', 1.0,  0, 40.0, 1000.0,'canonical'),
  ('glucose_pp',      'mmol/l', 'linear',   18.0, 0, 40.0, 1000.0,'mmol/L × 18 → mg/dL');

-- Albumin: g/dL canonical; g/L input
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('albumin', 'g/dl', 'identity', 1.0,  0, 1.0, 7.0, 'canonical'),
  ('albumin', 'g/l',  'linear',   0.1,  0, 1.0, 7.0, 'g/L ÷ 10 → g/dL');

-- HbA1c: % canonical; mmol/mol (IFCC) input
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('hba1c', '%',        'identity', 1.0,     0,    3.0, 20.0, 'canonical (NGSP %)'),
  ('hba1c', 'mmol/mol', 'linear',   0.09148, 2.152, 3.0, 20.0, 'IFCC→NGSP: NGSP = (IFCC/10.929)+2.15');

-- TSH: µIU/mL canonical; mIU/L (same numeric), uIU/mL aliases
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('tsh', 'uiu/ml',  'alias',    1.0, 0, 0.001, 100.0, 'µIU/mL = uIU/mL'),
  ('tsh', 'miu/l',   'alias',    1.0, 0, 0.001, 100.0, 'mIU/L = µIU/mL numerically'),
  ('tsh', 'uiu/ml',  'identity', 1.0, 0, 0.001, 100.0, 'canonical');

-- T3 total: ng/dL canonical; ng/mL (÷100!), nmol/L, pg/mL — CRITICAL traps
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('t3_total', 'ng/dl',  'identity', 1.0,    0, 40.0, 400.0, 'canonical'),
  ('t3_total', 'ng/ml',  'linear',   100.0,  0, 40.0, 400.0, 'ng/mL × 100 → ng/dL (100× trap)'),
  ('t3_total', 'nmol/l', 'linear',   65.1,   0, 40.0, 400.0, 'nmol/L × 65.1 → ng/dL (MW=651 Da)'),
  ('t3_total', 'pg/ml',  'linear',   0.1,    0, 40.0, 400.0, 'pg/mL ÷ 10 → ng/dL');

-- T3 free: pg/mL canonical; ng/dL, pmol/L
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('t3_free', 'pg/ml',  'identity', 1.0,    0, 0.5, 20.0, 'canonical'),
  ('t3_free', 'ng/dl',  'linear',   10.0,   0, 0.5, 20.0, 'ng/dL × 10 → pg/mL'),
  ('t3_free', 'pmol/l', 'linear',   0.651,  0, 0.5, 20.0, 'pmol/L × 0.651 → pg/mL');

-- T4 total: µg/dL canonical; nmol/L, ng/dL
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('t4_total', 'ug/dl',  'identity', 1.0,    0, 1.0, 30.0, 'canonical'),
  ('t4_total', 'nmol/l', 'linear',   0.0777, 0, 1.0, 30.0, 'nmol/L × 0.0777 → µg/dL (MW=777 Da)'),
  ('t4_total', 'ng/dl',  'linear',   0.001,  0, 1.0, 30.0, 'ng/dL ÷ 1000 → µg/dL (rare misprint)');

-- Vitamin B12: pg/mL canonical; ng/mL (1000× trap!)
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('vitamin_b12', 'pg/ml', 'identity', 1.0,    0, 50.0, 10000.0, 'canonical'),
  ('vitamin_b12', 'ng/ml', 'linear',   1000.0, 0, 50.0, 10000.0, 'ng/mL × 1000 → pg/mL (1000× trap)'),
  ('vitamin_b12', 'pmol/l','linear',   0.7378, 0, 50.0, 10000.0, 'pmol/L × MW(1355.37)/1000 → pg/mL, approx');

-- Vitamin D: ng/mL canonical; nmol/L
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('vitamin_d', 'ng/ml',  'identity', 1.0,   0, 3.0, 200.0, 'canonical'),
  ('vitamin_d', 'nmol/l', 'linear',   0.401, 0, 3.0, 200.0, 'nmol/L × 0.401 → ng/mL');

-- WBC: 10³/µL canonical; lakhs (×10⁶/L→ ÷100 to get 10³/µL), cells/µL
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('wbc', '10^3/ul',  'identity', 1.0,    0, 0.5, 100.0, 'canonical'),
  ('wbc', '10^3/µl',  'alias',    1.0,    0, 0.5, 100.0, 'Unicode µ variant'),
  ('wbc', 'cells/ul', 'linear',   0.001,  0, 0.5, 100.0, 'cells/µL ÷ 1000 → 10³/µL'),
  ('wbc', 'lakhs/ul', 'linear',   100.0,  0, 0.5, 100.0, 'lakhs/µL × 100 → 10³/µL');

-- Platelets: 10³/µL canonical; lakhs/µL
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('platelets', '10^3/ul',  'identity', 1.0,   0, 10.0, 2000.0, 'canonical'),
  ('platelets', 'lakhs/ul', 'linear',   100.0, 0, 10.0, 2000.0, 'lakhs/µL × 100 → 10³/µL'),
  ('platelets', 'cells/ul', 'linear',   0.001, 0, 10.0, 2000.0, 'cells/µL ÷ 1000 → 10³/µL');

-- RBC: 10⁶/µL canonical; 10^6/µL variants
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('rbc', '10^6/ul', 'identity', 1.0, 0, 1.0, 10.0, 'canonical'),
  ('rbc', 'mil/ul',  'alias',    1.0, 0, 1.0, 10.0, 'million/µL = 10⁶/µL');

-- Lp(a): nonlinear_blocked between mg/dL and nmol/L (§11 decision 6)
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('lpa_mgdl', 'mg/dl',   'identity',          1.0, 0, 0.0, 500.0, 'canonical'),
  ('lpa_mgdl', 'nmol/l',  'nonlinear_blocked', NULL, NULL, NULL, NULL,
   'BLOCKED: Lp(a) mg/dL↔nmol/L is non-linear and contested; store as separate lpa_nmol param'),
  ('lpa_nmol', 'nmol/l',  'identity',          1.0, 0, 0.0, 1000.0,'canonical'),
  ('lpa_nmol', 'mg/dl',   'nonlinear_blocked', NULL, NULL, NULL, NULL,
   'BLOCKED: see above');

-- Uric acid: mg/dL canonical; µmol/L
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('uric_acid', 'mg/dl',  'identity', 1.0,    0, 1.0, 20.0, 'canonical'),
  ('uric_acid', 'umol/l', 'linear',   0.01681,0, 1.0, 20.0, 'µmol/L ÷ 59.48 → mg/dL (MW=168.11 g/mol)');

-- Sodium/Potassium: mmol/L canonical; mEq/L (numerically identical for these monovalent ions)
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('sodium',    'mmol/l', 'identity', 1.0, 0, 100.0, 180.0, 'canonical'),
  ('sodium',    'meq/l',  'alias',    1.0, 0, 100.0, 180.0, 'mEq/L = mmol/L for Na'),
  ('potassium', 'mmol/l', 'identity', 1.0, 0, 1.5,   10.0,  'canonical'),
  ('potassium', 'meq/l',  'alias',    1.0, 0, 1.5,   10.0,  'mEq/L = mmol/L for K');

-- Calcium: mg/dL canonical; mmol/L
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('calcium', 'mg/dl',  'identity', 1.0,    0, 4.0, 16.0, 'canonical'),
  ('calcium', 'mmol/l', 'linear',   4.0082, 0, 4.0, 16.0, 'mmol/L × 4.008 → mg/dL (MW=40.08)');

-- Magnesium: mg/dL canonical; mmol/L, mEq/L
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('magnesium', 'mg/dl',  'identity', 1.0,    0, 0.5, 6.0, 'canonical'),
  ('magnesium', 'mmol/l', 'linear',   2.4305, 0, 0.5, 6.0, 'mmol/L × 2.431 → mg/dL (MW=24.305)'),
  ('magnesium', 'meq/l',  'linear',   1.2153, 0, 0.5, 6.0, 'mEq/L × 1.215 → mg/dL');

-- Ferritin: ng/mL canonical; µg/L (same numeric)
INSERT INTO unit_rules (canonical_param_id, raw_unit_normalized, conversion_kind, factor, offset, guard_min, guard_max, note) VALUES
  ('ferritin', 'ng/ml', 'identity', 1.0, 0, 2.0, 10000.0, 'canonical'),
  ('ferritin', 'ug/l',  'alias',    1.0, 0, 2.0, 10000.0, 'µg/L = ng/mL');

-- ---------------------------------------------------------------------------
-- OPTIMAL BANDS (conservative, well-cited set only — §11 decision 4)
-- Evidence tier 3 = expert opinion (Attia), except omega-3 (tier 1) and vit D (tier 1)
-- ---------------------------------------------------------------------------

INSERT INTO optimal_bands
  (canonical_param_id, label, low, high, direction, sex_scope, evidence_tier, citation, disclaimer_key)
VALUES
  -- apoB <60 mg/dL (Attia, expert opinion; Tier 3)
  ('apob', 'optimal_attia',
   NULL, 60.0, 'lower_better', 'all', 3,
   '{"label":"Attia P (2023). Outlive. Expert opinion on apoB <60 mg/dL optimal target.",
     "source_id":"attia_apob_60","url":"https://peterattiamd.com"}'::jsonb,
   'expert_opinion_discuss_clinician'),

  -- HbA1c <5.5% (Attia, expert opinion; Tier 3)
  ('hba1c', 'optimal_attia',
   NULL, 5.5, 'lower_better', 'all', 3,
   '{"label":"Attia P (2023). Outlive. HbA1c <5.5% optimal metabolic target.",
     "source_id":"attia_hba1c_55","url":"https://peterattiamd.com"}'::jsonb,
   'expert_opinion_discuss_clinician'),

  -- ALT <20 U/L (Attia, expert opinion; Tier 3)
  ('alt', 'optimal_attia',
   NULL, 20.0, 'lower_better', 'all', 3,
   '{"label":"Attia P (2023). Outlive. ALT <20 U/L hepatic health optimal.",
     "source_id":"attia_alt_20","url":"https://peterattiamd.com"}'::jsonb,
   'expert_opinion_discuss_clinician'),

  -- Uric acid <5.0 mg/dL (Attia, expert opinion; Tier 3)
  ('uric_acid', 'optimal_attia',
   NULL, 5.0, 'lower_better', 'all', 3,
   '{"label":"Attia P (2023). Outlive. Uric acid <5.0 mg/dL optimal.",
     "source_id":"attia_uric_50","url":"https://peterattiamd.com"}'::jsonb,
   'expert_opinion_discuss_clinician'),

  -- Omega-3 index ≥8% (Harris 2004, peer-reviewed; Tier 1)
  ('omega3_index', 'optimal_harris',
   8.0, NULL, 'higher_better', 'all', 1,
   '{"label":"Harris WS, Von Schacky C (2004). The Omega-3 Index. Prev Med. PMID 15208005.",
     "source_id":"harris_omega3_8pct","pmid":"15208005",
     "url":"https://pubmed.ncbi.nlm.nih.gov/15208005/"}'::jsonb,
   'peer_reviewed_discuss_clinician'),

  -- Vitamin D 40–60 ng/mL (Endocrine Society; Tier 1)
  ('vitamin_d', 'optimal_endocrine_society',
   40.0, 60.0, 'range', 'all', 1,
   '{"label":"Holick MF et al. (2011). Endocrine Society Guidelines. J Clin Endocrinol Metab. PMID 21646368.",
     "source_id":"endocrine_vitd_4060","pmid":"21646368",
     "url":"https://pubmed.ncbi.nlm.nih.gov/21646368/"}'::jsonb,
   'peer_reviewed_discuss_clinician'),

  -- Lp(a) nmol/L <50 nmol/L (Attia expert optimal) / >100 very high (genetic)
  ('lpa_nmol', 'optimal_attia',
   NULL, 50.0, 'lower_better', 'all', 3,
   '{"label":"Attia P (2023). Outlive. Lp(a) <50 nmol/L optimal (genetic, one-time test).",
     "source_id":"attia_apob_60","url":"https://peterattiamd.com"}'::jsonb,
   'expert_opinion_genetic_one_time_test');

-- ---------------------------------------------------------------------------
-- VENDOR REGISTER (India stack at launch; EU vendors seeded as inactive)
-- ---------------------------------------------------------------------------
INSERT INTO vendor_register (vendor_key, region, endpoint, geo_constraint, dpa_signed, baa_signed, no_train_agreed, active, notes) VALUES
  ('vertex_gemini',   'in', 'https://asia-south1-aiplatform.googleapis.com', 'asia-south1',
   false, false, false, false, 'Vertex AI Gemini — parsing/OCR; DPA + CMEK needed before activation'),
  ('vertex_docai',    'in', 'https://asia-south1-documentai.googleapis.com', 'asia-south1',
   false, false, false, false, 'Document AI regional endpoint asia-south1'),
  ('sarvam',          'in', 'https://api.sarvam.ai', 'asia-south1',
   false, false, false, false, 'Sarvam AI — STT/TTS/LLM all-India; DPDP processor agreement needed'),
  ('livekit',         'in', NULL, 'ap-south-1',
   false, false, false, false, 'LiveKit self-hosted SFU on the same EC2 (not a cloud vendor at launch)'),
  ('deepgram_eu',     'eu', 'https://eu.api.deepgram.com', 'europe-west3',
   false, false, false, false, 'EU-only STT — not built at launch'),
  ('cartesia_eu',     'eu', NULL, 'europe-west3',
   false, false, false, false, 'EU-only TTS — not built at launch');
