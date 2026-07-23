# Delayed cord clamping and early maternal haematological outcomes
# Complete publication analysis for the BMC Pregnancy and Childbirth submission
# Version 16.4 (2026-07-22) — v16.3 with maternal age fully excluded because
# it is not available in the analysis dataset.
# Retains the documented PCC_04411 date correction (2002-11-17 -> 2022-11-17).
# v15 base. Propensity scores from logistic regression;
# stabilised IPTW winsorised at the 1st/99th percentiles, computed directly (not via
# WeightIt, which aborted on near-separation). Fitted probabilities are clamped to
# [1e-6, 1-1e-6] only as a numerical safeguard against division by ~0. Interaction-term
# filter fixed ("::" no longer matched).
#
# Primary exposure: delayed cord clamping >=60 seconds versus immediate/30 seconds
# Primary outcome: postpartum anaemia (venous Hb <10 g/dL at approximately 6 hours)
# Primary estimand: ATE using stabilised IPTW, winsorised at the 1st/99th percentiles
# Complementary estimands: model-based adjusted association, ATO, and matched ATT
#
# Place this script beside the confidential day-level analysis dataset and run it
# from that directory. The script creates a self-contained output folder.

options(stringsAsFactors = FALSE)
set.seed(20260721)

# -----------------------------
# 0. User settings
# -----------------------------
INPUT_CANDIDATES <- c(
  "data/PPH_CordClamping.csv",
  "../data/PPH_CordClamping.csv",
  "PPH_CordClamping.csv",
  "PPH_CordClamping_Fully_English_PublicationReady.csv",
  "PPH_CordClamping_Fully_English_PublicationReady.xlsx",
  "PPH_CordClamping_Final_PublicationReady_English.csv",
  "PPH_CordClamping_Final_PublicationReady_English.xlsx"
)
OUTPUT_DIR <- "analysis_outputs_cord_clamping_v16_4_complete"
PRIMARY_EXPOSURE <- "exposure_guideline_delay"
MIN_SUBGROUP_N <- 30
WEIGHT_TRUNCATION_QUANTILES <- c(0.01, 0.99)
SMD_THRESHOLD <- 0.10
MATCH_CALIPER_SD <- 0.20
EXPECTED_DATE_RANGE <- as.Date(c("2022-06-06", "2024-12-31"))

# Keep FALSE for the manuscript analysis. Set TRUE only for a clearly labelled
# reproducibility/sensitivity run using the privacy-preserving public dataset,
# which contains month rather than exact day of delivery.
ALLOW_MONTH_LEVEL_PUBLIC_REPRODUCTION <- FALSE

# -----------------------------
# 1. Packages
# -----------------------------
required_pkgs <- c(
  "tidyverse", "readr", "readxl", "janitor", "lubridate", "broom",
  "tableone", "WeightIt", "cobalt", "survey", "sandwich", "lmtest",
  "MatchIt", "logistf", "splines", "stringr", "forcats"
)
install_if_missing <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) install.packages(pkg, dependencies = TRUE)
}
invisible(lapply(required_pkgs, install_if_missing))
suppressPackageStartupMessages({
  library(tidyverse); library(readr); library(readxl); library(janitor)
  library(lubridate); library(broom); library(tableone); library(WeightIt)
  library(cobalt); library(survey); library(sandwich); library(lmtest)
  library(MatchIt); library(logistf); library(splines)
})

dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
SCRIPT_VERSION <- "v16.4_complete_2026-07-22"
message("Running PPH Cord Clamping integrated analysis script ", SCRIPT_VERSION)
write_text <- function(x, path) writeLines(as.character(x), con = path, useBytes = TRUE)
log_step <- function(x) message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), x))
`%||%` <- function(x, y) if (is.null(x)) y else x

# Safe output helpers for empty/error model tables. Some models legitimately return
# only an error column or zero rows; downstream filtering must not assume a term column.
standardize_result_table <- function(x) {
  if (is.null(x)) x <- tibble()
  if (!is.data.frame(x)) x <- tibble(message = as.character(x))
  x <- tibble::as_tibble(x)

  # Harmonise broom/survey naming variants before binding outputs.
  if ("std.error" %in% names(x) && !"std_error" %in% names(x)) x <- dplyr::rename(x, std_error = std.error)
  if ("p.value" %in% names(x) && !"p_value" %in% names(x)) x <- dplyr::rename(x, p_value = p.value)
  if ("conf.low" %in% names(x) && !"conf_low" %in% names(x)) x <- dplyr::rename(x, conf_low = conf.low)
  if ("conf.high" %in% names(x) && !"conf_high" %in% names(x)) x <- dplyr::rename(x, conf_high = conf.high)

  required <- c("term", "outcome", "model", "estimate", "std_error", "statistic",
                "conf_low", "conf_high", "estimate_exp", "conf_low_exp", "conf_high_exp",
                "p_value", "n_obs", "n_events", "error")
  for (nm in required) {
    if (!nm %in% names(x)) x[[nm]] <- NA
  }
  x
}
safe_write_csv <- function(x, path) {
  if (is.null(x)) x <- tibble()
  if (!is.data.frame(x)) x <- tibble(value = as.character(x))
  readr::write_csv(tibble::as_tibble(x), path)
}

safe_term_filter <- function(x, pattern) {
  x <- standardize_result_table(x)
  if (nrow(x) == 0) return(x[0, , drop = FALSE])
  x %>%
    dplyr::filter(!is.na(.data$term),
                  stringr::str_detect(as.character(.data$term), pattern))
}

safe_outcome_term_filter <- function(x, outcome_name, pattern) {
  x <- standardize_result_table(x)
  if (nrow(x) == 0) return(x[0, , drop = FALSE])
  x %>%
    dplyr::filter(.data$outcome == outcome_name,
                  !is.na(.data$term),
                  stringr::str_detect(as.character(.data$term), pattern))
}

safe_add_source <- function(x, source_name) {
  x <- standardize_result_table(x)
  if (nrow(x) == 0) return(tibble::tibble(source = source_name))
  x %>% dplyr::mutate(source = source_name)
}



# -----------------------------
# 2. Import and name helpers
# -----------------------------
existing <- INPUT_CANDIDATES[file.exists(INPUT_CANDIDATES)]
if (length(existing) == 0) stop("No input dataset found. Put PPH_CordClamping.csv in the working directory.")
INPUT_FILE <- existing[1]
log_step(paste("Using input file:", INPUT_FILE))

raw <- if (grepl("\\.xlsx$", INPUT_FILE, ignore.case = TRUE)) {
  readxl::read_excel(INPUT_FILE)
} else {
  readr::read_csv(INPUT_FILE, locale = locale(encoding = "UTF-8"), show_col_types = FALSE, guess_max = 10000)
}

normalize_name <- function(x) {
  x <- as.character(x)
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "_", x)
  x <- gsub("^_|_$", "", x)
  x
}
orig_names <- names(raw)
names(raw) <- make.unique(normalize_name(names(raw)), sep = "_")
name_map <- tibble(original_name = orig_names, normalized_name = names(raw))
write_csv(name_map, file.path(OUTPUT_DIR, "00_imported_column_name_map.csv"))

# -----------------------------
# 2a. Calendar-time resolution check
# -----------------------------
# The confidential analysis requires exact delivery dates. The public dataset
# deliberately coarsens dates to month resolution and cannot be claimed to
# reproduce the exact day-level matching or weighting estimates.
DATE_RESOLUTION_USED <- "day"
if (!"delivery_date_iso" %in% names(raw) && "delivery_month" %in% names(raw)) {
  if (!ALLOW_MONTH_LEVEL_PUBLIC_REPRODUCTION) {
    stop(
      "The input contains delivery_month but no day-level delivery_date_iso. ",
      "Use the confidential day-level dataset for the manuscript analysis, or set ",
      "ALLOW_MONTH_LEVEL_PUBLIC_REPRODUCTION <- TRUE for a labelled public-data sensitivity run."
    )
  }
  DATE_RESOLUTION_USED <- "month_midpoint_sensitivity"
  warning(
    "Using the 15th of each delivery month. Results are a privacy-preserving ",
    "sensitivity analysis and must not be presented as the exact manuscript estimates."
  )
  raw <- raw %>%
    mutate(
      delivery_date_iso = if_else(
        !is.na(delivery_month) & nzchar(as.character(delivery_month)),
        paste0(as.character(delivery_month), "-15"),
        NA_character_
      )
    )
}

# English-schema audit for the translated publication-ready dataset.
expected_english_columns <- c(
  "study_id", "delivery_date_iso", "anemia_status", "anemia_severity",
  "pre_delivery_hemoglobin_g_dl", "postpartum_6h_hemoglobin_g_dl", "hemoglobin_drop_g_dl",
  "weight_kg", "height_cm", "parity", "body_mass_index_kg_m2", "cord_clamping_group",
  "cord_clamping_delay_seconds", "number_of_fetuses", "maternal_comorbidity",
  "pregnancy_complication", "iron_use_during_pregnancy", "delivery_mode",
  "iv_ferric_carboxymaltose_use_during_pregnancy", "uterotonic_agent",
  "additional_uterotonic_used", "additional_surgical_suture_used",
  "blood_transfusion_needed", "gravidity_group", "grand_multiparity",
  "plurality_group", "postpartum_hemorrhage"
)
english_schema_audit <- tibble(
  expected_column = expected_english_columns,
  present = expected_column %in% names(raw)
)
write_csv(english_schema_audit, file.path(OUTPUT_DIR, "00_english_schema_audit.csv"))
if (sum(english_schema_audit$present) >= 20) {
  log_step("Detected translated English dataset schema.")
}

find_col <- function(data, aliases = character(), patterns = character()) {
  nm <- names(data)
  aliases <- normalize_name(aliases)
  hit <- intersect(aliases, nm)
  if (length(hit) > 0) return(hit[1])
  for (p in patterns) {
    h <- nm[str_detect(nm, regex(p, ignore_case = TRUE))]
    if (length(h) > 0) return(h[1])
  }
  NA_character_
}
get_col <- function(data, aliases = character(), patterns = character(), default = NA) {
  cc <- find_col(data, aliases, patterns)
  if (is.na(cc)) rep(default, nrow(data)) else data[[cc]]
}
num <- function(x) suppressWarnings(as.numeric(str_replace_all(as.character(x), ",", ".")))
chr <- function(x) str_squish(as.character(x))
low <- function(x) str_to_lower(chr(x))
yn01 <- function(x) {
  # Preserve true missing/blank values as NA. Explicit No/0 values remain 0.
  z <- low(x)
  case_when(
    is.na(z) | z %in% c("", "na", "nan", "missing", "unknown") ~ NA_integer_,
    z %in% c("1", "yes", "y", "true", "evet", "e") ~ 1L,
    z %in% c("0", "no", "n", "false", "hayir", "hayır", "h", "none", "none recorded", "no recorded") ~ 0L,
    TRUE ~ suppressWarnings(as.integer(as.numeric(z)))
  )
}
yn_factor <- function(x) factor(if_else(yn01(x) == 1L, "Yes", "No", missing = NA_character_), levels = c("No", "Yes"))
none_if_blank <- function(x) {
  z <- chr(x)
  z[z == "" | z == "NA" | is.na(z)] <- "None recorded"
  z
}

