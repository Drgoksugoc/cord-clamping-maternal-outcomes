# Reproducibility note

This repository is designed to support public reproducibility for an observational cohort study evaluating delayed umbilical cord clamping and early postpartum maternal haematological outcomes.

## Dataset version (v16.4)

The public dataset now includes the day-resolution `delivery_date_iso` field (in M/D/YYYY format) and the derived `delivery_year` variable. The previous month-resolution variables (`delivery_month`, `delivery_year_quarter`, `delivery_month_numeric`) have been replaced. This allows the R analysis script (v16.4) to perform exact calendar-time adjustment via natural cubic splines without requiring a synthetic within-month anchor.

## PCC_04411 date correction

One record (PCC_04411) carries a source-level date typo: the delivery date is recorded as `11/17/2002` in the CSV. The `delivery_year` column already reflects the corrected year (2022), and the analysis script documents and handles this correction internally (mapping the date to 2022-11-17). This is noted in the script header as a known data-entry error.

## Analysis script version

The analysis script has been updated to **v16.4** (2026-07-22). Key changes from the previous v14 version include:

- Maternal age fully excluded (not available in the analysis dataset)
- Propensity scores computed from logistic regression with stabilised IPTW winsorised at the 1st/99th percentiles
- Weights computed directly (not via WeightIt, which aborted on near-separation)
- Fitted probabilities clamped to [1e-6, 1-1e-6] as a numerical safeguard
- Interaction-term filter fixed ("::" no longer matched)
- Day-resolution calendar-time adjustment using the exact `delivery_date_iso` field

## Reproducing the analysis

From the repository root:

```
Rscript analysis/PPH_CordClamping_statistical_script.R
```

The script resolves the dataset at `data/PPH_CordClamping.csv` when launched from the repository root, and at `../data/PPH_CordClamping.csv` when launched from inside `analysis/`. Outputs are written to `analysis_outputs_cord_clamping_v16_4_complete/`.

## Archived outputs

The `analysis_outputs/` directory contains the archived zip of all analysis outputs (`analysis_outputs_cord_clamping_v16_4_complete.zip`) produced by the v16.4 script. These serve as the reference outputs for reproducibility verification.
