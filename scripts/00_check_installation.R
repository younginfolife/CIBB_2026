## ---------------------------------------------------------------------------
## 00_check_installation.R
## Run this as the very first thing in RStudio: it loads every package of the
## tutorial and prints a table with the versions.
## ---------------------------------------------------------------------------

preprocessing <- c(
  "DESeq2", "edgeR", "limma", "sva", "RUVSeq", "EDASeq",
  "matrixStats", "data.table", "tidyverse"
)

reverse_engineering <- c(
  "WGCNA", "GENIE3", "minet", "GeneNet", "huge", "glasso",
  "space", "c3net", "BDgraph", "qgraph", "igraph"
)

all_pkgs <- c(preprocessing, reverse_engineering)

results <- data.frame(
  package = all_pkgs,
  group   = c(rep("preprocessing", length(preprocessing)),
              rep("reverse_engineering", length(reverse_engineering))),
  version = NA_character_,
  loaded  = FALSE,
  stringsAsFactors = FALSE
)

for (i in seq_len(nrow(results))) {
  pkg <- results$package[i]
  ok <- suppressWarnings(suppressPackageStartupMessages(
    require(pkg, character.only = TRUE, quietly = TRUE)
  ))
  results$loaded[i] <- isTRUE(ok)
  if (isTRUE(ok)) {
    results$version[i] <- as.character(utils::packageVersion(pkg))
  }
}

cat("\n=== Tutorial environment =========================================\n")
cat("R version      :", R.version.string, "\n")
cat("Platform       :", R.version$platform, "\n")
cat("Working dir    :", getwd(), "\n")
cat("Shared folder  :", ifelse(dir.exists("/sharedFolder"),
                               "/sharedFolder (mounted)",
                               "NOT FOUND"), "\n")
cat("==================================================================\n\n")

print(results, row.names = FALSE)

failed <- results$package[!results$loaded]
if (length(failed) > 0) {
  cat("\n")
  stop("These packages did not load: ", paste(failed, collapse = ", "))
}

cat("\nAll ", nrow(results), " packages loaded correctly.\n", sep = "")

## quick sanity check: 30 genes x 20 samples, one small network per method
set.seed(1)
counts <- matrix(rnbinom(30 * 20, mu = 200, size = 2), nrow = 30)
rownames(counts) <- paste0("gene", seq_len(30))
colnames(counts) <- paste0("s", seq_len(20))

log_cpm <- edgeR::cpm(counts, log = TRUE)
cat("\nlogCPM matrix:", nrow(log_cpm), "genes x", ncol(log_cpm), "samples\n")

mim <- minet::build.mim(t(log_cpm), estimator = "spearman")
net_aracne <- minet::aracne(mim)
cat("minet/ARACNe edges :", sum(net_aracne > 0) / 2, "\n")

net_genie3 <- GENIE3::GENIE3(log_cpm, nTrees = 50, verbose = FALSE)
cat("GENIE3 weight matrix:", nrow(net_genie3), "x", ncol(net_genie3), "\n")

g <- igraph::graph_from_adjacency_matrix(net_aracne > 0, mode = "undirected")
cat("igraph graph        :", igraph::vcount(g), "nodes,",
    igraph::ecount(g), "edges\n")

cat("\nEverything works. Enjoy the tutorial.\n")