# -----------------------------
# 3. Harmonise raw/English dataset into analysis schema
# -----------------------------
map_anemia_status <- function(x) {
  z <- low(x)
  case_when(
    str_detect(z, "non[- ]?anemic|non[- ]?anaemic|normal|no anemia|no anaemia") ~ "Non-anemic",
    str_detect(z, "anemic|anaemic|anemia|anaemia") ~ "Anemic",
    TRUE ~ NA_character_
  )
}
map_anemia_severity <- function(x) {
  z <- low(x)
  case_when(
    str_detect(z, "no anemia|no anaemia|normal|none|no ana?emia") ~ "Normal",
    str_detect(z, "hafif|mild") ~ "Mild",
    str_detect(z, "orta|moderate") ~ "Moderate",
    str_detect(z, "agir|ağır|severe") ~ "Severe",
    TRUE ~ NA_character_
  )
}
map_delivery <- function(x) {
  z <- low(x)
  case_when(
    z %in% c("1", "vd", "vaginal", "vaginal delivery", "normal", "normal dogum", "nvd") ~ "Vaginal delivery",
    z %in% c("0", "cs", "c/s", "cesarean", "cesarean delivery", "sezaryen", "sezeryan") ~ "Cesarean delivery",
    str_detect(z, "vaj|vag|nvd|normal") ~ "Vaginal delivery",
    str_detect(z, "sez|ces|cs") ~ "Cesarean delivery",
    TRUE ~ NA_character_
  )
}
map_plurality <- function(x, n_fetus = NULL) {
  z <- low(x)
  out <- case_when(
    str_detect(z, "tek|single") ~ "Singleton",
    str_detect(z, "ikiz|cogul|çoğul|twin|multiple") ~ "Multiple pregnancy",
    TRUE ~ NA_character_
  )
  if (!is.null(n_fetus)) {
    out <- if_else(is.na(out) & !is.na(n_fetus) & n_fetus <= 1, "Singleton", out)
    out <- if_else(is.na(out) & !is.na(n_fetus) & n_fetus > 1, "Multiple pregnancy", out)
  }
  out
}
map_n_fetus <- function(x) {
  z <- low(x)
  case_when(
    str_detect(z, "tek|single") ~ 1,
    str_detect(z, "ikiz|twin") ~ 2,
    str_detect(z, "ucuz|trip|üç") ~ 3,
    TRUE ~ num(z)
  )
}
map_gravidity <- function(x) {
  z <- low(x)
  g <- num(x)
  case_when(
    str_detect(z, "primigravida|primi") ~ "Primigravida",
    str_detect(z, "multigravida|multi") ~ "Multigravida",
    is.na(g) ~ NA_character_,
    g <= 1 ~ "Primigravida",
    g > 1 ~ "Multigravida"
  )
}
map_uterotonic <- function(x) {
  z <- chr(x)
  z[z == "" | is.na(z) | z %in% c("NA", "N/A", "Missing", "Unknown")] <- NA_character_
  z <- str_to_upper(z)
  z <- case_when(
    is.na(z) ~ NA_character_,
    str_detect(z, "PABAL") ~ "Carbetocin/Pabal",
    str_detect(z, "OKS|OXY|OXT|SYN") ~ "Oxytocin",
    str_detect(z, "MISO|CYTO") ~ "Misoprostol",
    str_detect(z, "METHER|METILER") ~ "Methylergometrine",
    z %in% c("NONE", "NONE RECORDED", "NO", "NOT USED") ~ "None recorded",
    TRUE ~ str_to_sentence(z)
  )
  z
}
parse_date_any <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (is.numeric(x)) return(as.Date(x, origin = "1899-12-30"))
  xx <- chr(x)
  serial <- suppressWarnings(as.numeric(xx))
  y <- suppressWarnings(ymd(xx))
  idx <- is.na(y); if (any(idx)) y[idx] <- suppressWarnings(mdy(xx[idx]))
  idx <- is.na(y); if (any(idx)) y[idx] <- suppressWarnings(dmy(xx[idx]))
  idx <- is.na(y) & !is.na(serial) & serial > 20000 & serial < 80000
  if (any(idx)) y[idx] <- as.Date(serial[idx], origin = "1899-12-30")
  y
}

derive_cord_delay <- function(data) {
  direct <- get_col(data, c("cord_clamping_delay_seconds", "cord_delay_sec", "cord_clamping_delay_sec"), patterns = c("cord.*delay.*sec|clamp.*delay.*sec"))
  d <- num(direct)
  if (sum(!is.na(d)) > 0) return(d)
  c0 <- yn01(get_col(data, c("kordhemenmiklemplendievet1hayir0"), patterns = c("kord.*hemen|immediate.*clamp")))
  c30 <- yn01(get_col(data, c("kordklemplenmesi30snbeklendimievet1hayir0"), patterns = c("30.*sn|30.*sec")))
  c60 <- yn01(get_col(data, c("kordkelmplenmesi1dkbeklendimievet1hayir0"), patterns = c("1.*dk|1.*min|60.*sec")))
  c120 <- yn01(get_col(data, c("kordklemplenmesi2dkbeklendimievet1hayir0"), patterns = c("2.*dk|2.*min|120.*sec")))
  grp <- low(get_col(data, c("cord_clamping_group", "kkgrup"), patterns = c("kkgrup|cord.*group")))
  out <- rep(NA_real_, nrow(data))
  out[c0 == 1] <- 0
  out[c30 == 1] <- 30
  out[c60 == 1] <- 60
  out[c120 == 1] <- 120
  out[is.na(out) & str_detect(grp, "hemen|immediate")] <- 0
  out[is.na(out) & str_detect(grp, "30")] <- 30
  out[is.na(out) & str_detect(grp, "1.*dk|1.*min|60")] <- 60
  out[is.na(out) & str_detect(grp, "2.*dk|2.*min|120")] <- 120
  out
}

n_fetus <- map_n_fetus(get_col(raw, c("number_of_fetuses", "fetussayisi", "fetus_sayisi", "fetussayisi_1", "fetussayısı"), patterns = c("fetus|fetus.*say")))
cord_delay <- derive_cord_delay(raw)

dat <- tibble(
  study_id = as.character(get_col(raw, c("study_id", "patient_id", "protokol", "protocol_number"), default = seq_len(nrow(raw)))),
  delivery_date = parse_date_any(get_col(raw, c("delivery_date_iso", "delivery_date", "dogum_tarihi", "dogumtarihi"), patterns = c("dogum|delivery.*date"))),
  anemia_status = factor(map_anemia_status(get_col(raw, c("anemia_status", "anemi"))), levels = c("Non-anemic", "Anemic")),
  anemia_severity = factor(map_anemia_severity(get_col(raw, c("anemia_severity", "anemigrup", "anemi_grup"))), levels = c("Normal", "Mild", "Moderate", "Severe")),
  pre_delivery_hemoglobin_g_dl = num(get_col(raw, c("pre_delivery_hemoglobin_g_dl", "preophb", "preop_hb"), patterns = c("pre.*hb|preop"))),
  postpartum_6h_hemoglobin_g_dl = num(get_col(raw, c("postpartum_6h_hemoglobin_g_dl", "popp6_saathb", "popp6_saat_hb"), patterns = c("popp6|post.*6.*hb"))),
  hemoglobin_drop_g_dl = num(get_col(raw, c("hemoglobin_drop_g_dl", "hgfarki", "hg_farki", "hb_drop"), patterns = c("hgfark|hb.*drop|hemo.*drop"))),
  weight_kg = num(get_col(raw, c("weight_kg", "kilo"), patterns = c("kilo|weight"))),
  height_cm = num(get_col(raw, c("height_cm", "boy"), patterns = c("boy|height"))),
  parity = num(get_col(raw, c("parity", "parite"), patterns = c("parite|parity"))),
  body_mass_index_kg_m2 = num(get_col(raw, c("body_mass_index_kg_m2", "bmi"), patterns = c("bmi|mass_index"))),
  number_of_fetuses = n_fetus,
  cord_clamping_delay_seconds = cord_delay,
  maternal_comorbidity = none_if_blank(get_col(raw, c("maternal_comorbidity", "ekhastalik", "ek_hastalik"), patterns = c("ekhast|comorb"))),
  pregnancy_complication = none_if_blank(get_col(raw, c("pregnancy_complication", "gebelikkomplikasyonu", "gebelik_komplikasyonu"), patterns = c("gebelik.*komplik|pregnancy.*comp"))),
  iron_use_during_pregnancy = yn_factor(get_col(raw, c("iron_use_during_pregnancy", "gebeliktefekullanimivar1yok0"), patterns = c("gebelikte.*fe|iron.*preg"))),
  delivery_mode = factor(map_delivery(get_col(raw, c("delivery_mode", "dogumseklics0vd1", "dogum_sekli_cs0vd1", "dogum_sekli_cs0_vd1"), patterns = c("dogum.*sek|delivery.*mode"))), levels = c("Vaginal delivery", "Cesarean delivery")),
  iv_ferric_carboxymaltose_use_during_pregnancy = yn_factor(get_col(raw, c("iv_ferric_carboxymaltose_use_during_pregnancy", "gebelikteferinjektkullanildimievet1hayir0"), patterns = c("ferinjekt.*kullan|carboxymaltose"))),
  uterotonic_agent = factor(map_uterotonic(get_col(raw, c("uterotonic_agent", "uterotonikkullanimi"), patterns = c("uteroton")))),
  additional_uterotonic_used = yn_factor(get_col(raw, c("additional_uterotonic_used", "ekuterotonik"), patterns = c("ekuteroton|additional.*uterotonic"))),
  additional_surgical_suture_used = yn_factor(get_col(raw, c("additional_surgical_suture_used", "ekcerrahisutur"), patterns = c("ekcerrahi|suture"))),
  blood_transfusion_needed = yn_factor(get_col(raw, c("blood_transfusion_needed", "kantransfuzyonihtiyaci", "kan_transfuzyon_ihtiyaci"), patterns = c("kan.*trans|blood.*trans"))),
  gravidity_group = factor(map_gravidity(get_col(raw, c("gravidity_group", "gravidayeni", "gravida_yeni", "gravidayeni_1"), patterns = c("gravid"))), levels = c("Primigravida", "Multigravida")),
  grand_multiparity = yn_factor(get_col(raw, c("grand_multiparity", "grandmprt"), patterns = c("grand"))),
  plurality_group = factor(map_plurality(get_col(raw, c("plurality_group", "cogulgebelik", "cogul_gebelik"), patterns = c("cogul|plural")), n_fetus), levels = c("Singleton", "Multiple pregnancy")),
  postpartum_hemorrhage = yn_factor(get_col(raw, c("postpartum_hemorrhage", "kanama", "pph"), patterns = c("kanama|hemorrhage|pph")))
) %>%
  mutate(
    # Documented single-record data correction: PCC_04411 delivery date was recorded as
    # 2002-11-17 (a year-transcription error) and is corrected to 2022-11-17 per source review.
    # This deterministically fixes the record regardless of the input file; set aside if unwanted.
    delivery_date = if_else(study_id == "PCC_04411" & !is.na(delivery_date) & lubridate::year(delivery_date) == 2002L,
                            delivery_date + lubridate::years(20), delivery_date),
    hemoglobin_drop_g_dl = if_else(is.na(hemoglobin_drop_g_dl) & !is.na(pre_delivery_hemoglobin_g_dl) & !is.na(postpartum_6h_hemoglobin_g_dl), pre_delivery_hemoglobin_g_dl - postpartum_6h_hemoglobin_g_dl, hemoglobin_drop_g_dl),
    body_mass_index_kg_m2 = if_else(is.na(body_mass_index_kg_m2) & !is.na(weight_kg) & !is.na(height_cm) & height_cm > 0, weight_kg / (height_cm / 100)^2, body_mass_index_kg_m2),
    cord_group_4 = factor(case_when(cord_clamping_delay_seconds == 0 ~ "Immediate", cord_clamping_delay_seconds == 30 ~ "Delayed 30 seconds", cord_clamping_delay_seconds == 60 ~ "Delayed 60 seconds", cord_clamping_delay_seconds == 120 ~ "Delayed 120 seconds", TRUE ~ NA_character_), levels = c("Immediate", "Delayed 30 seconds", "Delayed 60 seconds", "Delayed 120 seconds")),
    exposure_guideline_delay = factor(case_when(cord_clamping_delay_seconds >= 60 ~ "Delayed_60s_or_more", cord_clamping_delay_seconds < 60 ~ "Immediate_or_30s", TRUE ~ NA_character_), levels = c("Immediate_or_30s", "Delayed_60s_or_more")),
    exposure_any_delay = factor(case_when(cord_clamping_delay_seconds > 0 ~ "Any_delay", cord_clamping_delay_seconds == 0 ~ "Immediate", TRUE ~ NA_character_), levels = c("Immediate", "Any_delay")),
    exposure_immediate_vs_60plus = factor(case_when(cord_clamping_delay_seconds == 0 ~ "Immediate", cord_clamping_delay_seconds >= 60 ~ "Delayed_60s_or_more", TRUE ~ NA_character_), levels = c("Immediate", "Delayed_60s_or_more")),
    pre_delivery_anemia_hb11 = factor(if_else(pre_delivery_hemoglobin_g_dl < 11, "Yes", "No", missing = NA_character_), levels = c("No", "Yes")),
    postpartum_anemia_hb10 = factor(if_else(postpartum_6h_hemoglobin_g_dl < 10, "Yes", "No", missing = NA_character_), levels = c("No", "Yes")),
    postpartum_anemia_hb11 = factor(if_else(postpartum_6h_hemoglobin_g_dl < 11, "Yes", "No", missing = NA_character_), levels = c("No", "Yes")),
    hb_drop_ge_2g = factor(if_else(hemoglobin_drop_g_dl >= 2, "Yes", "No", missing = NA_character_), levels = c("No", "Yes")),
    maternal_comorbidity_any = factor(if_else(!is.na(maternal_comorbidity) & maternal_comorbidity != "None recorded", "Yes", "No"), levels = c("No", "Yes")),
    pregnancy_complication_any = factor(if_else(!is.na(pregnancy_complication) & pregnancy_complication != "None recorded", "Yes", "No"), levels = c("No", "Yes")),
    delivery_date_valid = !is.na(delivery_date) & delivery_date >= EXPECTED_DATE_RANGE[1] & delivery_date <= EXPECTED_DATE_RANGE[2],
    delivery_year = factor(if_else(delivery_date_valid, as.character(year(delivery_date)), NA_character_)),
    delivery_month = if_else(delivery_date_valid, floor_date(delivery_date, unit = "month"), as.Date(NA)),
    delivery_year_quarter = factor(if_else(delivery_date_valid, paste0(year(delivery_date), "-Q", quarter(delivery_date)), NA_character_)),
    delivery_date_numeric = if_else(delivery_date_valid, as.numeric(delivery_date - EXPECTED_DATE_RANGE[1]), NA_real_),
    delivery_date_invalid_or_missing = factor(if_else(is.na(delivery_date_numeric), "Yes", "No"), levels = c("No", "Yes"))
  )

