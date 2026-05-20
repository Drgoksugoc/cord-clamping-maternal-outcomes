# Reproducibility note: month-resolution calendar-time handling

This repository is designed to support public reproducibility while protecting participant privacy in a single-centre obstetric cohort. The public analysis dataset therefore represents calendar time at **month resolution** through variables such as `delivery_month`, `delivery_year_quarter`, and `delivery_month_numeric`. The original exact day-level delivery-date field is intentionally excluded from the public dataset.

The statistical script remains executable against the public dataset. When an exact delivery date is unavailable, the script synthesises an internal day-level date from `delivery_month` using a configurable within-month anchor day, with the 15th day of the month as the default. This synthetic date is used only for analysis operations that require a continuous calendar-time variable, including natural cubic spline adjustment and same-patient same-date duplicate diagnostics.

## Expected numerical differences from the private v14 day-resolution run

The archived v14 outputs were originally generated from the full internal analysis dataset containing exact delivery dates. A Phase 5 smoke test compared the primary postpartum anaemia risk ratios from the public month-resolution rerun with the private v14 reference outputs. The conventional adjusted modified Poisson result reproduced to two decimals, but three propensity-score-based estimates showed small expected numerical shifts because the calendar-time spline and matching distances depend on the within-month placement of observations.

| Primary postpartum anaemia method | v14 day-resolution RR | Public month-resolution rerun RR | Absolute difference | Two-decimal comparison |
| --- | ---: | ---: | ---: | --- |
| Conventional adjusted modified Poisson | 1.0155486298 | 1.0175381868 | 0.0019895570 | 1.02 vs 1.02 |
| Stabilized IPTW modified Poisson | 1.0146904275 | 1.0150364710 | 0.0003460435 | 1.01 vs 1.02 |
| Overlap-weighted modified Poisson | 0.9923684281 | 0.9952279520 | 0.0028595239 | 0.99 vs 1.00 |
| Propensity-score matched modified Poisson | 0.8773006135 | 0.8987341772 | 0.0214335637 | 0.88 vs 0.90 |

Additional anchor-day checks using the 1st, 5th, 10th, and 15th days of each month produced the same primary public rerun estimates, indicating that the discrepancy is not a simple artefact of the selected anchor day. Rather, it reflects the intentional replacement of exact day-level calendar information with month-resolution calendar information.

Accordingly, the public package should be interpreted as a **privacy-preserving reproducibility package** that reproduces the analysis workflow, variable definitions, model specifications, and aggregate outputs as closely as possible from the released de-identified data. It is not intended to provide bitwise-identical or guaranteed two-decimal-identical reproduction of analyses whose propensity-score or calendar-time components depend on exact delivery dates. Exact day-resolution replication would require access to the protected internal dataset under appropriate institutional governance and is outside the scope of this public repository.
