## ---------------------------------------------------------------------------
## install_packages.R
## Preprocessing + reverse engineering stack for the RNA-seq / networks tutorial
## ---------------------------------------------------------------------------

ncpus <- max(1L, parallel::detectCores())

options(
  repos = c(CRAN = Sys.getenv("CRAN", "https://cloud.r-project.org")),
  Ncpus = ncpus,
  warn = 1,
  timeout = 3600
)

## On arm64 (Apple Silicon, ARM servers) Posit Package Manager does not serve
## precompiled binaries, so everything is built from source: use all cores.
arch <- R.version$arch
message(">>> architecture: ", arch, " | cores: ", ncpus)
if (!nzchar(Sys.getenv("MAKEFLAGS"))) {
  Sys.setenv(MAKEFLAGS = paste0("-j", ncpus))
}

## --- 1. bootstrap ----------------------------------------------------------

if (!requireNamespace("BiocManager", quietly = TRUE)) {
  install.packages("BiocManager")
}

## Bioconductor release: taken from the BIOC_VERSION env var if set at build
## time, otherwise the one matching the running R version.
bioc_version <- Sys.getenv("BIOC_VERSION", "")
if (nzchar(bioc_version)) {
  message(">>> pinning Bioconductor to ", bioc_version)
  BiocManager::install(version = bioc_version, ask = FALSE, update = FALSE)
}

message(">>> R           : ", R.version.string)
message(">>> Bioconductor: ", as.character(BiocManager::version()))

bioc_install <- function(pkg, configure.args = NULL) {
  args <- list(pkg, update = FALSE, ask = FALSE)
  if (nzchar(bioc_version)) args$version <- bioc_version
  if (!is.null(configure.args)) args$configure.args <- configure.args
  do.call(BiocManager::install, args)
}

## --- 2. CRAN packages ------------------------------------------------------

cran_pkgs <- c(
  ## preprocessing / utilities
  "matrixStats",
  "data.table",
  "tidyverse",
  "R.utils",
  "remotes",
  ## reverse engineering
  "WGCNA",
  "GeneNet",
  "huge",
  "glasso",
  "BDgraph",
  "qgraph",
  "igraph",
  ## dependencies used by the packages above / by the archived ones
  "corpcor",
  "longitudinal",
  "fdrtool",
  "dynamicTreeCut",
  "fastcluster",
  "Rcpp",
  "RcppArmadillo",
  "MASS"
)

for (pkg in cran_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(">>> installing CRAN package: ", pkg)
    install.packages(pkg)
  } else {
    message(">>> already present: ", pkg)
  }
}

## --- 3. Bioconductor packages ---------------------------------------------

bioc_pkgs <- c(
  ## preprocessing
  "DESeq2",
  "edgeR",
  "limma",
  "sva",
  "RUVSeq",
  "EDASeq",
  ## reverse engineering
  "GENIE3",
  "minet",
  ## annotation / deps required by WGCNA and EDASeq
  "impute",
  "preprocessCore",
  "GO.db",
  "AnnotationDbi",
  "biomaRt",
  "Biobase",
  "SummarizedExperiment"
)

for (pkg in bioc_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message(">>> installing Bioconductor package: ", pkg)
    bioc_install(pkg)
    ## preprocessCore (needed by WGCNA) fails to build with OpenMP threading on
    ## several non-x86 platforms: retry with threading disabled.
    if (pkg == "preprocessCore" && !requireNamespace(pkg, quietly = TRUE)) {
      message(">>> retrying ", pkg, " with --disable-threading")
      bioc_install(pkg, configure.args = "--disable-threading")
    }
  } else {
    message(">>> already present: ", pkg)
  }
}

## --- 4. packages archived on CRAN -----------------------------------------
## `space` and `c3net` are no longer in the active CRAN index, so they are
## installed from the CRAN Archive. Several versions are tried in order.

archived_pkgs <- list(
  space = c(
    "https://cran.r-project.org/src/contrib/Archive/space/space_0.1-1.1.tar.gz",
    "https://cran.r-project.org/src/contrib/Archive/space/space_0.1-1.tar.gz"
  ),
  c3net = c(
    "https://cran.r-project.org/src/contrib/Archive/c3net/c3net_1.1.1.tar.gz",
    "https://cran.r-project.org/src/contrib/Archive/c3net/c3net_1.1.tar.gz"
  )
)

for (pkg in names(archived_pkgs)) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    message(">>> already present: ", pkg)
    next
  }
  urls <- archived_pkgs[[pkg]]
  for (url in urls) {
    message(">>> trying archived source for ", pkg, ": ", url)
    tarball <- file.path(tempdir(), basename(url))
    ok <- tryCatch({
      utils::download.file(url, tarball, mode = "wb", quiet = TRUE)
      install.packages(tarball, repos = NULL, type = "source")
      requireNamespace(pkg, quietly = TRUE)
    }, error = function(e) {
      message("    failed: ", conditionMessage(e))
      FALSE
    })
    if (isTRUE(ok)) break
  }
}

## --- 5. final verification -------------------------------------------------
## The build must fail loudly if anything is missing, otherwise students
## discover the problem during the tutorial.

required <- c(
  "DESeq2", "edgeR", "limma", "sva", "RUVSeq", "EDASeq",
  "matrixStats", "data.table", "tidyverse",
  "WGCNA", "GENIE3", "minet", "GeneNet", "huge", "glasso",
  "space", "c3net", "BDgraph", "qgraph", "igraph"
)

missing <- character(0)
for (pkg in required) {
  ok <- requireNamespace(pkg, quietly = TRUE)
  message(sprintf("%-14s %s", pkg, if (ok) "OK" else "MISSING"))
  if (!ok) missing <- c(missing, pkg)
}

if (length(missing) > 0) {
  stop("Installation incomplete, missing packages: ",
       paste(missing, collapse = ", "))
}

message("\nAll ", length(required), " required packages are installed.\n")

## Write a manifest inside the image, handy for reproducibility / debugging.
ip <- utils::installed.packages()
manifest <- data.frame(
  package = rownames(ip),
  version = ip[, "Version"],
  stringsAsFactors = FALSE,
  row.names = NULL
)
manifest <- manifest[order(manifest$package), ]
manifest$arch <- arch
utils::write.csv(manifest, "/opt/package_manifest.csv", row.names = FALSE)

sessionInfo()