# The available study_id is a delivery-episode identifier, not a maternal ID.
# It is audited here but is never used to claim maternal-level clustering.
identifier_audit <- tibble(
  metric = c(
    "Records",
    "Missing episode identifiers",
    "Unique non-missing episode identifiers",
    "Records sharing an episode identifier"
  ),
  value = c(
    nrow(dat),
    sum(is.na(dat$study_id) | dat$study_id == ""),
    n_distinct(dat$study_id[!is.na(dat$study_id) & dat$study_id != ""]),
    sum(duplicated(dat$study_id) & !is.na(dat$study_id) & dat$study_id != "")
  ),
  interpretation = c(
    "Delivery episodes in the harmonised dataset",
    "Episode IDs missing",
    "Unique delivery-episode IDs; these are not maternal IDs",
    "A non-zero value requires source-data review; it does not identify repeat maternal deliveries"
  )
)
safe_write_csv(identifier_audit, file.path(OUTPUT_DIR, "00_episode_identifier_audit.csv"))

# Keep a cleaned analysis dataset for audit.
write_csv(dat, file.path(OUTPUT_DIR, "00_analysis_dataset_harmonised.csv"))

# Calendar-time diagnostics. Cord-clamping practice changed across the study period;
# therefore valid delivery date is included in the primary adjustment/PS models.
calendar_exposure <- dat %>%
  filter(!is.na(delivery_year)) %>%
  count(delivery_year, !!sym(PRIMARY_EXPOSURE), name = "n") %>%
  group_by(delivery_year) %>%
  mutate(percent_within_year = 100 * n / sum(n)) %>%
  ungroup()
safe_write_csv(calendar_exposure, file.path(OUTPUT_DIR, "00_calendar_time_by_exposure.csv"))

calendar_outcomes <- dat %>%
  filter(!is.na(delivery_year)) %>%
  group_by(delivery_year) %>%
  summarise(
    n = n(),
    postpartum_anemia_hb10_rate = mean(postpartum_anemia_hb10 == "Yes", na.rm = TRUE),
    postpartum_hemorrhage_rate = mean(postpartum_hemorrhage == "Yes", na.rm = TRUE),
    blood_transfusion_needed_rate = mean(blood_transfusion_needed == "Yes", na.rm = TRUE),
    .groups = "drop"
  )
safe_write_csv(calendar_outcomes, file.path(OUTPUT_DIR, "00_calendar_outcomes_by_year.csv"))

calendar_month_adoption <- dat %>%
  filter(delivery_date_valid, !is.na(delivery_month), !is.na(.data[[PRIMARY_EXPOSURE]])) %>%
  group_by(delivery_month) %>%
  summarise(
    n_deliveries = n(),
    n_dcc_60s_or_more = sum(.data[[PRIMARY_EXPOSURE]] == "Delayed_60s_or_more"),
    proportion_dcc_60s_or_more = n_dcc_60s_or_more / n_deliveries,
    .groups = "drop"
  )
safe_write_csv(calendar_month_adoption, file.path(OUTPUT_DIR, "00_calendar_month_adoption.csv"))
try({
  p_calendar <- ggplot(calendar_month_adoption, aes(delivery_month, proportion_dcc_60s_or_more)) +
    geom_line(linewidth = 0.65, colour = "#1B6CA8") +
    geom_point(size = 1.5, colour = "#1B6CA8") +
    scale_y_continuous(labels = scales::label_percent(accuracy = 1), limits = c(0, 1)) +
    theme_minimal(base_size = 11) +
    labs(x = "Month of delivery", y = "Deliveries with DCC >=60 seconds")
  ggsave(file.path(OUTPUT_DIR, "00_calendar_month_adoption_plot.png"), p_calendar,
         width = 8, height = 5, dpi = 300)
  ggsave(file.path(OUTPUT_DIR, "Main_Figure_5_calendar_adoption.png"), p_calendar,
         width = 8, height = 5, dpi = 300)
}, silent = TRUE)

invalid_dates <- dat %>%
  filter(is.na(delivery_date_numeric)) %>%
  select(any_of(c("study_id", "delivery_date", "cord_clamping_delay_seconds", "delivery_mode", PRIMARY_EXPOSURE)))
safe_write_csv(invalid_dates, file.path(OUTPUT_DIR, "00_invalid_or_missing_delivery_dates_for_calendar_adjustment.csv"))

# -----------------------------
# 4. QC and variable diagnostics
# -----------------------------
qc_overall <- tibble(
  metric = c(
    "Total delivery episodes", "Unique episode IDs", "Missing primary exposure",
    "Delayed >=60s", "Immediate/30s", "Missing/invalid delivery date",
    "Valid-date calendar-adjusted cohort", "Missing 6h Hb",
    "Postpartum anaemia Hb<10 events (full cohort)", "Missing transfusion status",
    "Vaginal deliveries", "Caesarean deliveries", "Date resolution used"
  ),
  value = as.character(c(
    nrow(dat), n_distinct(dat$study_id, na.rm = TRUE), sum(is.na(dat[[PRIMARY_EXPOSURE]])),
    sum(dat[[PRIMARY_EXPOSURE]] == "Delayed_60s_or_more", na.rm = TRUE),
    sum(dat[[PRIMARY_EXPOSURE]] == "Immediate_or_30s", na.rm = TRUE),
    sum(!dat$delivery_date_valid), sum(dat$delivery_date_valid),
    sum(is.na(dat$postpartum_6h_hemoglobin_g_dl)),
    sum(dat$postpartum_anemia_hb10 == "Yes", na.rm = TRUE),
    sum(is.na(dat$blood_transfusion_needed)),
    sum(dat$delivery_mode == "Vaginal delivery", na.rm = TRUE),
    sum(dat$delivery_mode == "Cesarean delivery", na.rm = TRUE),
    DATE_RESOLUTION_USED
  ))
)
write_csv(qc_overall, file.path(OUTPUT_DIR, "00_qc_overall.csv"))
structural_restricted <- c("exposure_any_delay", "exposure_immediate_vs_60plus")  # derived, restricted-by-design comparisons; their "missingness" is structural, not missing data
missingness <- tibble(variable = names(dat), missing_n = map_int(dat, ~ sum(is.na(.x))), missing_percent = 100 * missing_n / nrow(dat), nonmissing_distinct = map_int(dat, ~ n_distinct(.x, na.rm = TRUE)), structural_restriction = variable %in% structural_restricted) %>% arrange(desc(missing_percent))
write_csv(missingness, file.path(OUTPUT_DIR, "00_missingness_by_variable.csv"))
write_csv(tibble(variable = names(dat), class = map_chr(dat, ~ paste(class(.x), collapse = ";")), levels_or_range = map_chr(dat, function(x) { if (is.factor(x) || is.character(x)) paste(head(unique(na.omit(as.character(x))), 20), collapse = " | ") else paste0("range ", paste(range(x, na.rm = TRUE), collapse = " to ")) })), file.path(OUTPUT_DIR, "00_variable_types.csv"))

# -----------------------------
# 5. Dynamic formula utilities
# -----------------------------
has_2plus <- function(x) n_distinct(x[!is.na(x)]) >= 2

# All four main methods use the same valid-date cohort. This avoids comparing
# estimates generated from different calendar-time denominators.
analysis_dat <- dat %>% filter(delivery_date_valid)

base_covariates <- c(
  "pre_delivery_hemoglobin_g_dl", "body_mass_index_kg_m2", "parity",
  "delivery_mode", "plurality_group", "grand_multiparity",
  "iron_use_during_pregnancy", "iv_ferric_carboxymaltose_use_during_pregnancy",
  "maternal_comorbidity_any", "pregnancy_complication_any",
  "delivery_date_numeric"
)

core_analysis_variables <- c(
  PRIMARY_EXPOSURE, "postpartum_anemia_hb10", "postpartum_6h_hemoglobin_g_dl",
  "hemoglobin_drop_g_dl", base_covariates
)
absent_core <- setdiff(core_analysis_variables, names(analysis_dat))
if (length(absent_core) > 0) {
  stop("Required analysis variables are absent after harmonisation: ",
       paste(absent_core, collapse = ", "))
}
unusable_core <- core_analysis_variables[!map_lgl(analysis_dat[core_analysis_variables], ~ sum(!is.na(.x)) > 0)]
if (length(unusable_core) > 0) {
  stop("Required analysis variables contain no usable values: ",
       paste(unusable_core, collapse = ", "))
}
if (nrow(analysis_dat) == 0 || !has_2plus(analysis_dat[[PRIMARY_EXPOSURE]])) {
  stop("The valid-date analysis cohort is empty or contains only one exposure level.")
}

