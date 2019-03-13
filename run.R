#!/usr/local/bin/Rscript

task <- dyncli::main()

library(jsonlite)
library(readr)
library(dplyr)
library(purrr)

library(monocle)

#   ____________________________________________________________________________
#   Load data                                                               ####

params <- task$params
counts <- task$counts

#   ____________________________________________________________________________
#   Infer trajectory                                                        ####


# just in case
if (is.factor(params$norm_method)) {
  params$norm_method <- as.character(params$norm_method)
}

# TIMING: done with preproc
checkpoints <- list(method_afterpreproc = as.numeric(Sys.time()))

# load in the new dataset
pd <- Biobase::AnnotatedDataFrame(data.frame(row.names = rownames(counts)))
fd <- Biobase::AnnotatedDataFrame(data.frame(row.names = colnames(counts), gene_short_name = colnames(counts)))
cds <- monocle::newCellDataSet(t(counts), pd, fd)

# estimate size factors and dispersions
cds <- BiocGenerics::estimateSizeFactors(cds)
cds <- BiocGenerics::estimateDispersions(cds)

# filter features if requested
if (params$filter_features) {
  disp_table <- dispersionTable(cds)
  ordering_genes <- subset(disp_table, mean_expression >= params$filter_features_mean_expression)
  cds <- setOrderingFilter(cds, ordering_genes)

  print(nrow(ordering_genes))
}

# if low # cells or features -> https://github.com/cole-trapnell-lab/monocle-release/issues/26
# this avoids the error "initial centers are not distinct."
if (ncol(counts) < 500 || nrow(counts) < 500) {
  params$auto_param_selection <- FALSE
}

# reduce the dimensionality
cds <- monocle::reduceDimension(
  cds,
  max_components = params$max_components,
  reduction_method = params$reduction_method,
  norm_method = params$norm_method,
  auto_param_selection = params$auto_param_selection
)

# workaround for determining the maximum number of
# possible branches accoding to the PQ algorithm
num_q_nodes <- function(cds) {
  root_cell <- monocle:::select_root_cell(cds, root_state = NULL, NULL)
  adjusted_S <- t(cds@reducedDimS)
  dp <- as.matrix(dist(adjusted_S))
  cellPairwiseDistances(cds) <- as.matrix(dist(adjusted_S))
  gp <- igraph::graph.adjacency(dp, mode = "undirected", weighted = TRUE)
  dp_mst <- igraph::minimum.spanning.tree(gp)
  next_node <<- 0
  res <- monocle:::pq_helper(dp_mst, use_weights = FALSE, root_node = root_cell)
  sum(igraph::V(res$subtree)$type == "Q")
}

branch_node_counts <- max(1, min(task$priors$start_n + task$priors$end_n - 1, num_q_nodes(cds)))

# order the cells
cds <- monocle::orderCells(cds, num_paths = branch_node_counts)

# TIMING: done with method
checkpoints$method_aftermethod <- as.numeric(Sys.time())

# extract the igraph and which cells are on the trajectory
gr <- cds@auxOrderingData[[params$reduction_method]]$cell_ordering_tree
to_keep <- setNames(rep(TRUE, nrow(counts)), rownames(counts))

# convert to milestone representation
cell_graph <- igraph::as_data_frame(gr, "edges") %>% mutate(directed = FALSE)

if ("weight" %in% colnames(cell_graph)) {
  cell_graph <- cell_graph %>% rename(length = weight)
} else {
  cell_graph <- cell_graph %>% mutate(length = 1)
}

cell_graph <- cell_graph %>% select(from, to, length, directed)

dimred <- t(cds@reducedDimS)
colnames(dimred) <- paste0("Comp", seq_len(ncol(dimred)))

#   ____________________________________________________________________________
#   Save output                                                             ####

output <- dynwrap::wrap_data(cell_ids = rownames(dimred)) %>%
  dynwrap::add_cell_graph(
    cell_graph = cell_graph,
    to_keep = to_keep
  ) %>%
  dynwrap::add_dimred(dimred) %>%
  dynwrap::add_timings(checkpoints)

dyncli::write_output(output, task$output)
