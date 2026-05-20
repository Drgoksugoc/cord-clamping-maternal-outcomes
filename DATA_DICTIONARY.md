# Data Dictionary

This data dictionary describes the publication-ready, de-identified dataset used in the cord-clamping maternal-outcomes analysis. The table reports the variable name, a concise description, the type inferred from the CSV file, missingness counts, and representative example values.

The dataset contains **4,644 rows** and **70 variables**.

## Calendar-time variables (month resolution)

To reduce re-identification risk in a single-centre obstetric cohort, the original day-resolution `delivery_date_iso` field has been removed. Calendar time is represented at month resolution by three derived variables: `delivery_month` (YYYY-MM), `delivery_year_quarter` (YYYY-Qn) and `delivery_month_numeric` (months since the study-start anchor 2022-06). The R analysis script uses `delivery_month_numeric` as the term in the natural cubic spline.

Twelve records (originally) had missing or unparseable delivery dates, and one further record had a year outlier (2002 — confirmed to be a data-entry typo). These 13 records are flagged via `qc_missing_or_invalid_delivery_date = Yes` and excluded from calendar-adjusted models. The unadjusted analysis cohort therefore numbers 4,644; the calendar-adjusted cohort numbers 4,631.

## Variable inventory

| Variable | Description | Type | Non-missing | Missing | Unique values | Example values |
| --- | --- | --- | --- | --- | --- | --- |
| `study_id` | Repository-specific study identifier; no direct patient identifiers are included. | `str` | 4,644 | 0 | 4644 | PCC_00001; PCC_00002; PCC_00003; PCC_00004; PCC_00005 |
| `delivery_month` | Month of delivery in YYYY-MM format. Coarsened from the original day-resolution date for re-identification protection. | `str` | 4,631 | 13 | 31 | 2024-02; 2023-07; 2023-12; 2024-06; 2023-11 |
| `delivery_year_quarter` | Quarter of delivery in YYYY-Qn format. Coarsened from the original day-resolution date. | `str` | 4,631 | 13 | 11 | 2024-Q1; 2023-Q3; 2023-Q4; 2024-Q2; 2024-Q4 |
| `delivery_month_numeric` | Months elapsed since the study-start anchor (2022-06 = 0). Used as the calendar-time term in the natural cubic spline. | `int64` | 4,631 | 13 | 31 | 20; 13; 18; 24; 17 |
| `delivery_year` | Calendar year of delivery. | `int64` | 4,632 | 12 | 4 | 2024; 2023; 2022; 2002 |
| `anemia_status` | Pre-delivery anaemia status category. | `str` | 4,644 | 0 | 2 | Anemic; Non-anemic |
| `anemia_severity` | Pre-delivery anaemia severity category. | `str` | 4,644 | 0 | 4 | Mild anemia; Moderate anemia; No anemia; Severe anemia |
| `pre_delivery_hemoglobin_g_dl` | Pre-delivery haemoglobin concentration in g/dL. | `float64` | 4,644 | 0 | 83 | 9.6; 8.9; 15.3; 12.1; 13.7 |
| `postpartum_6h_hemoglobin_g_dl` | Six-hour postpartum haemoglobin concentration in g/dL. | `float64` | 4,644 | 0 | 84 | 9.5; 8.1; 9.4; 14.3; 10.3 |
| `hemoglobin_drop_g_dl` | Recorded haemoglobin decrease from pre-delivery to six-hour postpartum value in g/dL. | `float64` | 4,644 | 0 | 53 | 0.1; 0.8; 0.2; 1; 1.8 |
| `hemoglobin_drop_recalculated_g_dl` | Recalculated haemoglobin decrease from the two recorded haemoglobin measurements. | `float64` | 4,644 | 0 | 53 | 0.1; 0.8; 0.2; 1; 1.8 |
| `hemoglobin_drop_difference_recorded_vs_recalculated_g_dl` | Quality-control difference between recorded and recalculated haemoglobin decrease. | `int64` | 4,644 | 0 | 1 | 0 |
| `postpartum_anemia_hb_lt_10` | Indicator/category for postpartum haemoglobin below 10 g/dL. | `str` | 4,644 | 0 | 2 | Yes; No |
| `postpartum_anemia_hb_lt_10_binary` | Binary version of postpartum haemoglobin below 10 g/dL. | `int64` | 4,644 | 0 | 2 | 1; 0 |
| `postpartum_anemia_hb_lt_11` | Indicator/category for postpartum haemoglobin below 11 g/dL. | `str` | 4,644 | 0 | 2 | Yes; No |
| `postpartum_anemia_hb_lt_11_binary` | Binary version of postpartum haemoglobin below 11 g/dL. | `int64` | 4,644 | 0 | 2 | 1; 0 |
| `weight_kg` | Maternal weight in kilograms. | `float64` | 4,644 | 0 | 106 | 70; 61; 78; 90; 71 |
| `height_cm` | Maternal height in centimetres. | `int64` | 4,644 | 0 | 44 | 165; 160; 156; 163; 168 |
| `body_mass_index_kg_m2` | Body mass index in kg/m^2. | `float64` | 4,644 | 0 | 1080 | 25.712; 23.828; 28.65; 25.066; 33.874 |
| `parity` | Parity count/category as represented in the analysis dataset. | `int64` | 4,644 | 0 | 8 | 1; 0; 3; 2; 4 |
| `gravidity_group` | Gravidity category. | `str` | 4,644 | 0 | 2 | Multigravida; Primigravida |
| `grand_multiparity` | Grand multiparity category. | `str` | 4,644 | 0 | 2 | No; Yes |
| `grand_multiparity_binary` | Binary grand multiparity indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `number_of_fetuses` | Number of fetuses in the pregnancy. | `str` | 4,644 | 0 | 3 | Singleton; Twin; Triplet |
| `plurality_group` | Pregnancy plurality category. | `str` | 4,644 | 0 | 2 | Singleton; Multiple pregnancy |
| `maternal_comorbidity` | Maternal comorbidity category; raw free text has been removed. | `str` | 4,644 | 0 | 102 | Placental or fetal condition; Thyroid disease; None recorded; Hypertensive disorder; Autoimmune or rheumatologic disease |
| `maternal_comorbidity_raw_text_removed` | Flag documenting removal of raw maternal-comorbidity free text. | `str` | 4,644 | 0 | 2 | Yes; No |
| `pregnancy_complication` | Pregnancy complication category; raw free text has been removed. | `str` | 4,644 | 0 | 25 | None recorded; Hypertensive disorder; Amniotic fluid disorder; Fetal growth abnormality; Other specified pregnancy complication; Fetal growth abnormality |
| `pregnancy_complication_raw_text_removed` | Flag documenting removal of raw pregnancy-complication free text. | `str` | 4,644 | 0 | 2 | No; Yes |
| `iron_use_during_pregnancy` | Iron-use category during pregnancy. | `str` | 4,644 | 0 | 2 | Yes; No |
| `iron_use_during_pregnancy_binary` | Binary iron-use indicator during pregnancy. | `int64` | 4,644 | 0 | 2 | 1; 0 |
| `iv_ferric_carboxymaltose_use_during_pregnancy` | Intravenous ferric carboxymaltose-use category during pregnancy. | `str` | 4,644 | 0 | 2 | Yes; No |
| `iv_ferric_carboxymaltose_use_during_pregnancy_binary` | Binary intravenous ferric carboxymaltose-use indicator. | `int64` | 4,644 | 0 | 2 | 1; 0 |
| `hemoglobin_before_iv_iron_g_dl` | Haemoglobin concentration before intravenous iron, where applicable. | `float64` | 16 | 4628 | 12 | 9.5; 8.2; 8.7; 8.4; 10.1 |
| `delivery_mode` | Mode of delivery category. | `str` | 4,644 | 0 | 2 | Cesarean delivery; Vaginal delivery |
| `vaginal_delivery_subtype` | Subtype of vaginal delivery, where applicable. | `str` | 4,644 | 0 | 3 | Not applicable (cesarean delivery); Spontaneous vaginal delivery with mediolateral episiotomy; Spontaneous vaginal delivery |
| `cesarean_indication` | Caesarean indication category; raw free text has been removed. | `str` | 4,644 | 0 | 36 | Previous cesarean or uterine surgery; Fetal anomaly or disease; Multiple pregnancy; Malpresentation; Placental disorder or bleeding |
| `cesarean_indication_raw_text_removed` | Flag documenting removal of raw caesarean-indication free text. | `str` | 4,644 | 0 | 2 | Yes; Not applicable |
| `cord_clamping_group` | Recorded cord-clamping timing group. | `str` | 4,644 | 0 | 4 | Immediate; Delayed 30 seconds; Delayed 60 seconds; Delayed 120 seconds |
| `cord_clamping_delay_seconds` | Cord-clamping delay in seconds. | `int64` | 4,644 | 0 | 4 | 0; 30; 60; 120 |
| `cord_clamping_guideline_category` | Guideline-concordance category for cord-clamping timing. | `str` | 4,644 | 0 | 2 | Less than 60 seconds; 60 seconds or more |
| `guideline_delayed_cord_clamping_ge_60s` | Indicator/category for delayed cord clamping at 60 seconds or later. | `str` | 4,644 | 0 | 2 | No; Yes |
| `guideline_delayed_cord_clamping_ge_60s_binary` | Binary delayed cord clamping at 60 seconds or later indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `any_delayed_cord_clamping_ge_30s` | Indicator/category for any delayed cord clamping at 30 seconds or later. | `str` | 4,644 | 0 | 2 | No; Yes |
| `any_delayed_cord_clamping_ge_30s_binary` | Binary any delayed cord clamping at 30 seconds or later indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `immediate_cord_clamping` | Indicator/category for immediate cord clamping. | `str` | 4,644 | 0 | 2 | Yes; No |
| `immediate_cord_clamping_binary` | Binary immediate cord-clamping indicator. | `int64` | 4,644 | 0 | 2 | 1; 0 |
| `cord_clamping_delayed_30s` | Indicator/category for 30-second cord clamping. | `str` | 4,644 | 0 | 2 | No; Yes |
| `cord_clamping_delayed_30s_binary` | Binary 30-second cord-clamping indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `cord_clamping_delayed_60s` | Indicator/category for 60-second cord clamping. | `str` | 4,644 | 0 | 2 | No; Yes |
| `cord_clamping_delayed_60s_binary` | Binary 60-second cord-clamping indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `cord_clamping_delayed_120s` | Indicator/category for 120-second cord clamping. | `str` | 4,644 | 0 | 2 | No; Yes |
| `cord_clamping_delayed_120s_binary` | Binary 120-second cord-clamping indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `uterotonic_agent` | Uterotonic agent category. | `str` | 4,644 | 0 | 3 | Carbetocin; Oxytocin; Unclear/needs verification |
| `additional_uterotonic_used` | Additional uterotonic-use category. | `str` | 4,644 | 0 | 2 | No; Yes |
| `additional_uterotonic_used_binary` | Binary additional uterotonic-use indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `additional_uterotonic_type` | Additional uterotonic type, where recorded. | `str` | 4,644 | 0 | 5 | None or not recorded; Methylergometrine; Oxytocin; Combined uterotonics; Misoprostol |
| `additional_surgical_suture_used` | Additional surgical suture-use category. | `str` | 4,643 | 1 | 2 | No; Yes |
| `additional_surgical_suture_used_binary` | Binary additional surgical suture-use indicator. | `int64` | 4,643 | 1 | 2 | 0; 1 |
| `surgical_suture_type` | Surgical suture type, where recorded. | `str` | 4,644 | 0 | 3 | None or not recorded; B-Lynch suture; Hayman suture |
| `postpartum_hemorrhage` | Clinically recorded postpartum haemorrhage category. | `str` | 4,644 | 0 | 2 | No; Yes |
| `postpartum_hemorrhage_binary` | Binary clinically recorded postpartum haemorrhage indicator. | `int64` | 4,644 | 0 | 2 | 0; 1 |
| `blood_transfusion_needed` | Blood transfusion category during the delivery admission. | `str` | 4,642 | 2 | 2 | No; Yes |
| `blood_transfusion_needed_binary` | Binary blood-transfusion indicator. | `int64` | 4,642 | 2 | 2 | 0; 1 |
| `blood_transfusion_components` | Blood-transfusion component category, where applicable. | `str` | 4,644 | 0 | 14 | None recorded; 2 units packed red blood cells; 2 units fresh frozen plasma; 2 units fresh frozen plasma; 27 units packed red blood cells; 2 units packed red blood cells |
| `qc_vaginal_delivery_with_source_cesarean_indication` | Quality-control flag for vaginal delivery with a source caesarean indication. | `str` | 4,644 | 0 | 2 | No; Yes |
| `qc_unclear_uterotonic_agent` | Quality-control flag for unclear uterotonic agent. | `str` | 4,644 | 0 | 2 | No; Yes |
| `qc_missing_or_invalid_delivery_date` | Quality-control flag for missing or invalid delivery date. Records with this flag = Yes are excluded from calendar-adjusted analyses. | `str` | 4,644 | 0 | 2 | No; Yes |
| `qc_cord_clamping_indicator_mismatch` | Quality-control flag for mismatch among cord-clamping indicators. | `str` | 4,644 | 0 | 2 | No; Yes |
| `qc_cord_clamping_indicator_mismatch_fields` | Quality-control details for cord-clamping indicator mismatch fields. | `str` | 7 | 4637 | 3 | cord_clamping_delayed_60s_binary; cord_clamping_delayed_30s_binary; cord_clamping_delayed_30s_binary; cord_clamping_delayed_60s_binary |

## De-identification note

The dataset contains a repository-specific study identifier and analysis variables. Raw free-text fields for maternal comorbidities, pregnancy complications and caesarean indications are represented only through removal flags or standardised categorical variables, as documented in the variable names. The original day-resolution delivery-date field has been removed and replaced with month-resolution variables. Subjects with year outliers identified during the public-release audit (notably a single 2002 entry, confirmed as a transcription error from a 2022 date) have been flagged through `qc_missing_or_invalid_delivery_date` and excluded from calendar-adjusted models.