# The outcome-regression and propensity-score models use the specification
# stated in the manuscript. The three continuous covariates below are modelled
# flexibly with natural cubic splines (3 df) in both model families.
model_covariate_names <- base_covariates
model_covariates <- c(
  "splines::ns(pre_delivery_hemoglobin_g_dl, df = 3)",
  "splines::ns(body_mass_index_kg_m2, df = 3)",
  "parity", "delivery_mode", "plurality_group", "grand_multiparity",
  "iron_use_during_pregnancy", "iv_ferric_carboxymaltose_use_during_pregnancy",
  "maternal_comorbidity_any", "pregnancy_complication_any",
  "splines::ns(delivery_date_numeric, df = 3)"
)

covariate_audit <- tibble(
  covariate = base_covariates,
  non_missing_n = map_int(analysis_dat[base_covariates], ~ sum(!is.na(.x))),
  missing_n = map_int(analysis_dat[base_covariates], ~ sum(is.na(.x))),
  distinct_non_missing = map_int(analysis_dat[base_covariates], ~ n_distinct(.x, na.rm = TRUE)),
  model_form = case_when(
    covariate %in% c("pre_delivery_hemoglobin_g_dl", "body_mass_index_kg_m2", "delivery_date_numeric") ~ "Natural cubic spline, 3 df",
    TRUE ~ "Linear term or indicator contrasts"
  )
)
write_csv(covariate_audit, file.path(OUTPUT_DIR, "00_covariate_audit_and_model_forms.csv"))

term_vars <- function(terms) {
  vars <- unique(unlist(str_extract_all(terms, "[A-Za-z_][A-Za-z0-9_]*")))
  setdiff(vars, c("splines", "ns", "I", "log", "poly", "df", "TRUE", "FALSE"))
}
term_available <- function(term, data) all(term_vars(term) %in% names(data))
filter_terms <- function(terms, data) {
  terms <- terms[map_lgl(terms, ~ term_available(.x, data))]
  terms[map_lgl(terms, function(t) {
    vv <- intersect(term_vars(t), names(data))
    if (length(vv) == 0) TRUE else all(map_lgl(data[vv], has_2plus))
  })]
}
build_formula <- function(lhs, rhs_terms, data = NULL) {
  rhs_terms <- unique(rhs_terms)
  if (!is.null(data)) rhs_terms <- filter_terms(rhs_terms, data)
  if (length(rhs_terms) == 0) as.formula(paste(lhs, "~ 1")) else as.formula(paste(lhs, "~", paste(rhs_terms, collapse = " + ")))
}
needed_vars_for_terms <- function(terms, data) intersect(term_vars(terms), names(data))

make_model_data <- function(data, outcome, exposure, covariates, binary = TRUE) {
  terms <- unique(c(exposure, covariates))
  needed <- unique(c("study_id", outcome, needed_vars_for_terms(terms, data)))
  d <- data %>% select(any_of(needed))
  complete_vars <- intersect(c(outcome, exposure, needed_vars_for_terms(covariates, d)), names(d))
  d <- d %>% tidyr::drop_na(any_of(complete_vars))
  if (!exposure %in% names(d) || !has_2plus(d[[exposure]])) return(tibble())
  if (binary) {
    d$outcome_numeric <- as.integer(d[[outcome]] == "Yes")
    if (!has_2plus(d$outcome_numeric)) return(tibble())
  } else {
    d$outcome_numeric <- as.numeric(d[[outcome]])
    if (all(is.na(d$outcome_numeric)) || isTRUE(sd(d$outcome_numeric, na.rm = TRUE) == 0)) return(tibble())
  }
  d
}

tidy_robust <- function(fit, vc, exponentiate, model, outcome, exposure, n_obs, n_events) {
  beta <- coef(fit); se <- sqrt(diag(vc)); z <- beta / se
  out <- tibble(term = names(beta), estimate = beta, std_error = se, statistic = z, p_value = 2 * pnorm(abs(z), lower.tail = FALSE), conf_low = beta - 1.96 * se, conf_high = beta + 1.96 * se, model = model, outcome = outcome, exposure = exposure, n_obs = n_obs, n_events = n_events)
  if (exponentiate) out <- out %>% mutate(estimate_exp = exp(estimate), conf_low_exp = exp(conf_low), conf_high_exp = exp(conf_high))
  out
}

fit_poisson_rr <- function(data, outcome, exposure, covariates = character(), label = "modified_poisson_RR") {
  d <- make_model_data(data, outcome, exposure, covariates, TRUE)
  if (nrow(d) == 0) return(tibble(model = label, outcome = outcome, exposure = exposure, error = "No valid model data"))
  rhs <- filter_terms(c(exposure, covariates), d)
  f <- build_formula("outcome_numeric", rhs, d)
  fit <- tryCatch(glm(f, data = d, family = poisson(link = "log")), error = function(e) e)
  if (inherits(fit, "error")) return(tibble(model = label, outcome = outcome, exposure = exposure, error = conditionMessage(fit)))
  tidy_robust(fit, sandwich::vcovHC(fit, type = "HC0"), TRUE, label, outcome, exposure, nrow(d), sum(d$outcome_numeric))
}
fit_logistic_or <- function(data, outcome, exposure, covariates = character(), label = "logistic_OR") {
  d <- make_model_data(data, outcome, exposure, covariates, TRUE)
  if (nrow(d) == 0) return(tibble(model = label, outcome = outcome, exposure = exposure, error = "No valid model data"))
  rhs <- filter_terms(c(exposure, covariates), d)
  f <- build_formula("outcome_numeric", rhs, d)
  fit <- tryCatch(glm(f, data = d, family = binomial(link = "logit")), error = function(e) e)
  if (inherits(fit, "error")) return(tibble(model = label, outcome = outcome, exposure = exposure, error = conditionMessage(fit)))
  tidy_robust(fit, sandwich::vcovHC(fit, type = "HC0"), TRUE, label, outcome, exposure, nrow(d), sum(d$outcome_numeric))
}
fit_linear_beta <- function(data, outcome, exposure, covariates = character(), label = "linear_beta") {
  d <- make_model_data(data, outcome, exposure, covariates, FALSE)
  if (nrow(d) == 0) return(tibble(model = label, outcome = outcome, exposure = exposure, error = "No valid model data"))
  rhs <- filter_terms(c(exposure, covariates), d)
  f <- build_formula("outcome_numeric", rhs, d)
  fit <- tryCatch(lm(f, data = d), error = function(e) e)
  if (inherits(fit, "error")) return(tibble(model = label, outcome = outcome, exposure = exposure, error = conditionMessage(fit)))
  tidy_robust(fit, sandwich::vcovHC(fit, type = "HC3"), FALSE, label, outcome, exposure, nrow(d), NA_integer_)
}

# -----------------------------
# 6. Descriptive tables
# -----------------------------
log_step("Creating descriptive tables")
table_vars <- c("pre_delivery_hemoglobin_g_dl", "postpartum_6h_hemoglobin_g_dl", "hemoglobin_drop_g_dl", "body_mass_index_kg_m2", "weight_kg", "height_cm", "parity", "delivery_mode", "delivery_year", "delivery_date_invalid_or_missing", "plurality_group", "gravidity_group", "grand_multiparity", "pre_delivery_anemia_hb11", "iron_use_during_pregnancy", "iv_ferric_carboxymaltose_use_during_pregnancy", "maternal_comorbidity_any", "pregnancy_complication_any", "uterotonic_agent", "postpartum_anemia_hb10", "postpartum_anemia_hb11", "hb_drop_ge_2g", "postpartum_hemorrhage", "blood_transfusion_needed")
table_vars <- table_vars[table_vars %in% names(dat) & map_lgl(dat[table_vars[table_vars %in% names(dat)]], has_2plus)]
factor_vars <- table_vars[map_lgl(dat[table_vars], ~ is.factor(.x) || is.character(.x))]
make_table1 <- function(strata, prefix) {
  if (!strata %in% names(dat) || !has_2plus(dat[[strata]])) {
    write_text(paste0("Skipped: ", strata, " is absent or has <2 levels."), file.path(OUTPUT_DIR, paste0(prefix, "_SKIPPED.txt")))
    return(invisible(NULL))
  }
  tbl <- tryCatch(tableone::CreateTableOne(vars = table_vars, strata = strata, data = dat, factorVars = factor_vars, test = TRUE, smd = TRUE, includeNA = TRUE), error = function(e) e)
  if (inherits(tbl, "error")) {
    write_text(conditionMessage(tbl), file.path(OUTPUT_DIR, paste0(prefix, "_ERROR.txt")))
  } else {
    write_csv(as.data.frame(print(tbl, showAllLevels = TRUE, smd = TRUE, quote = FALSE, noSpaces = TRUE)) %>% rownames_to_column("variable"), file.path(OUTPUT_DIR, paste0(prefix, ".csv")))
    write_text(capture.output(print(tbl, showAllLevels = TRUE, smd = TRUE)), file.path(OUTPUT_DIR, paste0(prefix, ".txt")))
  }
}
make_table1(PRIMARY_EXPOSURE, "01_table1_by_primary_exposure")
make_table1("cord_group_4", "01_table1_by_four_level_cord_group")
make_table1("delivery_mode", "01_table1_by_delivery_mode")

# Plots
try({
  p1 <- analysis_dat %>%
    filter(!is.na(cord_group_4), !is.na(hemoglobin_drop_g_dl)) %>%
    ggplot(aes(cord_group_4, hemoglobin_drop_g_dl)) +
    geom_boxplot(outlier.alpha = .25) +
    theme_minimal(base_size = 12) +
    labs(x = "Cord clamping timing", y = "Haemoglobin drop (g/dL)") +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
  ggsave(file.path(OUTPUT_DIR, "01_hb_drop_by_cord_group.png"), p1, width = 8, height = 5, dpi = 300)
  ggsave(file.path(OUTPUT_DIR, "Supplementary_Figure_S3_hb_drop_distribution.png"), p1, width = 8, height = 5, dpi = 300)
}, silent = TRUE)

# -----------------------------
# 7. Main regression analyses
# -----------------------------
log_step("Running conventional regression analyses")
binary_outcomes <- c("postpartum_anemia_hb10", "postpartum_anemia_hb11", "hb_drop_ge_2g", "postpartum_hemorrhage", "blood_transfusion_needed")
binary_outcomes <- binary_outcomes[binary_outcomes %in% names(analysis_dat) & map_lgl(analysis_dat[binary_outcomes[binary_outcomes %in% names(analysis_dat)]], has_2plus)]
continuous_outcomes <- c("postpartum_6h_hemoglobin_g_dl", "hemoglobin_drop_g_dl")
continuous_outcomes <- continuous_outcomes[continuous_outcomes %in% names(analysis_dat)]

reg_results <- list()
for (y in binary_outcomes) {
  reg_results[[paste(y, "unadj_rr")]] <- fit_poisson_rr(analysis_dat, y, PRIMARY_EXPOSURE, character(), "unadjusted_modified_poisson_RR")
  reg_results[[paste(y, "adj_rr")]] <- fit_poisson_rr(analysis_dat, y, PRIMARY_EXPOSURE, model_covariates, "adjusted_modified_poisson_RR")
  reg_results[[paste(y, "adj_or")]] <- fit_logistic_or(analysis_dat, y, PRIMARY_EXPOSURE, model_covariates, "adjusted_logistic_OR")
}
for (y in continuous_outcomes) {
  reg_results[[paste(y, "unadj_beta")]] <- fit_linear_beta(analysis_dat, y, PRIMARY_EXPOSURE, character(), "unadjusted_linear_beta")
  reg_results[[paste(y, "adj_beta")]] <- fit_linear_beta(analysis_dat, y, PRIMARY_EXPOSURE, model_covariates, "adjusted_linear_beta")
}
reg_all <- standardize_result_table(bind_rows(reg_results))
safe_write_csv(reg_all, file.path(OUTPUT_DIR, "02_conventional_regression_all_terms.csv"))
safe_write_csv(safe_term_filter(reg_all, PRIMARY_EXPOSURE), file.path(OUTPUT_DIR, "02_conventional_regression_exposure_terms.csv"))

