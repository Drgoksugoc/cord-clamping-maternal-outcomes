from pathlib import Path
import pandas as pd

repo = Path(__file__).resolve().parents[1]
data_path = repo / "data" / "PPH_CordClamping.csv"
df = pd.read_csv(data_path)

descriptions = {
    "study_id": "Repository-specific study identifier; no direct patient identifiers are included.",
    "delivery_month": "Month of delivery at YYYY-MM resolution for de-identified calendar-time analyses.",
    "delivery_year": "Calendar year of delivery.",
    "anemia_status": "Pre-delivery anemia status category.",
    "anemia_severity": "Pre-delivery anemia severity category.",
    "pre_delivery_hemoglobin_g_dl": "Pre-delivery hemoglobin concentration in g/dL.",
    "postpartum_6h_hemoglobin_g_dl": "Six-hour postpartum hemoglobin concentration in g/dL.",
    "hemoglobin_drop_g_dl": "Recorded hemoglobin decrease from pre-delivery to six-hour postpartum value in g/dL.",
    "hemoglobin_drop_recalculated_g_dl": "Recalculated hemoglobin decrease from the two recorded hemoglobin measurements.",
    "hemoglobin_drop_difference_recorded_vs_recalculated_g_dl": "Quality-control difference between recorded and recalculated hemoglobin decrease.",
    "postpartum_anemia_hb_lt_10": "Indicator/category for postpartum hemoglobin below 10 g/dL.",
    "postpartum_anemia_hb_lt_10_binary": "Binary version of postpartum hemoglobin below 10 g/dL.",
    "postpartum_anemia_hb_lt_11": "Indicator/category for postpartum hemoglobin below 11 g/dL.",
    "postpartum_anemia_hb_lt_11_binary": "Binary version of postpartum hemoglobin below 11 g/dL.",
    "weight_kg": "Maternal weight in kilograms.",
    "height_cm": "Maternal height in centimeters.",
    "body_mass_index_kg_m2": "Body mass index in kg/m².",
    "parity": "Parity count/category as represented in the analysis dataset.",
    "gravidity_group": "Gravidity category.",
    "grand_multiparity": "Grand multiparity category.",
    "grand_multiparity_binary": "Binary grand multiparity indicator.",
    "number_of_fetuses": "Number of fetuses in the pregnancy.",
    "plurality_group": "Pregnancy plurality category.",
    "maternal_comorbidity": "Maternal comorbidity category; raw free text has been removed.",
    "maternal_comorbidity_raw_text_removed": "Flag documenting removal of raw maternal-comorbidity free text.",
    "pregnancy_complication": "Pregnancy complication category; raw free text has been removed.",
    "pregnancy_complication_raw_text_removed": "Flag documenting removal of raw pregnancy-complication free text.",
    "iron_use_during_pregnancy": "Iron-use category during pregnancy.",
    "iron_use_during_pregnancy_binary": "Binary iron-use indicator during pregnancy.",
    "iv_ferric_carboxymaltose_use_during_pregnancy": "Intravenous ferric carboxymaltose-use category during pregnancy.",
    "iv_ferric_carboxymaltose_use_during_pregnancy_binary": "Binary intravenous ferric carboxymaltose-use indicator.",
    "hemoglobin_before_iv_iron_g_dl": "Hemoglobin concentration before intravenous iron, where applicable.",
    "delivery_mode": "Mode of delivery category.",
    "vaginal_delivery_subtype": "Subtype of vaginal delivery, where applicable.",
    "cesarean_indication": "Cesarean indication category; raw free text has been removed.",
    "cesarean_indication_raw_text_removed": "Flag documenting removal of raw cesarean-indication free text.",
    "cord_clamping_group": "Recorded cord-clamping timing group.",
    "cord_clamping_delay_seconds": "Cord-clamping delay in seconds.",
    "cord_clamping_guideline_category": "Guideline-concordance category for cord-clamping timing.",
    "guideline_delayed_cord_clamping_ge_60s": "Indicator/category for delayed cord clamping at 60 seconds or later.",
    "guideline_delayed_cord_clamping_ge_60s_binary": "Binary delayed cord clamping at 60 seconds or later indicator.",
    "any_delayed_cord_clamping_ge_30s": "Indicator/category for any delayed cord clamping at 30 seconds or later.",
    "any_delayed_cord_clamping_ge_30s_binary": "Binary any delayed cord clamping at 30 seconds or later indicator.",
    "immediate_cord_clamping": "Indicator/category for immediate cord clamping.",
    "immediate_cord_clamping_binary": "Binary immediate cord-clamping indicator.",
    "cord_clamping_delayed_30s": "Indicator/category for 30-second cord clamping.",
    "cord_clamping_delayed_30s_binary": "Binary 30-second cord-clamping indicator.",
    "cord_clamping_delayed_60s": "Indicator/category for 60-second cord clamping.",
    "cord_clamping_delayed_60s_binary": "Binary 60-second cord-clamping indicator.",
    "cord_clamping_delayed_120s": "Indicator/category for 120-second cord clamping.",
    "cord_clamping_delayed_120s_binary": "Binary 120-second cord-clamping indicator.",
    "uterotonic_agent": "Uterotonic agent category.",
    "additional_uterotonic_used": "Additional uterotonic-use category.",
    "additional_uterotonic_used_binary": "Binary additional uterotonic-use indicator.",
    "additional_uterotonic_type": "Additional uterotonic type, where recorded.",
    "additional_surgical_suture_used": "Additional surgical suture-use category.",
    "additional_surgical_suture_used_binary": "Binary additional surgical suture-use indicator.",
    "surgical_suture_type": "Surgical suture type, where recorded.",
    "postpartum_hemorrhage": "Clinically recorded postpartum hemorrhage category.",
    "postpartum_hemorrhage_binary": "Binary clinically recorded postpartum hemorrhage indicator.",
    "blood_transfusion_needed": "Blood transfusion category during the delivery admission.",
    "blood_transfusion_needed_binary": "Binary blood-transfusion indicator.",
    "blood_transfusion_components": "Blood-transfusion component category, where applicable.",
    "qc_vaginal_delivery_with_source_cesarean_indication": "Quality-control flag for vaginal delivery with a source cesarean indication.",
    "qc_unclear_uterotonic_agent": "Quality-control flag for unclear uterotonic agent.",
    "qc_missing_or_invalid_delivery_date": "Quality-control flag for missing or invalid delivery date.",
    "qc_cord_clamping_indicator_mismatch": "Quality-control flag for mismatch among cord-clamping indicators.",
    "qc_cord_clamping_indicator_mismatch_fields": "Quality-control details for cord-clamping indicator mismatch fields.",
}

