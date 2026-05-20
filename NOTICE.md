# Repository Notice

This repository is a public reproducibility package for the study **"Delayed umbilical cord clamping and postpartum maternal outcomes: a calendar-time-adjusted observational cohort study."** It is intended to make the analysis dataset, statistical code and reporting checklist available for transparent peer review, analytic verification and reuse.

## De-identification

The dataset distributed in this repository is publication-ready and de-identified. It contains a repository-specific study identifier and analysis variables. It does not include direct patient identifiers (names, telephone numbers, e-mail addresses, street addresses or medical-record numbers), raw free-text clinical notes, or exact delivery dates. Calendar time is represented at month-level resolution (`delivery_month`, `delivery_year_quarter`, `delivery_month_numeric`); the original day-resolution field has been removed to reduce re-identification risk in a single-centre obstetric cohort.

Raw free-text fields for maternal comorbidities, pregnancy complications and caesarean indications were either removed or replaced by standardised categorical variables and quality-control flags.

## Licensing

Code in this repository is released under the [MIT License](LICENSE).
The dataset and data dictionary are released under [Creative Commons Attribution 4.0 International (CC-BY-4.0)](LICENSE-data).

Reuse is permitted under those terms with appropriate attribution. See [`CITATION.cff`](CITATION.cff) and the README for the recommended citation form.

## Contribution and curation rules

Future contributors to this repository must not commit:
- unredacted clinical exports;
- raw free-text clinical notes;
- direct patient identifiers;
- signed conflict-of-interest forms or other personal documents;
- private editorial correspondence;
- files containing institutional credentials.

If sensitive material is accidentally committed, contact the corresponding author listed in `CITATION.cff` immediately so the offending history can be rewritten and the public state corrected.