# -----------------------------
# 8. Propensity-score IPTW and overlap weighting
# -----------------------------
log_step("Running IPTW and overlap weighting")
ps_terms <- c(
  if ("pre_delivery_hemoglobin_g_dl" %in% model_covariate_names) "splines::ns(pre_delivery_hemoglobin_g_dl, df = 3)",
  if ("body_mass_index_kg_m2" %in% model_covariate_names) "splines::ns(body_mass_index_kg_m2, df = 3)",
  if ("delivery_date_numeric" %in% model_covariate_names) "splines::ns(delivery_date_numeric, df = 3)",
  setdiff(model_covariate_names, c("pre_delivery_hemoglobin_g_dl", "body_mass_index_kg_m2", "delivery_date_numeric"))
)
ps_terms <- filter_terms(ps_terms, analysis_dat)
write_csv(tibble(term = ps_terms), file.path(OUTPUT_DIR, "00_ps_formula_terms.csv"))

run_weighted <- function(estimand_type = c("ATE", "ATO")) {
  estimand_type <- match.arg(estimand_type)
  label <- ifelse(estimand_type == "ATE", "iptw", "overlap")
  needed <- unique(c(
    PRIMARY_EXPOSURE, needed_vars_for_terms(ps_terms, analysis_dat),
    binary_outcomes, continuous_outcomes, "study_id"
  ))
  d <- analysis_dat %>%
    select(any_of(needed)) %>%
    drop_na(any_of(c(PRIMARY_EXPOSURE, needed_vars_for_terms(ps_terms, analysis_dat))))
  if (nrow(d) == 0 || !has_2plus(d[[PRIMARY_EXPOSURE]])) {
    return(list(
      results = standardize_result_table(tibble(error = "No valid PS data")),
      balance = NULL, data = d, weightit = NULL, diagnostics = tibble()
    ))
  }
  f_ps <- build_formula(PRIMARY_EXPOSURE, ps_terms, d)
  # Fit the propensity score directly rather than via WeightIt::weightit().
  # Calendar time strongly separates DCC adoption (delivery-year SMD ~1.0), which pushes
  # fitted probabilities toward 0/1; weightit() then aborts with
  # "Missing values and NaN's not allowed if 'na.rm' is FALSE", which (being caught below)
  # would silently drop the PRIMARY IPTW result. Bounding the PS away from 0/1 keeps every
  # weight finite; stabilised ATE and overlap (ATO) weights are then formed in closed form.
  w <- tryCatch(glm(f_ps, data = d, family = binomial(link = "logit")), error = function(e) e)
  if (inherits(w, "error")) {
    return(list(
      results = standardize_result_table(tibble(error = conditionMessage(w))),
      balance = NULL, data = d, weightit = NULL, diagnostics = tibble()
    ))
  }
  ps_hat  <- pmin(pmax(as.numeric(fitted(w)), 1e-6), 1 - 1e-6)
  trt     <- as.integer(d[[PRIMARY_EXPOSURE]] == levels(d[[PRIMARY_EXPOSURE]])[2])  # 2nd level = Delayed_60s_or_more
  p_treat <- mean(trt)
  if (estimand_type == "ATE") {
    d$.weight_raw <- ifelse(trt == 1, p_treat / ps_hat, (1 - p_treat) / (1 - ps_hat))  # stabilised ATE
  } else {
    d$.weight_raw <- ifelse(trt == 1, 1 - ps_hat, ps_hat)                               # overlap (ATO)
  }
  d$.weight_analysis <- d$.weight_raw
  truncation_limits <- c(NA_real_, NA_real_)
  if (estimand_type == "ATE") {
    truncation_limits <- as.numeric(quantile(
      d$.weight_raw, probs = WEIGHT_TRUNCATION_QUANTILES,
      na.rm = TRUE, names = FALSE
    ))
    d$.weight_analysis <- pmin(
      pmax(d$.weight_raw, truncation_limits[1]),
      truncation_limits[2]
    )
  }

  d$.propensity_score <- ps_hat

  # IMPORTANT: balance is calculated with the exact weights used in the outcome
  # model. For IPTW these are the winsorised, not the original, weights.
  bal_obj <- cobalt::bal.tab(
    f_ps,
    data = d,
    weights = d$.weight_analysis,
    estimand = estimand_type,
    s.d.denom = "pooled",
    un = TRUE,
    thresholds = c(m = SMD_THRESHOLD)
  )
  bal_text <- capture.output(print(bal_obj))
  write_text(bal_text, file.path(OUTPUT_DIR, paste0("03_", label, "_balance.txt")))

  balance_table <- tibble(covariate = rownames(bal_obj$Balance)) %>%
    bind_cols(as_tibble(bal_obj$Balance, rownames = NULL))
  safe_write_csv(balance_table, file.path(OUTPUT_DIR, paste0("03_", label, "_balance_table.csv")))
  adjusted_smd <- if ("Diff.Adj" %in% names(balance_table)) balance_table$Diff.Adj else numeric()
  max_abs_smd <- if (length(adjusted_smd) > 0 && any(is.finite(adjusted_smd))) {
    max(abs(adjusted_smd), na.rm = TRUE)
  } else {
    NA_real_
  }
  max_smd_variable <- if (is.finite(max_abs_smd)) {
    balance_table$covariate[which.max(abs(balance_table$Diff.Adj))]
  } else {
    NA_character_
  }

  weight_by_group <- d %>%
    group_by(exposure_group = .data[[PRIMARY_EXPOSURE]]) %>%
    summarise(
      n = n(),
      sum_weights = sum(.weight_analysis),
      mean_weight = mean(.weight_analysis),
      min_weight = min(.weight_analysis),
      p01_weight = quantile(.weight_analysis, 0.01),
      median_weight = median(.weight_analysis),
      p99_weight = quantile(.weight_analysis, 0.99),
      max_weight = max(.weight_analysis),
      effective_sample_size = sum(.weight_analysis)^2 / sum(.weight_analysis^2),
      propensity_min = if (all(is.na(.propensity_score))) NA_real_ else min(.propensity_score, na.rm = TRUE),
      propensity_p01 = if (all(is.na(.propensity_score))) NA_real_ else quantile(.propensity_score, 0.01, na.rm = TRUE),
      propensity_median = if (all(is.na(.propensity_score))) NA_real_ else median(.propensity_score, na.rm = TRUE),
      propensity_p99 = if (all(is.na(.propensity_score))) NA_real_ else quantile(.propensity_score, 0.99, na.rm = TRUE),
      propensity_max = if (all(is.na(.propensity_score))) NA_real_ else max(.propensity_score, na.rm = TRUE),
      .groups = "drop"
    )
  safe_write_csv(weight_by_group, file.path(OUTPUT_DIR, paste0("03_", label, "_weight_and_ess_diagnostics.csv")))

  diagnostics <- tibble(
    method = label,
    estimand = estimand_type,
    n_propensity_cohort = nrow(d),
    lower_truncation_quantile = ifelse(estimand_type == "ATE", WEIGHT_TRUNCATION_QUANTILES[1], NA_real_),
    upper_truncation_quantile = ifelse(estimand_type == "ATE", WEIGHT_TRUNCATION_QUANTILES[2], NA_real_),
    lower_weight_limit = truncation_limits[1],
    upper_weight_limit = truncation_limits[2],
    n_weights_changed = sum(abs(d$.weight_analysis - d$.weight_raw) > sqrt(.Machine$double.eps)),
    maximum_absolute_adjusted_smd = max_abs_smd,
    variable_with_maximum_adjusted_smd = max_smd_variable,
    balance_threshold = SMD_THRESHOLD,
    all_adjusted_smd_below_threshold = is.finite(max_abs_smd) && max_abs_smd < SMD_THRESHOLD
  )
  safe_write_csv(diagnostics, file.path(OUTPUT_DIR, paste0("03_", label, "_diagnostic_summary.csv")))

  try({
    p_love <- cobalt::love.plot(
      bal_obj, stats = "mean.diffs", abs = TRUE,
      thresholds = c(m = SMD_THRESHOLD), var.order = "unadjusted"
    )
    ggsave(file.path(OUTPUT_DIR, paste0("03_", label, "_love_plot.png")), p_love,
           width = 8, height = 6, dpi = 300)
    if (label == "iptw") {
      ggsave(file.path(OUTPUT_DIR, "Main_Figure_2_IPTW_balance.png"), p_love,
             width = 8, height = 6, dpi = 300)
      ggsave(file.path(OUTPUT_DIR, "Supplementary_Figure_S1_IPTW_balance.png"), p_love,
             width = 8, height = 6, dpi = 300)
    }
    if (label == "overlap") {
      ggsave(file.path(OUTPUT_DIR, "Supplementary_Figure_S2_overlap_balance.png"), p_love,
             width = 8, height = 6, dpi = 300)
    }
  }, silent = TRUE)

  try({
    p_ps <- d %>%
      filter(is.finite(.propensity_score)) %>%
      ggplot(aes(x = .propensity_score, colour = .data[[PRIMARY_EXPOSURE]], fill = .data[[PRIMARY_EXPOSURE]])) +
      geom_density(alpha = 0.18, linewidth = 0.7) +
      theme_minimal(base_size = 11) +
      labs(x = "Estimated propensity score", y = "Density", colour = NULL, fill = NULL) +
      theme(legend.position = "bottom")
    ggsave(file.path(OUTPUT_DIR, paste0("03_", label, "_propensity_overlap.png")), p_ps,
           width = 7.5, height = 5, dpi = 300)
  }, silent = TRUE)

  res <- list()
  for (y in binary_outcomes) {
    dd <- d %>% drop_na(any_of(y)) %>% mutate(y_num = as.integer(.data[[y]] == "Yes"))
    if (nrow(dd) > 0 && has_2plus(dd$y_num) && has_2plus(dd[[PRIMARY_EXPOSURE]])) {
      des <- survey::svydesign(ids = ~1, weights = ~.weight_analysis, data = dd)
      ff <- as.formula(paste("y_num ~", PRIMARY_EXPOSURE))
      fit <- tryCatch(survey::svyglm(ff, design = des, family = quasipoisson(link = "log")), error = function(e) e)
      if (!inherits(fit, "error")) {
        tt <- broom::tidy(fit, conf.int = TRUE, exponentiate = TRUE) %>%
          mutate(model = paste0(label, "_weighted_RR"), outcome = y, exposure = PRIMARY_EXPOSURE, n_obs = nrow(dd), n_events = sum(dd$y_num))
        res[[paste(y, label)]] <- tt
      } else {
        res[[paste(y, label, "error")]] <- tibble(error = paste0("Weighted binary model failed for ", y, ": ", conditionMessage(fit)))
      }
    } else {
      res[[paste(y, label, "skipped")]] <- tibble(error = paste0("Weighted binary model skipped for ", y, ": insufficient outcome or exposure variation"))
    }
  }
  for (y in continuous_outcomes) {
    dd <- d %>% drop_na(any_of(y))
    if (nrow(dd) > 0 && has_2plus(dd[[PRIMARY_EXPOSURE]])) {
      des <- survey::svydesign(ids = ~1, weights = ~.weight_analysis, data = dd)
      ff <- as.formula(paste(y, "~", PRIMARY_EXPOSURE))
      fit <- tryCatch(survey::svyglm(ff, design = des), error = function(e) e)
      if (!inherits(fit, "error")) {
        res[[paste(y, label)]] <- broom::tidy(fit, conf.int = TRUE) %>%
          mutate(model = paste0(label, "_weighted_beta"), outcome = y, exposure = PRIMARY_EXPOSURE, n_obs = nrow(dd), n_events = NA_integer_)
      } else {
        res[[paste(y, label, "error")]] <- tibble(error = paste0("Weighted continuous model failed for ", y, ": ", conditionMessage(fit)))
      }
    } else {
      res[[paste(y, label, "skipped")]] <- tibble(error = paste0("Weighted continuous model skipped for ", y, ": insufficient data or exposure variation"))
    }
  }
  list(
    results = standardize_result_table(bind_rows(res)),
    balance = bal_obj, data = d, weightit = w, diagnostics = diagnostics
  )
}
iptw <- run_weighted("ATE")
overlap <- run_weighted("ATO")
safe_write_csv(iptw$results, file.path(OUTPUT_DIR, "03_iptw_results_all_terms.csv"))
safe_write_csv(safe_term_filter(iptw$results, PRIMARY_EXPOSURE), file.path(OUTPUT_DIR, "03_iptw_results_exposure_terms.csv"))
safe_write_csv(overlap$results, file.path(OUTPUT_DIR, "03_overlap_weight_results_all_terms.csv"))
safe_write_csv(safe_term_filter(overlap$results, PRIMARY_EXPOSURE), file.path(OUTPUT_DIR, "03_overlap_weight_results_exposure_terms.csv"))

