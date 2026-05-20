# Statistical Analysis

This folder contains the R script used for the submitted statistical workflow. The script imports the publication-ready dataset, harmonises analysis variables, fits the calendar-time-adjusted and propensity-score models, generates balance diagnostics, performs sensitivity analyses, and writes tables and figures to its configured output directory.

| File | Description |
|---|---|
| `PPH_CordClamping_statistical_script.R` | Main statistical analysis script. |

To run the workflow from the repository root, use:

```bash
Rscript analysis/PPH_CordClamping_statistical_script.R
```

The script has been adjusted to locate the repository dataset at `data/PPH_CordClamping.csv` from the repository root or at `../data/PPH_CordClamping.csv` from the `analysis/` folder. The archived submitted outputs are stored separately in `analysis_outputs/`.
