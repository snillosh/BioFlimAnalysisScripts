#!/usr/bin/env Rscript

# Neutrophil phagocytosis / pHrodo analysis
#
# For RStudio use, set these two values and then source the complete script.
# Command-line --input and --output values override these settings.
INPUT_FILE <- ""
OUTPUT_DIRECTORY <- ""


# Check the R runtime and packages before reading or writing any files.
required_packages <- c(
  "readxl",
  "dplyr",
  "tidyr",
  "stringr",
  "readr",
  "tibble",
  "ggplot2",
  "rstatix",
  "ggpubr"
)


check_required_packages <- function() {
  if (getRversion() < numeric_version("4.1.0")) {
    stop("R 4.1 or later is required.", call. = FALSE)
  }

  installed <- rownames(utils::installed.packages())
  missing <- setdiff(required_packages, installed)

  if (length(missing) > 0L) {
    install_command <- sprintf(
      "install.packages(c(%s))",
      paste(sprintf('"%s"', missing), collapse = ", ")
    )
    stop(
      paste0(
        "Missing required R package(s): ",
        paste(missing, collapse = ", "),
        "\nInstall them in R with:\n",
        install_command
      ),
      call. = FALSE
    )
  }
}


# Accept either editable variables above or Windows-friendly command-line options.
parse_command_line <- function(arguments) {
  values <- list(input = NULL, output = NULL)
  index <- 1L

  while (index <= length(arguments)) {
    argument <- arguments[[index]]

    if (startsWith(argument, "--input=")) {
      values$input <- sub("^--input=", "", argument)
    } else if (startsWith(argument, "--output=")) {
      values$output <- sub("^--output=", "", argument)
    } else if (argument %in% c("--input", "--output")) {
      if (index == length(arguments)) {
        stop(sprintf("%s requires a value", argument), call. = FALSE)
      }
      index <- index + 1L
      key <- sub("^--", "", argument)
      values[[key]] <- arguments[[index]]
    } else if (argument %in% c("--help", "-h")) {
      cat(
        paste0(
          "Usage:\n",
          "  Rscript PhagocytosisAnalysis.R --input ",
          '"path/to/input.xlsx" --output "path/to/output"\n'
        )
      )
      quit(status = 0L)
    } else {
      stop(sprintf("Unrecognised command-line argument: %s", argument), call. = FALSE)
    }

    index <- index + 1L
  }

  values
}


resolve_configuration <- function() {
  command_line <- parse_command_line(commandArgs(trailingOnly = TRUE))
  input_file <- command_line$input
  output_directory <- command_line$output

  if (is.null(input_file) || !nzchar(trimws(input_file))) {
    input_file <- INPUT_FILE
  }
  if (is.null(output_directory) || !nzchar(trimws(output_directory))) {
    output_directory <- OUTPUT_DIRECTORY
  }

  if (!nzchar(trimws(input_file))) {
    stop(
      "No input workbook supplied. Set INPUT_FILE or use --input.",
      call. = FALSE
    )
  }
  if (!nzchar(trimws(output_directory))) {
    stop(
      "No output directory supplied. Set OUTPUT_DIRECTORY or use --output.",
      call. = FALSE
    )
  }
  if (!file.exists(input_file)) {
    stop(sprintf("Input workbook does not exist: %s", input_file), call. = FALSE)
  }
  if (!grepl("\\.xlsx?$", input_file, ignore.case = TRUE)) {
    stop("The input file must be an .xls or .xlsx workbook.", call. = FALSE)
  }

  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(output_directory)) {
    stop(
      sprintf("Could not create output directory: %s", output_directory),
      call. = FALSE
    )
  }

  list(
    input = normalizePath(input_file, winslash = "/", mustWork = TRUE),
    output = normalizePath(output_directory, winslash = "/", mustWork = TRUE)
  )
}


# Read and validate the two measurement sheets, then average technical rows.
normalise_header <- function(value) {
  value |>
    as.character() |>
    stringr::str_squish() |>
    stringr::str_to_lower()
}


find_required_sheet <- function(sheet_names, required_name) {
  matches <- which(normalise_header(sheet_names) == normalise_header(required_name))

  if (length(matches) != 1L) {
    stop(
      sprintf(
        "Expected exactly one '%s' sheet, found %d.",
        required_name,
        length(matches)
      ),
      call. = FALSE
    )
  }

  sheet_names[[matches]]
}


coerce_excel_date <- function(values) {
  if (inherits(values, "Date")) {
    return(values)
  }
  if (inherits(values, "POSIXt")) {
    return(as.Date(values))
  }
  if (is.numeric(values)) {
    return(as.Date(values, origin = "1899-12-30"))
  }

  text <- trimws(as.character(values))
  result <- as.Date(rep(NA_character_, length(text)))
  formats <- c("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y")

  for (date_format in formats) {
    missing <- is.na(result) & nzchar(text)
    result[missing] <- as.Date(text[missing], format = date_format)
  }

  result
}