# -----------------------------
# 9. Matching sensitivity
# -----------------------------
log_step("Running matching sensitivity")
fit_matched_poisson_rr <- function(data, outcome, exposure) {
  needed <- c(outcome, exposure, "subclass", "weights")
  if (!all(needed %in% names(data))) {
    return(tibble(
      model = "matched_pair_clustered_modified_poisson_RR", outcome = outcome,
      exposure = exposure, error = "Matched data lack outcome, exposure, subclass, or weights"
    ))
  }
  d <- data %>%
    select(all_of(needed)) %>%
    drop_na(all_of(c(outcome, exposure, "subclass", "weights"))) %>%
    mutate(outcome_numeric = as.integer(.data[[outcome]] == "Yes"))
  if (nrow(d) == 0 || !has_2plus(d$outcome_numeric) || !has_2plus(d[[exposure]])) {
    return(tibble(
      model = "matched_pair_clustered_modified_poisson_RR", outcome = outcome,
      exposure = exposure, error = "Insufficient matched outcome or exposure variation"
    ))
  }
  f <- as.formula(paste("outcome_numeric ~", exposure))
  fit <- tryCatch(
    glm(f, data = d, family = poisson(link = "log"), weights = weights),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(tibble(
      model = "matched_pair_clustered_modified_poisson_RR", outcome = outcome,
      exposure = exposure, error = conditionMessage(fit)
    ))
  }
  vc <- sandwich::vcovCL(
    fit, cluster = d$subclass, type = "HC0", cadjust = TRUE
  )
  tidy_robust(
    fit, vc, TRUE, "matched_pair_clustered_modified_poisson_RR",
    outcome, exposure, nrow(d), sum(d$outcome_numeric)
  ) %>%
    mutate(estimand = "ATT", matched_sets = n_distinct(d$subclass))
}

fit_matched_linear_beta <- function(data, outcome, exposure) {
  needed <- c(outcome, exposure, "subclass", "weights")
  if (!all(needed %in% names(data))) {
    return(tibble(
      model = "matched_pair_clustered_linear_beta", outcome = outcome,
      exposure = exposure, error = "Matched data lack outcome, exposure, subclass, or weights"
    ))
  }
  d <- data %>%
    select(all_of(needed)) %>%
    drop_na(all_of(c(outcome, exposure, "subclass", "weights")))
  outcome_sd <- if (nrow(d) >= 2) sd(d[[outcome]]) else NA_real_
  if (nrow(d) < 2 || !has_2plus(d[[exposure]]) || !is.finite(outcome_sd) || outcome_sd == 0) {
    return(tibble(
      model = "matched_pair_clustered_linear_beta", outcome = outcome,
      exposure = exposure, error = "Insufficient matched outcome or exposure variation"
    ))
  }
  f <- as.formula(paste(outcome, "~", exposure))
  fit <- tryCatch(lm(f, data = d, weights = weights), error = function(e) e)
  if (inherits(fit, "error")) {
    return(tibble(
      model = "matched_pair_clustered_linear_beta", outcome = outcome,
      exposure = exposure, error = conditionMessage(fit)
    ))
  }
  vc <- sandwich::vcovCL(
    fit, cluster = d$subclass, type = "HC0", cadjust = TRUE
  )
  tidy_robust(
    fit, vc, FALSE, "matched_pair_clustered_linear_beta",
    outcome, exposure, nrow(d), NA_integer_
  ) %>%
    mutate(estimand = "ATT", matched_sets = n_distinct(d$subclass))
}

match_results <- tibble()
match_diagnostics <- tibble()
mfit <- NULL
mdat <- tibble()

m_needed <- unique(c(
  PRIMARY_EXPOSURE, needed_vars_for_terms(ps_terms, analysis_dat),
  binary_outcomes, continuous_outcomes
))
md <- analysis_dat %>%
  select(any_of(m_needed)) %>%
  drop_na(any_of(c(PRIMARY_EXPOSURE, needed_vars_for_terms(ps_terms, analysis_dat))))

if (nrow(md) > 0 && has_2plus(md[[PRIMARY_EXPOSURE]])) {
  mfit <- tryCatch(
    MatchIt::matchit(
      build_formula(PRIMARY_EXPOSURE, ps_terms, md),
      data = md,
      method = "nearest",
      distance = "glm",
      # A 0.2-SD caliper is applied to the logit (linear predictor) of
      # the estimated propensity score.
      link = "linear.logit",
      estimand = "ATT",
      ratio = 1,
      replace = FALSE,
      caliper = MATCH_CALIPER_SD,
      std.caliper = TRUE
    ),
    error = function(e) e
  )

  if (!inherits(mfit, "error")) {
    mdat <- MatchIt::match.data(mfit, drop.unmatched = TRUE)
    write_text(capture.output(summary(mfit)), file.path(OUTPUT_DIR, "04_matching_summary.txt"))

    mbal <- cobalt::bal.tab(
      mfit, un = TRUE, s.d.denom = "pooled",
      thresholds = c(m = SMD_THRESHOLD)
    )
    write_text(capture.output(print(mbal)), file.path(OUTPUT_DIR, "04_matching_balance.txt"))
    matched_balance_table <- tibble(covariate = rownames(mbal$Balance)) %>%
      bind_cols(as_tibble(mbal$Balance, rownames = NULL))
    safe_write_csv(matched_balance_table, file.path(OUTPUT_DIR, "04_matching_balance_table.csv"))

    matched_covariate_balance <- matched_balance_table %>%
      filter(tolower(covariate) != "distance")
    matched_smd <- if ("Diff.Adj" %in% names(matched_covariate_balance)) {
      matched_covariate_balance$Diff.Adj
    } else {
      numeric()
    }
    max_matched_smd <- if (length(matched_smd) > 0 && any(is.finite(matched_smd))) {
      max(abs(matched_smd), na.rm = TRUE)
    } else {
      NA_real_
    }
    max_matched_variable <- if (is.finite(max_matched_smd)) {
      matched_covariate_balance$covariate[which.max(abs(matched_covariate_balance$Diff.Adj))]
    } else {
      NA_character_
    }

    matched_group_counts <- mdat %>%
      count(exposure_group = .data[[PRIMARY_EXPOSURE]], name = "matched_n")
    safe_write_csv(matched_group_counts, file.path(OUTPUT_DIR, "04_matching_group_counts.csv"))

    match_diagnostics <- tibble(
      estimand = "ATT",
      matching_method = "1:1 nearest-neighbour without replacement",
      propensity_model = "Logistic regression; caliper on logit of propensity score",
      caliper_standard_deviations = MATCH_CALIPER_SD,
      matched_n = nrow(mdat),
      matched_sets = n_distinct(mdat$subclass),
      maximum_absolute_adjusted_covariate_smd = max_matched_smd,
      variable_with_maximum_adjusted_covariate_smd = max_matched_variable,
      balance_threshold = SMD_THRESHOLD,
      all_adjusted_covariate_smd_below_threshold = is.finite(max_matched_smd) && max_matched_smd < SMD_THRESHOLD,
      outcome_inference = "Sandwich standard errors clustered by matched subclass"
    )
    safe_write_csv(match_diagnostics, file.path(OUTPUT_DIR, "04_matching_diagnostic_summary.csv"))

    try({
      png(file.path(OUTPUT_DIR, "04_matching_love_plot.png"), width = 2400, height = 1800, res = 300)
      print(cobalt::love.plot(
        mbal, stats = "mean.diffs", abs = TRUE,
        thresholds = c(m = SMD_THRESHOLD), var.order = "unadjusted"
      ))
      dev.off()
    }, silent = TRUE)

    tmp <- list()
    for (y in binary_outcomes) tmp[[y]] <- fit_matched_poisson_rr(mdat, y, PRIMARY_EXPOSURE)
    for (y in continuous_outcomes) tmp[[y]] <- fit_matched_linear_beta(mdat, y, PRIMARY_EXPOSURE)
    match_results <- standardize_result_table(bind_rows(tmp))
  } else {
    write_text(conditionMessage(mfit), file.path(OUTPUT_DIR, "04_matching_ERROR.txt"))
    match_results <- standardize_result_table(tibble(error = conditionMessage(mfit)))
  }
} else {
  match_results <- standardize_result_table(tibble(error = "No valid matching cohort"))
}
safe_write_csv(match_results, file.path(OUTPUT_DIR, "04_matching_results_all_terms.csv"))
safe_write_csv(safe_term_filter(match_results, PRIMARY_EXPOSURE), file.path(OUTPUT_DIR, "04_matching_results_exposure_terms.csv"))

# -----------------------------
# 10. Alternative exposure definitions and dose response
# -----------------------------
log_step("Running sensitivity exposure models")
sens_results <- list()
for (expv in c("exposure_any_delay", "exposure_immediate_vs_60plus", "cord_group_4")) {
  if (expv %in% names(analysis_dat) && has_2plus(analysis_dat[[expv]])) {
    for (y in binary_outcomes) sens_results[[paste(expv, y)]] <- fit_poisson_rr(analysis_dat, y, expv, model_covariates, paste0("sensitivity_", expv, "_RR"))
    for (y in continuous_outcomes) sens_results[[paste(expv, y)]] <- fit_linear_beta(analysis_dat, y, expv, model_covariates, paste0("sensitivity_", expv, "_beta"))
  }
}
for (y in binary_outcomes) sens_results[[paste("dose", y)]] <- fit_poisson_rr(analysis_dat %>% mutate(cord_delay_min = cord_clamping_delay_seconds / 60), y, "cord_delay_min", model_covariates, "dose_per_minute_RR")
for (y in continuous_outcomes) sens_results[[paste("dose", y)]] <- fit_linear_beta(analysis_dat %>% mutate(cord_delay_min = cord_clamping_delay_seconds / 60), y, "cord_delay_min", model_covariates, "dose_per_minute_beta")
sens_all <- standardize_result_table(bind_rows(sens_results))
safe_write_csv(sens_all, file.path(OUTPUT_DIR, "05_sensitivity_and_dose_models_all_terms.csv"))
safe_write_csv(safe_term_filter(sens_all, "exposure_|cord_group_4|cord_delay_min"), file.path(OUTPUT_DIR, "05_sensitivity_and_dose_models_exposure_terms.csv"))

