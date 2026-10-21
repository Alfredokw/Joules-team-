script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_dir <- if (length(script_arg)) {
  script_file <- sub("^--file=", "", script_arg[1])
  script_file <- gsub("~\\+~", " ", script_file)
  dirname(normalizePath(script_file, mustWork = TRUE))
} else {
  normalizePath(getwd(), mustWork = TRUE)
}
old_working_directory <- getwd()
on.exit(setwd(old_working_directory), add = TRUE)
setwd(script_dir)

cache_dir <- Sys.getenv(
  "GREENLAB_CACHE",
  unset = file.path(tempdir(), paste0("greenlab_hypothesis_testing_", Sys.getpid()))
)
if (dir.exists(cache_dir)) unlink(cache_dir, recursive = TRUE, force = TRUE)
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(cache_dir, recursive = TRUE, force = TRUE), add = TRUE)

scripts <- c(
  "01_prepare_data.R",
  "02_subject_level_data.R",
  "03_RQ1_baseline.R",
  "04_RQ2_correlation.R",
  "05_RQ3_workload.R",
  "06_RQ4_error_family.R",
  "07_make_figures.R",
  "09_publish_tables.R"
)
missing_scripts <- scripts[!file.exists(scripts)]
if (length(missing_scripts)) {
  stop("Missing analysis scripts: ", paste(missing_scripts, collapse = ", "))
}
for (script in scripts) {
  message("\n=== Running ", script, " ===")
  source(script, local = new.env(parent = globalenv()))
}
message("\nAll hypothesis-testing outputs are complete.")