read_measurement_sheet <- function(input_file, sheet_name, measurement_name) {
  sheet <- readxl::read_excel(
    input_file,
    sheet = sheet_name,
    .name_repair = "minimal"
  )

  names(sheet) <- stringr::str_squish(names(sheet))
  header_keys <- normalise_header(names(sheet))

  if (any(is.na(header_keys) | !nzchar(header_keys))) {
    stop(sprintf("Sheet '%s' contains an empty column heading.", sheet_name), call. = FALSE)
  }
  if (anyDuplicated(header_keys)) {
    duplicates <- unique(names(sheet)[duplicated(header_keys)])
    stop(
      sprintf(
        "Sheet '%s' contains duplicate headings: %s",
        sheet_name,
        paste(duplicates, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  date_column <- which(header_keys == "date")
  if (length(date_column) != 1L) {
    stop(
      sprintf("Sheet '%s' must contain exactly one Date column.", sheet_name),
      call. = FALSE
    )
  }
  names(sheet)[date_column] <- "Date"

  original_dates <- sheet$Date
  sheet$Date <- coerce_excel_date(original_dates)
  invalid_date_rows <- which(
    !is.na(original_dates) &
      nzchar(trimws(as.character(original_dates))) &
      is.na(sheet$Date)
  )
  if (length(invalid_date_rows) > 0L) {
    stop(
      sprintf(
        "Sheet '%s' contains unreadable dates on Excel row(s): %s",
        sheet_name,
        paste(invalid_date_rows + 1L, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  sheet$.source_row <- seq_len(nrow(sheet)) + 1L

  long <- sheet |>
    tidyr::pivot_longer(
      cols = -c("Date", ".source_row"),
      names_to = "SampleName",
      values_to = "RawValue",
      values_transform = list(RawValue = as.character)
    ) |>
    dplyr::mutate(
      SampleName = stringr::str_squish(.data$SampleName),
      Value = suppressWarnings(as.numeric(.data$RawValue)),
      HasRawValue = !is.na(.data$RawValue) & nzchar(trimws(.data$RawValue)),
      Measurement = measurement_name,
      Sheet = sheet_name
    )

  invalid_values <- dplyr::bind_rows(
    long |>
      dplyr::filter(
        .data$HasRawValue,
        is.na(.data$Value) | !is.finite(.data$Value)
      ) |>
      dplyr::transmute(
        Sheet = .data$Sheet,
        ExcelRow = .data$.source_row,
        Date = .data$Date,
        SampleName = .data$SampleName,
        RawValue = .data$RawValue,
        Reason = dplyr::if_else(
          is.na(.data$Value),
          "Measurement is not numeric",
          "Measurement is not finite"
        )
      ),
    long |>
      dplyr::filter(.data$HasRawValue, is.na(.data$Date)) |>
      dplyr::transmute(
        Sheet = .data$Sheet,
        ExcelRow = .data$.source_row,
        Date = .data$Date,
        SampleName = .data$SampleName,
        RawValue = .data$RawValue,
        Reason = "Date is missing"
      )
  )

  long <- long |>
    dplyr::mutate(
      Value = dplyr::if_else(is.finite(.data$Value), .data$Value, NA_real_)
    )

  aggregated <- long |>
    dplyr::filter(!is.na(.data$Date)) |>
    dplyr::group_by(.data$Date, .data$SampleName) |>
    dplyr::summarise(
      Value = if (all(is.na(.data$Value))) NA_real_ else mean(.data$Value, na.rm = TRUE),
      TechnicalReplicates = sum(!is.na(.data$Value)),
      .groups = "drop"
    )

  list(data = aggregated, invalid_values = invalid_values)
}


# Convert sample headings into analysis time points and display labels.
classify_samples <- function(data) {
  classified <- data |>
    dplyr::mutate(
      NormalisedName = .data$SampleName |>
        stringr::str_to_lower() |>
        stringr::str_replace_all("[_-]+", " ") |>
        stringr::str_squish(),
      Time = dplyr::case_when(
        stringr::str_detect(.data$NormalisedName, "(^| )30\\s*min( |$)") ~ "30 min",
        stringr::str_detect(.data$NormalisedName, "(^| )3\\s*h( |$)") ~ "3 h",
        .data$NormalisedName == "cold" ~ "Both",
        TRUE ~ NA_character_
      ),
      ConditionKey = .data$NormalisedName |>
        stringr::str_replace_all("(^| )30\\s*min( |$)", " ") |>
        stringr::str_replace_all("(^| )3\\s*h( |$)", " ") |>
        stringr::str_squish(),
      TreatmentCode = dplyr::case_when(
        .data$ConditionKey %in% c("ut", "untreated") ~ "UT",
        .data$ConditionKey == "vehicle" ~ "Vehicle",
        .data$ConditionKey %in% c("ebc 4", "ebc4") ~ "EBC 4",
        .data$ConditionKey %in% c("ebc 8", "ebc8") ~ "EBC 8",
        .data$ConditionKey == "ebc" ~ "EBC",
        .data$ConditionKey == "pma" ~ "PMA",
        .data$ConditionKey == "cold" ~ "Cold",
        .data$ConditionKey %in% c("neut alone", "neutrophils alone") ~ "Neut alone",
        TRUE ~ NA_character_
      ),
      Treatment = dplyr::case_when(
        .data$TreatmentCode == "UT" ~ "Untreated",
        .data$TreatmentCode == "Vehicle" ~ "Vehicle",
        .data$TreatmentCode == "EBC 4" ~ "EBC (4 \u00B5g/mL)",
        .data$TreatmentCode == "EBC 8" ~ "EBC (8 \u00B5g/mL)",
        .data$TreatmentCode == "EBC" ~ "EBC (256 \u00B5g/mL)",
        .data$TreatmentCode == "PMA" ~ "PMA",
        .data$TreatmentCode == "Cold" ~ "Cold",
        .data$TreatmentCode == "Neut alone" ~ "Neut alone",
        TRUE ~ NA_character_
      ),
      ClassificationStatus = dplyr::case_when(
        .data$TreatmentCode == "Neut alone" ~ "Excluded by analysis plan",
        is.na(.data$TreatmentCode) & is.na(.data$Time) ~
          "Treatment and time point were not recognised",
        is.na(.data$TreatmentCode) ~ "Treatment was not recognised",
        is.na(.data$Time) ~ "Time point was not recognised",
        TRUE ~ "Included"
      )
    )

  cold_without_time <- classified |>
    dplyr::filter(.data$TreatmentCode == "Cold", .data$Time == "Both")
  classified_without_shared_cold <- classified |>
    dplyr::filter(!(.data$TreatmentCode == "Cold" & .data$Time == "Both"))

  dplyr::bind_rows(
    classified_without_shared_cold,
    cold_without_time |> dplyr::mutate(Time = "30 min"),
    cold_without_time |> dplyr::mutate(Time = "3 h")
  )
}


prepare_analysis_data <- function(input_file) {
  sheet_names <- readxl::excel_sheets(input_file)
  median_sheet <- find_required_sheet(sheet_names, "Median 2")
  frequency_sheet <- find_required_sheet(sheet_names, "Frequency")

  median <- read_measurement_sheet(
    input_file,
    median_sheet,
    "Median pHrodo intensity"
  )
  frequency <- read_measurement_sheet(
    input_file,
    frequency_sheet,
    "% pHrodo-positive neutrophils"
  )

  combined <- dplyr::full_join(
    median$data |>
      dplyr::rename(
        MedianValue = Value,
        MedianTechnicalReplicates = TechnicalReplicates
      ),
    frequency$data |>
      dplyr::rename(
        FrequencyValue = Value,
        FrequencyTechnicalReplicates = TechnicalReplicates
      ),
    by = c("Date", "SampleName")
  ) |>
    classify_samples()

  unmatched <- combined |>
    dplyr::filter(
      .data$ClassificationStatus != "Excluded by analysis plan",
      is.na(.data$TreatmentCode) | is.na(.data$Time)
    ) |>
    dplyr::select(
      Date,
      SampleName,
      MedianValue,
      FrequencyValue,
      Reason = ClassificationStatus
    )

  excluded <- combined |>
    dplyr::filter(.data$TreatmentCode == "Neut alone") |>
    dplyr::select(
      Date,
      SampleName,
      MedianValue,
      FrequencyValue,
      Reason = ClassificationStatus
    )

  mismatches <- combined |>
    dplyr::filter(
      .data$ClassificationStatus == "Included",
      is.na(.data$MedianValue) | is.na(.data$FrequencyValue)
    ) |>
    dplyr::transmute(
      Date = .data$Date,
      Time = .data$Time,
      Treatment = .data$Treatment,
      SampleName = .data$SampleName,
      MissingMeasurement = dplyr::case_when(
        is.na(.data$MedianValue) & is.na(.data$FrequencyValue) ~ "Both measurements",
        is.na(.data$MedianValue) ~ "Median pHrodo intensity",
        TRUE ~ "% pHrodo-positive neutrophils"
      )
    )

  ambiguities <- combined |>
    dplyr::filter(.data$ClassificationStatus == "Included") |>
    dplyr::group_by(.data$Date, .data$Time, .data$Treatment) |>
    dplyr::filter(dplyr::n() > 1L) |>
    dplyr::summarise(
      SampleNames = paste(sort(unique(.data$SampleName)), collapse = "; "),
      Reason = "More than one sample column maps to this treatment and time point",
      .groups = "drop"
    )

  tidy <- combined |>
    dplyr::filter(.data$ClassificationStatus == "Included") |>
    tidyr::pivot_longer(
      cols = c("MedianValue", "FrequencyValue"),
      names_to = "MeasurementKey",
      values_to = "Value"
    ) |>
    dplyr::mutate(
      Measurement = dplyr::case_when(
        .data$MeasurementKey == "MedianValue" ~ "Median pHrodo intensity",
        TRUE ~ "% pHrodo-positive neutrophils"
      ),
      TechnicalReplicates = dplyr::case_when(
        .data$MeasurementKey == "MedianValue" ~ .data$MedianTechnicalReplicates,
        TRUE ~ .data$FrequencyTechnicalReplicates
      )
    ) |>
    dplyr::filter(!is.na(.data$Value)) |>
    dplyr::select(
      Date,
      Time,
      Treatment,
      TreatmentCode,
      SampleName,
      Measurement,
      Value,
      TechnicalReplicates
    ) |>
    dplyr::arrange(.data$Measurement, .data$Time, .data$Date, .data$Treatment)

  invalid_values <- dplyr::bind_rows(
    median$invalid_values,
    frequency$invalid_values
  )

  list(
    tidy = tidy,
    unmatched = unmatched,
    excluded = excluded,
    mismatches = mismatches,
    ambiguities = ambiguities,
    invalid_values = invalid_values
  )
}


treatment_order <- function(treatments) {
  preferred <- c(
    "Untreated",
    "Vehicle",
    "EBC (4 \u00B5g/mL)",
    "EBC (8 \u00B5g/mL)",
    "EBC (256 \u00B5g/mL)",
    "PMA",
    "Cold"
  )
  treatments <- unique(as.character(treatments))
  c(intersect(preferred, treatments), sort(setdiff(treatments, preferred)))
}


# Normality and statistical helpers retain Date as the matched biological unit.
significance_label <- function(p_value) {
  if (is.na(p_value)) {
    return(NA_character_)
  }
  if (p_value < 0.0001) {
    return("****")
  }
  if (p_value < 0.001) {
    return("***")
  }
  if (p_value < 0.01) {
    return("**")
  }
  if (p_value < 0.05) {
    return("*")
  }
  "ns"
}


safe_shapiro <- function(values) {
  values <- values[is.finite(values)]
  result <- list(
    n = length(values),
    statistic = NA_real_,
    p_value = NA_real_,
    compatible = NA,
    notes = ""
  )

  if (length(values) < 3L) {
    result$notes <- "Shapiro-Wilk requires at least three values"
    return(result)
  }
  if (length(values) > 5000L) {
    result$notes <- "Shapiro-Wilk supports at most 5000 values"
    return(result)
  }
  if (length(unique(values)) < 2L) {
    result$notes <- "All assessed values are identical"
    return(result)
  }

  test <- tryCatch(
    stats::shapiro.test(values),
    error = function(error) error
  )
  if (inherits(test, "error")) {
    result$notes <- conditionMessage(test)
    return(result)
  }

  result$statistic <- unname(test$statistic)
  result$p_value <- test$p.value
  result$compatible <- test$p.value >= 0.05
  result
}


normality_record <- function(
    measurement,
    time_point,
    scope,
    shapiro,
    selected_test) {
  tibble::tibble(
    Measurement = measurement,
    Time = time_point,
    Scope = scope,
    NormalityTest = "Shapiro-Wilk",
    NValuesAssessed = shapiro$n,
    W = shapiro$statistic,
    PValue = shapiro$p_value,
    CompatibleWithNormality = shapiro$compatible,
    SelectedTest = selected_test,
    Notes = shapiro$notes
  )
}


empty_normality_results <- function() {
  tibble::tibble(
    Measurement = character(),
    Time = character(),
    Scope = character(),
    NormalityTest = character(),
    NValuesAssessed = integer(),
    W = double(),
    PValue = double(),
    CompatibleWithNormality = logical(),
    SelectedTest = character(),
    Notes = character()
  )
}


empty_assumption_results <- function() {
  tibble::tibble(
    Measurement = character(),
    Time = character(),
    Check = character(),
    Details = character()
  )
}


empty_qq_values <- function() {
  tibble::tibble(
    Scope = character(),
    Value = double()
  )
}


empty_scope_exclusions <- function() {
  tibble::tibble(
    Date = as.Date(character()),
    Scope = character(),
    Reason = character()
  )
}


empty_analysis_exclusions <- function() {
  tibble::tibble(
    Measurement = character(),
    Time = character(),
    Date = as.Date(character()),
    Scope = character(),
    Reason = character()
  )
}


complete_repeated_measures_data <- function(data, treatments) {
  coverage <- data |>
    dplyr::distinct(.data$Date, .data$Treatment) |>
    dplyr::count(.data$Date, name = "TreatmentCount")
  complete_dates <- coverage |>
    dplyr::filter(.data$TreatmentCount == length(treatments)) |>
    dplyr::pull("Date")

  complete <- data |>
    dplyr::filter(.data$Date %in% complete_dates) |>
    dplyr::mutate(
      Date = factor(.data$Date),
      Treatment = factor(.data$Treatment, levels = treatments)
    )

  all_dates <- sort(unique(data$Date))
  incomplete_dates <- all_dates[!all_dates %in% complete_dates]
  exclusions <- lapply(incomplete_dates, function(excluded_date) {
    present <- data |>
      dplyr::filter(.data$Date == excluded_date) |>
      dplyr::pull("Treatment") |>
      as.character()
    missing <- setdiff(treatments, present)
    tibble::tibble(
      Date = excluded_date,
      Scope = "Overall repeated-measures test",
      Reason = paste("Missing treatment(s):", paste(missing, collapse = ", "))
    )
  })

  list(
    data = complete,
    dates = complete_dates,
    exclusions = if (length(exclusions) > 0L) {
      dplyr::bind_rows(exclusions)
    } else {
      empty_scope_exclusions()
    }
  )
}


empty_statistical_results <- function() {
  tibble::tibble(
    Measurement = character(),
    Time = character(),
    Comparison = character(),
    StatisticalTest = character(),
    TestStatistic = double(),
    DF1 = double(),
    DF2 = double(),
    NBiologicalReplicates = integer(),
    PValue = double(),
    AdjustedPValue = double(),
    Significance = character(),
    Group1 = character(),
    Group2 = character(),
    Notes = character()
  )
}


extract_anova_assumptions <- function(test, measurement, time_point) {
  component_names <- names(test)
  wanted <- grep(
    "Mauchly|Sphericity Corrections",
    component_names,
    ignore.case = TRUE,
    value = TRUE
  )

  if (length(wanted) == 0L) {
    return(empty_assumption_results())
  }

  dplyr::bind_rows(lapply(wanted, function(component_name) {
    details <- paste(capture.output(print(test[[component_name]])), collapse = " | ")
    tibble::tibble(
      Measurement = measurement,
      Time = time_point,
      Check = component_name,
      Details = details
    )
  }))
}


table_value <- function(data, column_name) {
  if (nrow(data) == 0L || !column_name %in% names(data)) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(data[[column_name]][[1L]]))
}


run_overall_test <- function(
    complete_data,
    measurement,
    time_point,
    use_parametric) {
  n_dates <- dplyr::n_distinct(complete_data$Date)

  if (n_dates < 3L) {
    result <- empty_statistical_results() |>
      tibble::add_row(
        Measurement = measurement,
        Time = time_point,
        Comparison = "Overall treatment effect",
        StatisticalTest = "Not performed",
        NBiologicalReplicates = n_dates,
        Notes = "Fewer than three complete biological replicates"
      )
    return(list(result = result, assumptions = empty_assumption_results()))
  }

  if (use_parametric) {
    test <- tryCatch(
      rstatix::anova_test(
        data = complete_data,
        dv = Value,
        wid = Date,
        within = Treatment,
        effect.size = "ges",
        detailed = TRUE
      ),
      error = function(error) error
    )

    if (inherits(test, "error")) {
      result <- empty_statistical_results() |>
        tibble::add_row(
          Measurement = measurement,
          Time = time_point,
          Comparison = "Overall treatment effect",
          StatisticalTest = "Repeated-measures ANOVA failed",
          NBiologicalReplicates = n_dates,
          Notes = conditionMessage(test)
        )
      return(list(result = result, assumptions = empty_assumption_results()))
    }

    table <- rstatix::get_anova_table(test, correction = "auto")
    treatment_row <- table |>
      dplyr::filter(.data$Effect == "Treatment") |>
      dplyr::slice(1L)
    if (nrow(treatment_row) == 0L) {
      treatment_row <- table |> dplyr::slice(1L)
    }

    p_value <- table_value(treatment_row, "p")
    result <- empty_statistical_results() |>
      tibble::add_row(
        Measurement = measurement,
        Time = time_point,
        Comparison = "Overall treatment effect",
        StatisticalTest = "Repeated-measures ANOVA",
        TestStatistic = table_value(treatment_row, "F"),
        DF1 = table_value(treatment_row, "DFn"),
        DF2 = table_value(treatment_row, "DFd"),
        NBiologicalReplicates = n_dates,
        PValue = p_value,
        Significance = significance_label(p_value),
        Notes = "Sphericity correction selected automatically when required"
      )
    assumptions <- extract_anova_assumptions(test, measurement, time_point)
    return(list(result = result, assumptions = assumptions))
  }

  test <- tryCatch(
    rstatix::friedman_test(complete_data, Value ~ Treatment | Date),
    error = function(error) error
  )
  if (inherits(test, "error")) {
    result <- empty_statistical_results() |>
      tibble::add_row(
        Measurement = measurement,
        Time = time_point,
        Comparison = "Overall treatment effect",
        StatisticalTest = "Friedman test failed",
        NBiologicalReplicates = n_dates,
        Notes = conditionMessage(test)
      )
    return(list(result = result, assumptions = empty_assumption_results()))
  }

  p_value <- test$p[[1L]]
  result <- empty_statistical_results() |>
    tibble::add_row(
      Measurement = measurement,
      Time = time_point,
      Comparison = "Overall treatment effect",
      StatisticalTest = "Friedman test",
      TestStatistic = test$statistic[[1L]],
      DF1 = test$df[[1L]],
      NBiologicalReplicates = n_dates,
      PValue = p_value,
      Significance = significance_label(p_value)
    )
  list(result = result, assumptions = empty_assumption_results())
}


pair_values_with_untreated <- function(data, treatment) {
  untreated <- data |>
    dplyr::filter(.data$Treatment == "Untreated") |>
    dplyr::select(Date, UntreatedValue = Value)
  comparison <- data |>
    dplyr::filter(.data$Treatment == treatment) |>
    dplyr::select(Date, ComparisonValue = Value)

  dplyr::inner_join(untreated, comparison, by = "Date") |>
    dplyr::mutate(Difference = .data$ComparisonValue - .data$UntreatedValue)
}


run_pairwise_tests <- function(data, treatments, measurement, time_point) {
  comparison_groups <- setdiff(treatments, "Untreated")
  results <- list()
  normality <- list()
  qq_values <- list()
  exclusions <- list()

  if (!"Untreated" %in% treatments) {
    result <- empty_statistical_results() |>
      tibble::add_row(
        Measurement = measurement,
        Time = time_point,
        Comparison = "Treatment comparisons with Untreated",
        StatisticalTest = "Not performed",
        NBiologicalReplicates = dplyr::n_distinct(data$Date),
        Notes = "Untreated group is absent"
      )
    return(list(
      results = result,
      normality = empty_normality_results(),
      qq_values = empty_qq_values(),
      exclusions = empty_scope_exclusions()
    ))
  }

  all_dates <- sort(unique(data$Date))

  for (comparison_group in comparison_groups) {
    pairs <- pair_values_with_untreated(data, comparison_group)
    scope <- paste(comparison_group, "vs Untreated paired differences")
    shapiro <- safe_shapiro(pairs$Difference)
    use_parametric <- isTRUE(shapiro$compatible)
    selected_test <- if (use_parametric) {
      "Paired t-test"
    } else {
      "Wilcoxon signed-rank test"
    }

    normality[[length(normality) + 1L]] <- normality_record(
      measurement,
      time_point,
      scope,
      shapiro,
      selected_test
    )
    if (nrow(pairs) > 0L) {
      qq_values[[length(qq_values) + 1L]] <- tibble::tibble(
        Scope = scope,
        Value = pairs$Difference
      )
    }

    excluded_dates <- all_dates[!all_dates %in% pairs$Date]
    if (length(excluded_dates) > 0L) {
      exclusions[[length(exclusions) + 1L]] <- tibble::tibble(
        Date = excluded_dates,
        Scope = paste(comparison_group, "vs Untreated"),
        Reason = "One or both paired treatment values are missing"
      )
    }

    test_statistic <- NA_real_
    degrees_freedom <- NA_real_
    p_value <- NA_real_
    notes <- ""

    if (nrow(pairs) < 2L) {
      notes <- "Fewer than two matched biological replicates"
    } else if (use_parametric) {
      test <- tryCatch(
        stats::t.test(
          pairs$ComparisonValue,
          pairs$UntreatedValue,
          paired = TRUE,
          alternative = "two.sided"
        ),
        error = function(error) error
      )
      if (inherits(test, "error")) {
        notes <- conditionMessage(test)
      } else {
        test_statistic <- unname(test$statistic)
        degrees_freedom <- unname(test$parameter)
        p_value <- test$p.value
      }
    } else {
      test <- tryCatch(
        stats::wilcox.test(
          pairs$ComparisonValue,
          pairs$UntreatedValue,
          paired = TRUE,
          alternative = "two.sided",
          exact = FALSE
        ),
        error = function(error) error
      )
      if (inherits(test, "error")) {
        notes <- conditionMessage(test)
      } else {
        test_statistic <- unname(test$statistic)
        p_value <- test$p.value
      }
    }

    results[[length(results) + 1L]] <- empty_statistical_results() |>
      tibble::add_row(
        Measurement = measurement,
        Time = time_point,
        Comparison = paste(comparison_group, "vs Untreated"),
        StatisticalTest = selected_test,
        TestStatistic = test_statistic,
        DF1 = degrees_freedom,
        NBiologicalReplicates = nrow(pairs),
        PValue = p_value,
        Group1 = "Untreated",
        Group2 = comparison_group,
        Notes = notes
      )
  }

  result_table <- dplyr::bind_rows(results)
  result_table$AdjustedPValue <- NA_real_
  valid_p_values <- which(!is.na(result_table$PValue))
  result_table$AdjustedPValue[valid_p_values] <- stats::p.adjust(
    result_table$PValue[valid_p_values],
    method = "holm"
  )
  result_table$Significance <- vapply(
    result_table$AdjustedPValue,
    significance_label,
    character(1L)
  )

  list(
    results = result_table,
    normality = if (length(normality) > 0L) {
      dplyr::bind_rows(normality)
    } else {
      empty_normality_results()
    },
    qq_values = if (length(qq_values) > 0L) {
      dplyr::bind_rows(qq_values)
    } else {
      empty_qq_values()
    },
    exclusions = if (length(exclusions) > 0L) {
      dplyr::bind_rows(exclusions)
    } else {
      empty_scope_exclusions()
    }
  )
}


# Main plots show individual Dates, within-Date connections, and summaries.
summary_values <- function(data, use_parametric) {
  data |>
    dplyr::group_by(.data$Treatment) |>
    dplyr::summarise(
      Centre = if (use_parametric) mean(.data$Value) else stats::median(.data$Value),
      Lower = if (use_parametric) {
        mean(.data$Value) - stats::sd(.data$Value)
      } else {
        stats::quantile(.data$Value, 0.25, names = FALSE)
      },
      Upper = if (use_parametric) {
        mean(.data$Value) + stats::sd(.data$Value)
      } else {
        stats::quantile(.data$Value, 0.75, names = FALSE)
      },
      .groups = "drop"
    ) |>
    dplyr::mutate(Lower = pmax(0, .data$Lower))
}


create_empty_plot <- function(measurement, time_point, reason) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 0, label = reason) +
    ggplot2::theme_void() +
    ggplot2::labs(title = paste(time_point, "\u2014", measurement))
}


create_analysis_plot <- function(
    data,
    measurement,
    time_point,
    use_parametric,
    pairwise_results) {
  treatments <- treatment_order(data$Treatment)
  data <- data |>
    dplyr::mutate(Treatment = factor(.data$Treatment, levels = treatments))
  summaries <- summary_values(data, use_parametric) |>
    dplyr::mutate(Treatment = factor(.data$Treatment, levels = treatments))

  summary_description <- if (use_parametric) "Mean \u00B1 SD" else "Median and IQR"
  plot <- ggplot2::ggplot(
    data,
    ggplot2::aes(x = .data$Treatment, y = .data$Value)
  ) +
    ggplot2::geom_line(
      ggplot2::aes(group = .data$Date),
      colour = "#A6A6A6",
      linewidth = 0.45,
      alpha = 0.65,
      na.rm = TRUE
    ) +
    ggplot2::geom_point(
      ggplot2::aes(colour = .data$Treatment),
      size = 2.6,
      alpha = 0.9,
      na.rm = TRUE
    ) +
    ggplot2::geom_errorbar(
      data = summaries,
      ggplot2::aes(
        x = .data$Treatment,
        ymin = .data$Lower,
        ymax = .data$Upper
      ),
      width = 0.13,
      linewidth = 0.8,
      colour = "black",
      inherit.aes = FALSE,
      na.rm = TRUE
    ) +
    ggplot2::geom_point(
      data = summaries,
      ggplot2::aes(x = .data$Treatment, y = .data$Centre),
      shape = 18,
      size = 3.8,
      colour = "black",
      inherit.aes = FALSE
    ) +
    ggplot2::scale_colour_brewer(palette = "Dark2", drop = FALSE) +
    ggplot2::expand_limits(y = 0) +
    ggplot2::labs(
      title = paste(time_point, "\u2014", measurement),
      subtitle = paste("Points are biological replicates;", summary_description),
      x = NULL,
      y = measurement
    ) +
    ggplot2::theme_classic(base_size = 12, base_family = "sans") +
    ggplot2::theme(
      legend.position = "none",
      axis.text.x = ggplot2::element_text(angle = 25, hjust = 1),
      plot.title = ggplot2::element_text(face = "bold"),
      plot.margin = ggplot2::margin(10, 18, 10, 10)
    )

  significant <- pairwise_results |>
    dplyr::filter(!is.na(.data$AdjustedPValue), .data$AdjustedPValue < 0.05)
  if (nrow(significant) > 0L) {
    data_range <- range(data$Value, na.rm = TRUE)
    step <- diff(data_range) * 0.12
    if (!is.finite(step) || step <= 0) {
      step <- max(abs(data_range), 1) * 0.12
    }
    significant <- significant |>
      dplyr::arrange(.data$AdjustedPValue) |>
      dplyr::mutate(
        y.position = max(data$Value, na.rm = TRUE) + dplyr::row_number() * step,
        group1 = .data$Group1,
        group2 = .data$Group2,
        label = .data$Significance
      )
    plot <- plot + ggpubr::stat_pvalue_manual(
      significant,
      label = "label",
      xmin = "group1",
      xmax = "group2",
      y.position = "y.position",
      tip.length = 0.01,
      bracket.size = 0.35,
      hide.ns = TRUE
    )
  }

  plot + ggplot2::coord_cartesian(clip = "off")
}


create_qq_plot <- function(values, measurement, time_point) {
  if (nrow(values) == 0L) {
    return(
      ggplot2::ggplot() +
        ggplot2::annotate("text", x = 0, y = 0, label = "Insufficient data") +
        ggplot2::theme_void() +
        ggplot2::labs(title = paste(time_point, "\u2014", measurement, "normality"))
    )
  }

  ggplot2::ggplot(values, ggplot2::aes(sample = .data$Value)) +
    ggplot2::stat_qq(size = 1.7, colour = "#1F4E78") +
    ggplot2::stat_qq_line(linewidth = 0.6, colour = "#7F7F7F") +
    ggplot2::facet_wrap(~ Scope, scales = "free") +
    ggplot2::labs(
      title = paste(time_point, "\u2014", measurement, "normality"),
      x = "Theoretical quantiles",
      y = "Observed quantiles"
    ) +
    ggplot2::theme_classic(base_size = 11, base_family = "sans") +
    ggplot2::theme(strip.text = ggplot2::element_text(size = 9))
}


not_performed_result <- function(measurement, time_point, reason, n_dates = 0L) {
  empty_statistical_results() |>
    tibble::add_row(
      Measurement = measurement,
      Time = time_point,
      Comparison = "Overall treatment effect",
      StatisticalTest = "Not performed",
      NBiologicalReplicates = n_dates,
      Notes = reason
    )
}


analyse_combination <- function(tidy_data, measurement, time_point) {
  data <- tidy_data |>
    dplyr::filter(
      .data$Measurement == measurement,
      .data$Time == time_point,
      is.finite(.data$Value)
    ) |>
    dplyr::select(Date, Treatment, Value)

  treatments <- treatment_order(data$Treatment)
  data <- data |>
    dplyr::mutate(Treatment = factor(.data$Treatment, levels = treatments))

  if (nrow(data) == 0L) {
    return(list(
      statistics = not_performed_result(
        measurement,
        time_point,
        "No analysable values"
      ),
      normality = empty_normality_results(),
      assumptions = empty_assumption_results(),
      exclusions = empty_analysis_exclusions(),
      plot = create_empty_plot(measurement, time_point, "No analysable values"),
      qq_plot = create_qq_plot(empty_qq_values(), measurement, time_point)
    ))
  }

  if (length(treatments) < 2L) {
    return(list(
      statistics = not_performed_result(
        measurement,
        time_point,
        "Fewer than two recognised treatment groups",
        dplyr::n_distinct(data$Date)
      ),
      normality = empty_normality_results(),
      assumptions = empty_assumption_results(),
      exclusions = empty_analysis_exclusions(),
      plot = create_analysis_plot(
        data,
        measurement,
        time_point,
        FALSE,
        empty_statistical_results()
      ),
      qq_plot = create_qq_plot(empty_qq_values(), measurement, time_point)
    ))
  }

  complete <- complete_repeated_measures_data(data, treatments)
  if (length(treatments) > 2L) {
    residual_values <- numeric()
    if (nrow(complete$data) > 0L) {
      residual_model <- tryCatch(
        stats::lm(Value ~ Treatment + Date, data = complete$data),
        error = function(error) NULL
      )
      if (!is.null(residual_model)) {
        residual_values <- stats::residuals(residual_model)
      }
    }

    overall_shapiro <- safe_shapiro(residual_values)
    overall_parametric <- isTRUE(overall_shapiro$compatible)
    overall_selected_test <- if (overall_parametric) {
      "Repeated-measures ANOVA"
    } else {
      "Friedman test"
    }
    normality <- normality_record(
      measurement,
      time_point,
      "Overall repeated-measures model residuals",
      overall_shapiro,
      overall_selected_test
    )
    qq_values <- if (length(residual_values) > 0L) {
      tibble::tibble(
        Scope = "Overall repeated-measures model residuals",
        Value = residual_values
      )
    } else {
      empty_qq_values()
    }

    overall <- run_overall_test(
      complete$data,
      measurement,
      time_point,
      overall_parametric
    )
    overall_exclusions <- complete$exclusions |>
      dplyr::mutate(Measurement = measurement, Time = time_point, .before = 1L)
  } else {
    overall_parametric <- FALSE
    normality <- empty_normality_results()
    qq_values <- empty_qq_values()
    overall <- list(
      result = empty_statistical_results(),
      assumptions = empty_assumption_results()
    )
    overall_exclusions <- empty_analysis_exclusions()
  }

  pairwise <- run_pairwise_tests(data, treatments, measurement, time_point)
  normality <- dplyr::bind_rows(normality, pairwise$normality)
  qq_values <- dplyr::bind_rows(qq_values, pairwise$qq_values)

  pairwise_exclusions <- pairwise$exclusions |>
    dplyr::mutate(Measurement = measurement, Time = time_point, .before = 1L)
  plot_parametric <- if (length(treatments) == 2L) {
    nrow(pairwise$results) == 1L &&
      pairwise$results$StatisticalTest[[1L]] == "Paired t-test"
  } else {
    overall_parametric
  }

  list(
    statistics = dplyr::bind_rows(overall$result, pairwise$results),
    normality = normality,
    assumptions = overall$assumptions,
    exclusions = dplyr::bind_rows(overall_exclusions, pairwise_exclusions),
    plot = create_analysis_plot(
      data,
      measurement,
      time_point,
      plot_parametric,
      pairwise$results
    ),
    qq_plot = create_qq_plot(qq_values, measurement, time_point)
  )
}


# Save inspectable tables, high-resolution plots, and reproducibility metadata.
file_slug <- function(time_point, measurement) {
  time_slug <- if (time_point == "30 min") "30_min" else "3_h"
  measurement_slug <- if (measurement == "Median pHrodo intensity") {
    "median_phrodo_intensity"
  } else {
    "percent_phrodo_positive_neutrophils"
  }
  paste(time_slug, measurement_slug, sep = "_")
}


save_plot_pair <- function(plot, output_directory, stem, width = 8.5, height = 6.2) {
  ggplot2::ggsave(
    filename = file.path(output_directory, paste0(stem, ".png")),
    plot = plot,
    width = width,
    height = height,
    units = "in",
    dpi = 600,
    bg = "white"
  )
  ggplot2::ggsave(
    filename = file.path(output_directory, paste0(stem, ".pdf")),
    plot = plot,
    width = width,
    height = height,
    units = "in",
    bg = "white"
  )
}


write_output_table <- function(data, output_directory, filename) {
  readr::write_excel_csv(
    data,
    file.path(output_directory, filename),
    na = ""
  )
}


report_issue_count <- function(data, label) {
  if (nrow(data) > 0L) {
    warning(sprintf("%s: %d row(s). See the corresponding output CSV.", label, nrow(data)))
  } else {
    message(sprintf("%s: 0", label))
  }
}


main <- function() {
  check_required_packages()
  configuration <- resolve_configuration()

  message("Reading workbook: ", configuration$input)
  prepared <- prepare_analysis_data(configuration$input)

  write_output_table(
    prepared$tidy,
    configuration$output,
    "cleaned_tidy_data.csv"
  )
  write_output_table(
    prepared$unmatched,
    configuration$output,
    "unmatched_samples.csv"
  )
  write_output_table(
    prepared$excluded,
    configuration$output,
    "excluded_samples.csv"
  )
  write_output_table(
    prepared$mismatches,
    configuration$output,
    "measurement_mismatches.csv"
  )
  write_output_table(
    prepared$ambiguities,
    configuration$output,
    "classification_ambiguities.csv"
  )
  write_output_table(
    prepared$invalid_values,
    configuration$output,
    "invalid_measurements.csv"
  )

  report_issue_count(prepared$unmatched, "Unmatched samples")
  report_issue_count(prepared$excluded, "Deliberately excluded samples")
  report_issue_count(prepared$mismatches, "Measurement mismatches")
  report_issue_count(prepared$ambiguities, "Classification ambiguities")
  report_issue_count(prepared$invalid_values, "Invalid measurement rows")

  if (nrow(prepared$ambiguities) > 0L) {
    stop(
      paste0(
        "Analysis stopped because multiple sample columns map to the same ",
        "treatment and time point. Review classification_ambiguities.csv."
      ),
      call. = FALSE
    )
  }

  plot_directory <- file.path(configuration$output, "plots")
  qq_directory <- file.path(configuration$output, "normality_qq")
  dir.create(plot_directory, recursive = TRUE, showWarnings = FALSE)
  dir.create(qq_directory, recursive = TRUE, showWarnings = FALSE)

  combinations <- expand.grid(
    Time = c("30 min", "3 h"),
    Measurement = c(
      "Median pHrodo intensity",
      "% pHrodo-positive neutrophils"
    ),
    stringsAsFactors = FALSE
  )

  all_statistics <- list()
  all_normality <- list()
  all_assumptions <- list()
  all_exclusions <- list()

  for (index in seq_len(nrow(combinations))) {
    time_point <- combinations$Time[[index]]
    measurement <- combinations$Measurement[[index]]
    message("Analysing: ", time_point, " — ", measurement)

    analysis <- analyse_combination(prepared$tidy, measurement, time_point)
    all_statistics[[index]] <- analysis$statistics
    all_normality[[index]] <- analysis$normality
    all_assumptions[[index]] <- analysis$assumptions
    all_exclusions[[index]] <- analysis$exclusions

    stem <- file_slug(time_point, measurement)
    save_plot_pair(analysis$plot, plot_directory, stem)
    save_plot_pair(
      analysis$qq_plot,
      qq_directory,
      paste0(stem, "_qq"),
      width = 10,
      height = 7
    )
  }

  statistical_results <- dplyr::bind_rows(all_statistics)
  normality_results <- dplyr::bind_rows(all_normality)
  assumption_results <- dplyr::bind_rows(all_assumptions)
  analysis_exclusions <- dplyr::bind_rows(all_exclusions)

  write_output_table(
    statistical_results,
    configuration$output,
    "statistical_results.csv"
  )
  write_output_table(
    normality_results,
    configuration$output,
    "normality_results.csv"
  )
  write_output_table(
    assumption_results,
    configuration$output,
    "anova_assumption_results.csv"
  )
  write_output_table(
    analysis_exclusions,
    configuration$output,
    "analysis_exclusions.csv"
  )

  session_information <- capture.output(utils::sessionInfo())
  writeLines(
    enc2utf8(session_information),
    file.path(configuration$output, "session_info.txt"),
    useBytes = TRUE
  )

  cat("\nNormality results\n")
  print(normality_results, n = Inf, width = Inf)
  cat("\nStatistical results\n")
  print(statistical_results, n = Inf, width = Inf)
  cat("\nAnalysis complete\n")
  cat("Output directory:", configuration$output, "\n")
}


main()