four_level_primary <- sens_all %>%
  standardize_result_table() %>%
  filter(
    outcome == "postpartum_anemia_hb10",
    model == "sensitivity_cord_group_4_RR",
    !is.na(term), str_detect(term, "^cord_group_4")
  ) %>%
  transmute(
    clamping_group = case_when(
      str_detect(term, "30") ~ "Delayed 30 seconds",
      str_detect(term, "60") ~ "Delayed 60 seconds",
      str_detect(term, "120") ~ "Delayed 120 seconds",
      TRUE ~ term
    ),
    risk_ratio = estimate_exp,
    ci_low = conf_low_exp,
    ci_high = conf_high_exp,
    p_value,
    n_obs,
    n_events
  )
safe_write_csv(four_level_primary, file.path(OUTPUT_DIR, "05_four_level_primary_outcome_summary.csv"))
try({
  if (nrow(four_level_primary) > 0) {
    p_four <- four_level_primary %>%
      mutate(clamping_group = factor(
        clamping_group,
        levels = rev(c("Delayed 30 seconds", "Delayed 60 seconds", "Delayed 120 seconds"))
      )) %>%
      ggplot(aes(risk_ratio, clamping_group)) +
      geom_vline(xintercept = 1, linetype = 2, colour = "grey45") +
      geom_pointrange(aes(xmin = ci_low, xmax = ci_high), linewidth = 0.5) +
      scale_x_log10() +
      theme_minimal(base_size = 11) +
      labs(x = "Adjusted risk ratio (95% CI), logarithmic scale", y = NULL)
    ggsave(file.path(OUTPUT_DIR, "05_four_level_primary_outcome_forest.png"), p_four,
           width = 7.5, height = 4.5, dpi = 300)
    ggsave(file.path(OUTPUT_DIR, "Supplementary_Figure_S4_four_level_forest.png"), p_four,
           width = 7.5, height = 4.5, dpi = 300)
  }
}, silent = TRUE)

# -----------------------------
# 11. Subgroups, built only when column exists and is usable
# -----------------------------
log_step("Running safe subgroup analyses")
subgroups <- list()
if ("delivery_mode" %in% names(analysis_dat)) {
  subgroups$vaginal_delivery <- quo(delivery_mode == "Vaginal delivery")
  subgroups$cesarean_delivery <- quo(delivery_mode == "Cesarean delivery")
}
if ("plurality_group" %in% names(analysis_dat)) {
  subgroups$singleton_only <- quo(plurality_group == "Singleton")
  subgroups$multiple_pregnancy_only <- quo(plurality_group == "Multiple pregnancy")
}
if ("pre_delivery_anemia_hb11" %in% names(analysis_dat)) {
  subgroups$pre_delivery_anemia <- quo(pre_delivery_anemia_hb11 == "Yes")
  subgroups$no_pre_delivery_anemia <- quo(pre_delivery_anemia_hb11 == "No")
}
run_subgroup <- function(q, name) {
  d <- tryCatch(analysis_dat %>% filter(!!q), error = function(e) tibble())
  if (nrow(d) < MIN_SUBGROUP_N || !PRIMARY_EXPOSURE %in% names(d) || !has_2plus(d[[PRIMARY_EXPOSURE]])) return(tibble(subgroup = name, error = paste0("Skipped: n=", nrow(d), "; exposure levels=", ifelse(PRIMARY_EXPOSURE %in% names(d), n_distinct(d[[PRIMARY_EXPOSURE]], na.rm = TRUE), 0))))
  covs <- setdiff(model_covariates, names(select(d, where(~ !has_2plus(.x)))))
  bind_rows(
    fit_poisson_rr(d, "postpartum_anemia_hb10", PRIMARY_EXPOSURE, covs, paste0("subgroup_", name, "_RR")),
    fit_linear_beta(d, "hemoglobin_drop_g_dl", PRIMARY_EXPOSURE, covs, paste0("subgroup_", name, "_beta"))
  ) %>% mutate(subgroup = name)
}
subgroup_results <- standardize_result_table(purrr::imap_dfr(subgroups, ~ run_subgroup(.x, .y)))
safe_write_csv(subgroup_results, file.path(OUTPUT_DIR, "06_subgroup_models_all_terms.csv"))
subgroup_exposure_results <- safe_term_filter(subgroup_results, PRIMARY_EXPOSURE)
safe_write_csv(subgroup_exposure_results, file.path(OUTPUT_DIR, "06_subgroup_models_exposure_terms.csv"))

# -----------------------------
# 12. Formal interaction with delivery mode
# -----------------------------
log_step("Running formal delivery-mode interaction models")
interaction_results <- tibble()
if ("delivery_mode" %in% names(analysis_dat) && has_2plus(analysis_dat$delivery_mode)) {
  interaction_covariates <- c(
    paste0(PRIMARY_EXPOSURE, "*delivery_mode"),
    setdiff(model_covariates, "delivery_mode")
  )
  interaction_results <- bind_rows(
    fit_poisson_rr(analysis_dat, "postpartum_anemia_hb10", PRIMARY_EXPOSURE, interaction_covariates, "interaction_delivery_mode_RR"),
    fit_poisson_rr(analysis_dat, "postpartum_hemorrhage", PRIMARY_EXPOSURE, interaction_covariates, "interaction_delivery_mode_RR"),
    fit_linear_beta(analysis_dat, "hemoglobin_drop_g_dl", PRIMARY_EXPOSURE, interaction_covariates, "interaction_delivery_mode_beta")
  ) %>% standardize_result_table()
}
safe_write_csv(interaction_results, file.path(OUTPUT_DIR, "06b_delivery_mode_interaction_models_all_terms.csv"))
safe_write_csv(safe_term_filter(interaction_results, PRIMARY_EXPOSURE), file.path(OUTPUT_DIR, "06b_delivery_mode_interaction_models_exposure_terms.csv"))
interaction_product_terms <- interaction_results %>%
  standardize_result_table() %>%
  # A true interaction term contains a single ':' between two factors. Exclude the
  # namespace-qualified spline main effects 'splines::ns(...)', whose '::' otherwise
  # matches a bare ':' filter and pollutes the interaction summary and Figure 4.
  filter(!is.na(term), str_detect(term, ":"), !str_detect(term, "::"))
safe_write_csv(interaction_product_terms, file.path(OUTPUT_DIR, "06b_delivery_mode_interaction_product_terms.csv"))

subgroup_primary_summary <- subgroup_exposure_results %>%
  standardize_result_table() %>%
  filter(outcome == "postpartum_anemia_hb10") %>%
  transmute(
    row_type = "Within-subgroup adjusted RR",
    subgroup = recode(
      subgroup,
      vaginal_delivery = "Vaginal delivery",
      cesarean_delivery = "Caesarean delivery",
      singleton_only = "Singleton pregnancy",
      multiple_pregnancy_only = "Multiple pregnancy",
      pre_delivery_anemia = "Pre-delivery anaemia",
      no_pre_delivery_anemia = "No pre-delivery anaemia",
      .default = subgroup
    ),
    n = n_obs,
    events = n_events,
    estimate = estimate_exp,
    ci_low = conf_low_exp,
    ci_high = conf_high_exp,
    p_value
  )

interaction_primary_summary <- interaction_product_terms %>%
  filter(outcome == "postpartum_anemia_hb10") %>%
  transmute(
    row_type = "Formal multiplicative interaction",
    subgroup = "Delivery-mode interaction ratio",
    n = n_obs,
    events = n_events,
    estimate = estimate_exp,
    ci_low = conf_low_exp,
    ci_high = conf_high_exp,
    p_value
  )

subgroup_and_interaction_summary <- bind_rows(
  subgroup_primary_summary,
  interaction_primary_summary
)
safe_write_csv(
  subgroup_and_interaction_summary,
  file.path(OUTPUT_DIR, "06_primary_outcome_subgroup_and_interaction_summary.csv")
)

try({
  plot_subgroup <- subgroup_and_interaction_summary %>%
    filter(is.finite(estimate), is.finite(ci_low), is.finite(ci_high), ci_low > 0) %>%
    mutate(
      subgroup = factor(subgroup, levels = rev(unique(subgroup))),
      shape_group = if_else(
        row_type == "Formal multiplicative interaction",
        "Formal interaction ratio", "Within-subgroup adjusted RR"
      )
    )
  if (nrow(plot_subgroup) > 0) {
    p_subgroup <- ggplot(plot_subgroup, aes(estimate, subgroup, shape = shape_group)) +
      geom_vline(xintercept = 1, linetype = 2, colour = "grey45") +
      geom_pointrange(aes(xmin = ci_low, xmax = ci_high), linewidth = 0.48) +
      scale_x_log10() +
      scale_shape_manual(values = c("Within-subgroup adjusted RR" = 16, "Formal interaction ratio" = 18)) +
      theme_minimal(base_size = 10.5) +
      theme(legend.position = "bottom") +
      labs(x = "Risk ratio or ratio of risk ratios (95% CI), logarithmic scale", y = NULL, shape = NULL)
    ggsave(file.path(OUTPUT_DIR, "06_primary_outcome_subgroup_forest.png"), p_subgroup,
           width = 8.5, height = 5.5, dpi = 300)
    ggsave(file.path(OUTPUT_DIR, "Main_Figure_4_subgroup_forest.png"), p_subgroup,
           width = 8.5, height = 5.5, dpi = 300)
  }
}, silent = TRUE)

# -----------------------------
# 13. Sparse outcome / Firth logistic for transfusion
# -----------------------------
log_step("Running Firth logistic for sparse transfusion outcome")
firth_out <- tibble()
try({
  y <- "blood_transfusion_needed"
  d <- make_model_data(analysis_dat, y, PRIMARY_EXPOSURE, model_covariates, TRUE)
  if (nrow(d) > 0 && sum(d$outcome_numeric) > 0 && has_2plus(d$outcome_numeric)) {
    rhs <- filter_terms(c(PRIMARY_EXPOSURE, model_covariates), d)
    ff <- build_formula("outcome_numeric", rhs, d)
    fitf <- logistf::logistf(ff, data = d)
    firth_out <- tibble(term = names(coef(fitf)), estimate = as.numeric(coef(fitf)), std_error = sqrt(diag(vcov(fitf))), p_value = as.numeric(fitf$prob), conf_low = as.numeric(fitf$ci.lower), conf_high = as.numeric(fitf$ci.upper), estimate_exp = exp(estimate), conf_low_exp = exp(conf_low), conf_high_exp = exp(conf_high), model = "firth_logistic_OR", outcome = y, exposure = PRIMARY_EXPOSURE, n_obs = nrow(d), n_events = sum(d$outcome_numeric))
  }
}, silent = TRUE)
safe_write_csv(firth_out, file.path(OUTPUT_DIR, "07_firth_sparse_transfusion.csv"))

