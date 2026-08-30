# Load packages for the exercises

library(igraph)

library(qgraph)

library(GeneNet)

library(glasso)

library(huge)

library(minet)

library(GENIE3)

library(BDgraph)

# Set the project folder

base_dir <- "/sharedFolder/data/ValidationData"

expr_file <- file.path(base_dir, "DataSet",
                                      "insilico_size100_2_multifactorial.tsv")

gold_file <- file.path(base_dir, "GoldStandard",
                       
                       "insilico_size100_multifactorial_2_goldstandard_matrix.tsv"
)

# Read expression data: rows = samples, columns = genes

expr <- read.delim(expr_file, check.names = FALSE)

# Read gold standard: rows = genes, columns = genes

gold <- read.delim(gold_file, row.names = 1, check.names =
                     FALSE)
# Quick checks

dim(expr)

dim(gold)

head(colnames(expr))

# Convert to numeric matrices

X <- as.matrix(expr)

G <- as.matrix(gold)

storage.mode(X) <- "numeric"

storage.mode(G) <- "numeric"
# Check missing values and basic ranges

sum(is.na(X))

summary(as.vector(X))

# Keep genes that vary across samples

gene_var <- apply(X, 2, var)

X <- X[, gene_var > 0]

# Standardize genes for covariance-based methods

X_scaled <- scale(X)

# Align the gold standard to the retained genes

common_genes <- intersect(colnames(X_scaled), rownames(G))

X_scaled <- X_scaled[, common_genes]

G <- G[common_genes, common_genes]

# Compute an absolute Pearson correlation matrix

S <- abs(cor(X_scaled, method = "pearson"))

diag(S) <- 0

# Keep only the strongest edges

threshold <- quantile(S[upper.tri(S)], 0.98)

A_cor <- (S >= threshold) * 1

diag(A_cor) <- 0

# Build an undirected graph

g_cor <- graph_from_adjacency_matrix(A_cor,
                                     
                                     mode = "undirected", diag = FALSE)

# Basic graph statistics

vcount(g_cor)

ecount(g_cor)

sort(degree(g_cor), decreasing = TRUE)[1:10]

# Estimate shrinkage partial correlations

pcor_mat <- ggm.estimate.pcor(X_scaled)

# Test and rank candidate edges

genet_edges <- network.test.edges(
  
  pcor_mat,
  
  direct = FALSE,
  
  plot = FALSE
  
)

# Keep the best-ranked edges

top_edges <- genet_edges[order(genet_edges$qval), ][1:200, ]

# Build an edge list for igraph

el <- data.frame(
  
  from = top_edges$node1,
  
  to = top_edges$node2,
  
  weight = abs(top_edges$pcor)
  
)

g_genet <- graph_from_data_frame(el, directed = FALSE)

# glasso requires a covariance matrix

S_cov <- cov(X_scaled)

# Try one regularization value

rho <- 0.15

fit_glasso <- glasso(S_cov, rho = rho)

# Non-zero precision matrix entries define edges

P <- fit_glasso$wi

A_glasso <- (abs(P) > 1e-6) * 1

diag(A_glasso) <- 0

g_glasso <- graph_from_adjacency_matrix(A_glasso,
                                        
                                        mode = "undirected", diag = FALSE)
# huge can fit a path of sparse networks

fit_huge <- huge(X_scaled, method = "glasso")

# Select one model with the rotation information criterion

sel <- huge.select(fit_huge, criterion = "ric")

A_huge <- sel$refit

g_huge <- graph_from_adjacency_matrix(A_huge,
                                      
                                      mode = "undirected", diag = FALSE)

# Estimate mutual information

mi <- build.mim(X_scaled, estimator = "spearman")

# Try three common algorithms

net_aracne <- aracne(mi)

net_clr <- clr(mi)

net_mrnet <- mrnet(mi)

# Convert a score matrix to an adjacency matrix

S_mi <- as.matrix(net_clr)

diag(S_mi) <- 0

threshold <- quantile(S_mi[upper.tri(S_mi)], 0.98)

A_mi <- (S_mi >= threshold) * 1

g_minet <- graph_from_adjacency_matrix(A_mi,
                                       
                                       mode = "undirected", diag = FALSE)

# Load packages

library(c3net)

library(igraph)

# Infer the network. C3NET expects genes in rows and samples in columns

A_c3 <- c3net(t(X_scaled))

# Remove self-connections

diag(A_c3) <- 0

# Build the graph

g_c3 <- graph_from_adjacency_matrix(
  
  A_c3,
  
  mode = "undirected",
  
  weighted = TRUE,
  
  diag = FALSE
  
)

# Inspect the network

vcount(g_c3)

ecount(g_c3)

# Identify the most connected genes

sort(degree(g_c3), decreasing = TRUE)[1:10]

# GENIE3 expects genes in rows and samples in columns

expr_genes_by_samples <- t(X_scaled)

# Run GENIE3 on all genes as candidate regulators

set.seed(123)

weight_matrix <- GENIE3(expr_genes_by_samples)

# Convert weights to a ranked edge list

genie_edges <- getLinkList(weight_matrix)

head(genie_edges)

# Keep the top predicted regulatory links

top_genie <- head(genie_edges, 300)

g_genie <- graph_from_data_frame(top_genie, directed =
                                   TRUE)

# Evaluate undirected adjacency matrices

evaluate_network <- function(A_pred, A_true) {
  
  A_pred <- (A_pred > 0) * 1
  
  A_true <- (A_true > 0) * 1
  
  diag(A_pred) <- 0
  
  diag(A_true) <- 0
  
  idx <- upper.tri(A_true)
  
  TP <- sum(A_pred[idx] == 1 & A_true[idx] == 1)
  
  FP <- sum(A_pred[idx] == 1 & A_true[idx] == 0)
  
  FN <- sum(A_pred[idx] == 0 & A_true[idx] == 1)
  
  precision <- TP / (TP + FP)
  
  recall <- TP / (TP + FN)
  
  f1 <- 2 * precision * recall / (precision + recall)
  
  data.frame(TP, FP, FN, precision, recall, f1)
  
}
# Example: evaluate three networks

G_bin <- (G > 0) * 1

evaluate_network(A_cor, G_bin)

evaluate_network(A_glasso, G_bin)

evaluate_network(A_mi, G_bin)
# Avvia metrics.py sulle tre reti
metrics_script <- "/sharedFolder/scripts/metrics.py"
output_dir <- "/sharedFolder/data/metrics_input"

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Forza gli stessi nomi dei geni su tutte le matrici
rownames(G_bin) <- common_genes
colnames(G_bin) <- common_genes

networks <- list(
  A_cor = A_cor,
  A_glasso = A_glasso,
  A_mi = A_mi
)

true_file <- file.path(output_dir, "G_bin.csv")
write.csv(G_bin, true_file)

for (network_name in names(networks)) {
  adjacency <- as.matrix(networks[[network_name]])
  
  rownames(adjacency) <- common_genes
  colnames(adjacency) <- common_genes
  
  estimated_file <- file.path(
    output_dir,
    paste0(network_name, ".csv")
  )
  
  write.csv(adjacency, estimated_file)
  
  cat("\n---", network_name, "---\n")
  
  python_output <- system2(
    "python3",
    args = c(
      metrics_script,
      "--est", estimated_file,
      "--true", true_file
    ),
    stdout = TRUE,
    stderr = TRUE
  )
  
  cat(python_output, sep = "\n")
  cat("\n")
}