profile_rows = []
for col in df.columns:
    s = df[col]
    non_missing = int(s.notna().sum())
    missing = int(s.isna().sum())
    dtype = str(s.dtype)
    unique_count = int(s.nunique(dropna=True))
    examples = []
    for value in s.dropna().astype(str).unique()[:5]:
        examples.append(value)
    profile_rows.append({
        "variable": col,
        "description": descriptions.get(col, "Analysis variable included in the publication-ready dataset."),
        "type_in_csv": dtype,
        "non_missing": non_missing,
        "missing": missing,
        "unique_values": unique_count,
        "example_values": "; ".join(examples),
    })

profile = pd.DataFrame(profile_rows)
profile.to_csv(repo / "metadata" / "data_profile.csv", index=False)

lines = []
lines.append("# Data Dictionary\n")
lines.append("This data dictionary describes the publication-ready, de-identified dataset used for the cord-clamping maternal-outcomes analysis. The table reports the variable name, a concise description, the type inferred from the CSV file, missingness, and representative example values.\n")
lines.append(f"The dataset contains **{len(df):,} rows** and **{len(df.columns):,} variables**.\n")
lines.append("| Variable | Description | Type | Non-missing | Missing | Unique values | Example values |")
lines.append("|---|---|---:|---:|---:|---:|---|")
for row in profile_rows:
    ex = str(row["example_values"]).replace("|", "\\|")
    desc = str(row["description"]).replace("|", "\\|")
    lines.append(f"| `{row['variable']}` | {desc} | `{row['type_in_csv']}` | {row['non_missing']} | {row['missing']} | {row['unique_values']} | {ex} |")
lines.append("\n## De-identification note\n")
lines.append("The dataset distributed in this repository contains a study identifier and analysis variables. Raw free-text fields for comorbidities, complications, and cesarean indications are represented only through removal flags or categorized fields, as reflected in the variable names.\n")
(repo / "DATA_DICTIONARY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Generated DATA_DICTIONARY.md and metadata/data_profile.csv")