# -----------------------------
# 14. E-values for primary IPTW RR, when available
# -----------------------------
log_step("Computing E-values where possible")
manual_evalue_rr <- function(rr) {
  rr <- as.numeric(rr)
  if (!is.finite(rr) || rr <= 0) return(NA_real_)
  rr2 <- ifelse(rr < 1, 1 / rr, rr)
  rr2 + sqrt(rr2 * (rr2 - 1))
}
manual_evalue_ci <- function(rr, lo, hi) {
  rr <- as.numeric(rr); lo <- as.numeric(lo); hi <- as.numeric(hi)
  if (!is.finite(rr) || !is.finite(lo) || !is.finite(hi) || rr <= 0 || lo <= 0 || hi <= 0) return(NA_real_)
  if (lo <= 1 && hi >= 1) return(1)
  bound <- ifelse(rr >= 1, lo, hi)
  manual_evalue_rr(bound)
}
ev <- tibble()
try({
  prim <- safe_outcome_term_filter(iptw$results, "postpartum_anemia_hb10", PRIMARY_EXPOSURE) %>% slice(1)
  if (nrow(prim) == 1) {
    rr <- suppressWarnings(as.numeric(prim$estimate_exp))[1]
    if (!is.finite(rr)) rr <- suppressWarnings(as.numeric(prim$estimate))[1]
    lo <- suppressWarnings(as.numeric(prim$conf_low_exp))[1]
    if (!is.finite(lo)) lo <- suppressWarnings(as.numeric(prim$conf_low))[1]
    hi <- suppressWarnings(as.numeric(prim$conf_high_exp))[1]
    if (!is.finite(hi)) hi <- suppressWarnings(as.numeric(prim$conf_high))[1]
    ev <- tibble(
      outcome = "postpartum_anemia_hb10",
      model = "iptw_weighted_RR",
      rr = rr,
      conf_low = lo,
      conf_high = hi,
      e_value_point = manual_evalue_rr(rr),
      e_value_ci = manual_evalue_ci(rr, lo, hi),
      interpretation_note = ifelse(lo <= 1 & hi >= 1,
                                   "Confidence interval crosses the null; CI-limit E-value is 1.",
                                   "CI-limit E-value uses the confidence-limit closest to the null.")
    )
  }
}, silent = TRUE)
safe_write_csv(ev, file.path(OUTPUT_DIR, "08_evalues_primary_iptw.csv"))

# -----------------------------
# 15. Consolidated compact outputs and plots
# -----------------------------
log_step("Writing consolidated outputs")
compact <- bind_rows(
  safe_add_source(reg_all, "conventional"),
  safe_add_source(iptw$results, "iptw"),
  safe_add_source(overlap$results, "overlap"),
  safe_add_source(match_results, "matching"),
  safe_add_source(sens_all, "sensitivity"),
  safe_add_source(interaction_results, "interaction"),
  safe_add_source(firth_out, "firth")
)
safe_write_csv(compact, file.path(OUTPUT_DIR, "09_all_results_all_terms.csv"))
compact_exposure <- safe_term_filter(compact, "exposure_|cord_group_4|cord_delay_min")
safe_write_csv(compact_exposure, file.path(OUTPUT_DIR, "09_all_results_exposure_terms.csv"))

observed_binary_counts <- purrr::map_dfr(binary_outcomes, function(y) {
  analysis_dat %>%
    group_by(exposure_group = .data[[PRIMARY_EXPOSURE]]) %>%
    summarise(
      outcome = y,
      non_missing_n = sum(!is.na(.data[[y]])),
      events = sum(.data[[y]] == "Yes", na.rm = TRUE),
      percent = 100 * events / non_missing_n,
      .groups = "drop"
    )
})
safe_write_csv(observed_binary_counts, file.path(OUTPUT_DIR, "09_observed_binary_outcome_counts.csv"))

observed_continuous_summary <- purrr::map_dfr(continuous_outcomes, function(y) {
  analysis_dat %>%
    group_by(exposure_group = .data[[PRIMARY_EXPOSURE]]) %>%
    summarise(
      outcome = y,
      non_missing_n = sum(!is.na(.data[[y]])),
      mean = mean(.data[[y]], na.rm = TRUE),
      sd = sd(.data[[y]], na.rm = TRUE),
      median = median(.data[[y]], na.rm = TRUE),
      q1 = quantile(.data[[y]], 0.25, na.rm = TRUE),
      q3 = quantile(.data[[y]], 0.75, na.rm = TRUE),
      .groups = "drop"
    )
})
safe_write_csv(observed_continuous_summary, file.path(OUTPUT_DIR, "09_observed_continuous_outcome_summary.csv"))

key_method_models <- c(
  "adjusted_modified_poisson_RR", "adjusted_linear_beta",
  "iptw_weighted_RR", "iptw_weighted_beta",
  "overlap_weighted_RR", "overlap_weighted_beta",
  "matched_pair_clustered_modified_poisson_RR", "matched_pair_clustered_linear_beta"
)
cross_method_summary <- compact_exposure %>%
  standardize_result_table() %>%
  filter(
    model %in% key_method_models,
    str_detect(as.character(term), "Delayed_60s_or_more")
  ) %>%
  transmute(
    outcome,
    method = recode(
      model,
      adjusted_modified_poisson_RR = "Covariate-adjusted modified Poisson",
      adjusted_linear_beta = "Covariate-adjusted linear regression",
      iptw_weighted_RR = "Stabilised/winsorised IPTW",
      iptw_weighted_beta = "Stabilised/winsorised IPTW",
      overlap_weighted_RR = "Overlap weighting",
      overlap_weighted_beta = "Overlap weighting",
      matched_pair_clustered_modified_poisson_RR = "1:1 PS matching; pair-clustered SE",
      matched_pair_clustered_linear_beta = "1:1 PS matching; pair-clustered SE"
    ),
    estimand = case_when(
      str_detect(model, "^iptw") ~ "ATE after 1st/99th-percentile weight winsorisation",
      str_detect(model, "^overlap") ~ "ATO",
      str_detect(model, "^matched") ~ "ATT",
      TRUE ~ "Model-based adjusted association"
    ),
    effect_measure = if_else(outcome %in% binary_outcomes, "Risk ratio", "Mean difference"),
    estimate = if_else(outcome %in% binary_outcomes, coalesce(estimate_exp, estimate), estimate),
    ci_low = if_else(outcome %in% binary_outcomes, coalesce(conf_low_exp, conf_low), conf_low),
    ci_high = if_else(outcome %in% binary_outcomes, coalesce(conf_high_exp, conf_high), conf_high),
    p_value,
    n_obs,
    n_events
  )
safe_write_csv(cross_method_summary, file.path(OUTPUT_DIR, "09_cross_method_outcome_summary.csv"))

# Manuscript-ready primary outcome summary across key causal/sensitivity methods
primary_summary <- compact_exposure %>%
  standardize_result_table() %>%
  dplyr::filter(outcome == "postpartum_anemia_hb10",
                stringr::str_detect(as.character(term), "Delayed_60s_or_more"),
                model %in% c("adjusted_modified_poisson_RR", "iptw_weighted_RR", "overlap_weighted_RR", "matched_pair_clustered_modified_poisson_RR")) %>%
  dplyr::transmute(
    method = dplyr::recode(model,
                           adjusted_modified_poisson_RR = "Conventional adjusted modified Poisson",
                           iptw_weighted_RR = "Stabilised, 1st/99th percentile winsorised IPTW",
                           overlap_weighted_RR = "Overlap-weighted modified Poisson",
                           matched_pair_clustered_modified_poisson_RR = "1:1 PS matched; SE clustered by matched pair",
                           .default = model),
    outcome,
    risk_ratio = dplyr::coalesce(estimate_exp, estimate),
    ci_low = dplyr::coalesce(conf_low_exp, conf_low),
    ci_high = dplyr::coalesce(conf_high_exp, conf_high),
    p_value,
    n_obs,
    n_events
  )
safe_write_csv(primary_summary, file.path(OUTPUT_DIR, "09_primary_postpartum_anemia_summary.csv"))

try({
  for (nm in c("estimate_exp", "conf_low_exp", "conf_high_exp", "estimate", "conf.low", "conf.high", "conf_low", "conf_high", "outcome", "term", "source")) { if (!nm %in% names(compact_exposure)) compact_exposure[[nm]] <- NA }
  plot_df <- compact_exposure %>%
    filter(
      outcome %in% c("postpartum_anemia_hb10", "postpartum_hemorrhage", "blood_transfusion_needed"),
      str_detect(as.character(term), "Delayed_60s_or_more"),
      model %in% c("adjusted_modified_poisson_RR", "iptw_weighted_RR", "overlap_weighted_RR", "matched_pair_clustered_modified_poisson_RR")
    ) %>%
    mutate(
      est = coalesce(estimate_exp, estimate),
      lo = coalesce(conf_low_exp, conf_low, conf.low),
      hi = coalesce(conf_high_exp, conf_high, conf.high),
      method_label = recode(
        model,
        adjusted_modified_poisson_RR = "Covariate adjusted",
        iptw_weighted_RR = "Stabilised IPTW",
        overlap_weighted_RR = "Overlap weighted",
        matched_pair_clustered_modified_poisson_RR = "PS matched"
      ),
      outcome_label = recode(
        outcome,
        postpartum_anemia_hb10 = "Postpartum anaemia (Hb <10 g/dL)",
        postpartum_hemorrhage = "Clinically recorded PPH",
        blood_transfusion_needed = "Blood transfusion"
      ),
      label = paste(outcome_label, method_label, sep = " | ")
    ) %>%
    filter(!is.na(est), !is.na(lo), !is.na(hi), est > 0, lo > 0, hi > 0)
  if (nrow(plot_df) > 0) {
    p <- ggplot(plot_df, aes(x = est, y = fct_rev(factor(label, levels = unique(label))))) +
      geom_vline(xintercept = 1, linetype = 2, colour = "grey45") +
      geom_pointrange(aes(xmin = lo, xmax = hi), linewidth = 0.45) +
      scale_x_log10() +
      theme_minimal(base_size = 10) +
      labs(x = "Risk ratio (95% CI), logarithmic scale", y = NULL)
    ggsave(file.path(OUTPUT_DIR, "09_cross_method_forest_plot.png"), p, width = 10, height = max(5, nrow(plot_df) * .25), dpi = 300)
    ggsave(file.path(OUTPUT_DIR, "Main_Figure_3_cross_method_forest.png"), p, width = 10, height = max(5, nrow(plot_df) * .25), dpi = 300)
  }
}, silent = TRUE)

# Single compact file containing the diagnostics needed to replace manuscript
# placeholders after rerunning the confidential day-level dataset.
manuscript_diagnostics <- bind_rows(
  iptw$diagnostics %>% mutate(component = "IPTW"),
  overlap$diagnostics %>% mutate(component = "Overlap weighting"),
  match_diagnostics %>% mutate(component = "Matching")
)
safe_write_csv(manuscript_diagnostics, file.path(OUTPUT_DIR, "09_manuscript_balance_and_matching_diagnostics.csv"))

# Reproducibility metadata
write_text(capture.output(sessionInfo()), file.path(OUTPUT_DIR, "99_R_session_info.txt"))

notes <- c(
  "Cord clamping complete analysis v16.4 finished.",
  paste0("Input file: ", INPUT_FILE),
  paste0("Date resolution used: ", DATE_RESOLUTION_USED, "."),
  paste0("Primary exposure: ", PRIMARY_EXPOSURE, " (delayed >=60 seconds vs <60 seconds)."),
  "Primary outcome: postpartum anemia at 6 hours, Hb <10 g/dL.",
  paste0("Full descriptive cohort: n=", nrow(dat), "; common valid-date adjusted cohort: n=", nrow(analysis_dat), "."),
  paste0("Calendar adjustment window: ", paste(EXPECTED_DATE_RANGE, collapse = " to "), "; invalid/missing dates are excluded from calendar-adjusted models."),
  paste0("Retained covariate terms: ", paste(model_covariates, collapse = ", ")), 
  "The primary IPTW weights are stabilised and winsorised at the 1st and 99th percentiles. Balance and ESS are recalculated from those exact analysis weights.",
  "The matching analysis targets the ATT and uses sandwich standard errors clustered by MatchIt subclass (matched pair).",
  "The episode identifier is not a maternal identifier. No maternal-level clustered analysis is claimed or performed.",
  "Use 03_iptw_results_exposure_terms.csv and 09_primary_postpartum_anemia_summary.csv for the primary result; 09_manuscript_balance_and_matching_diagnostics.csv supplies the balance and matching values needed for reporting; 06b_delivery_mode_interaction_product_terms.csv contains formal interaction tests."
)
write_text(notes, file.path(OUTPUT_DIR, "10_analysis_notes_for_manuscript.txt"))
log_step(paste("Finished. Outputs written to", OUTPUT_DIR))
