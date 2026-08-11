# Gene Network Inference Benchmark

This repository contains synthetic benchmark datasets for gene network inference experiments based on DREAM4-style regulatory networks.

---

# Repository Structure

```text
readme_fix_extract/
  Test data/
    Gold standard/
      insilico_size100_multifactorial_3_goldstandard_matrix.tsv
      insilico_size10_1_goldstandard_matrix.tsv
      insilico_size100_1_goldstandard_matrix.tsv
      insilico_size100_multifactorial_2_goldstandard_matrix.tsv
      insilico_size100_multifactorial_1_goldstandard_matrix.tsv
      insilico_size100_2_goldstandard_matrix.tsv
    Data/
      insilico_size100_3_multifactorial.tsv
      insilico_size10_1_knockouts.tsv
      insilico_size100_1_knockdowns.tsv
      insilico_size10_1_knockdowns.tsv
      insilico_size100_2_knockdowns.tsv
      insilico_size100_1_multifactorial.tsv
      insilico_size100_1_knockouts.tsv
      insilico_size100_2_knockouts.tsv
      insilico_size100_2_multifactorial.tsv
      insilico_size10_1_multifactorial.tsv
```

---

# Data Folder

The `Data/` folder contains the expression datasets used as input for network inference algorithms.

Each file corresponds to a specific network topology.

Examples:

```text
insilico_size100_1_multifactorial.tsv
insilico_size100_2_knockdowns.tsv
insilico_size10_1_knockouts.tsv
```

The datasets contain:

- steady-state transcriptomic data
- perturbation experiments
- expression matrices in TSV format

Matrix convention:

```text
samples × genes
```

where:

- rows correspond to samples / perturbation experiments
- columns correspond to genes

These datasets should be used to infer the hidden interaction networks.

---

# Gold Standard Folder

The `Gold standard/` folder contains the reference adjacency matrices associated with the datasets stored in `Data/`.

Each file is a symmetric adjacency matrix representing the true network topology associated with a corresponding dataset.

Examples:

```text
insilico_size100_1_goldstandard_matrix.tsv
insilico_size100_multifactorial_2_goldstandard_matrix.tsv
```

Matrix convention:

```text
genes × genes
```

where:

- rows correspond to genes
- columns correspond to genes

Entries are binary:

- `1` = edge present
- `0` = edge absent

Gene ordering follows natural numeric ordering:

```text
G1, G2, G3, ..., G10, G11, ..., G100
```

The adjacency matrices have been symmetrized in order to support undirected graph recovery methods.

---

# Relationship Between Data and Gold Standards

Each dataset in `Data/` is associated with a corresponding adjacency matrix in `Gold standard/`.

The intended workflow is:

```text
Expression Data
        ↓
Network Inference Algorithm
        ↓
Predicted Network
        ↓
Comparison with Gold Standard
```

For example:

```text
Data/insilico_size100_1_multifactorial.tsv
```

should be evaluated against:

```text
Gold standard/insilico_size100_1_goldstandard_matrix.tsv
```

Similarly:

```text
Data/insilico_size100_2_multifactorial.tsv
```

corresponds to:

```text
Gold standard/insilico_size100_2_goldstandard_matrix.tsv
```

---

# Notes

- The benchmark focuses on static graph recovery.
- Time-series datasets are not included.
- The gold standard networks are provided as symmetric adjacency matrices.
