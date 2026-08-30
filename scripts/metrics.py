#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import argparse

import numpy as np
import pandas as pd


def read_adjacency(path: str) -> pd.DataFrame:
    """Read a labelled adjacency matrix from CSV or TSV."""
    file_path = Path(path)
    if not file_path.is_file():
        raise FileNotFoundError(f"File not found: {file_path}")

    if file_path.suffix.lower() in {".tsv", ".txt"}:
        sep = "\t"
    elif file_path.suffix.lower() == ".csv":
        sep = ","
    else:
        sep = None  # Let pandas detect the separator.

    matrix = pd.read_csv(file_path, sep=sep, engine="python", index_col=0)
    matrix.index = matrix.index.map(str)
    matrix.columns = matrix.columns.map(str)

    if matrix.empty:
        raise ValueError(f"Empty or incorrectly parsed matrix: {file_path}")
    if matrix.shape[0] != matrix.shape[1]:
        raise ValueError(
            f"Matrix must be square, but {file_path} has shape {matrix.shape}"
        )
    if matrix.index.has_duplicates or matrix.columns.has_duplicates:
        raise ValueError(f"Duplicated row or column labels in {file_path}")

    try:
        matrix = matrix.apply(pd.to_numeric, errors="raise")
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Matrix contains non-numeric values: {file_path}") from exc

    return matrix


def stat_metrics(
    ground_truth: np.ndarray, estimated_adj: np.ndarray
) -> tuple[float, float, float]:
    """Compute precision, recall and MCC for an undirected binary network."""
    ground_truth = np.asarray(ground_truth)
    estimated_adj = np.asarray(estimated_adj)

    if ground_truth.ndim != 2 or ground_truth.shape[0] != ground_truth.shape[1]:
        raise ValueError("The ground-truth matrix must be square")
    if estimated_adj.shape != ground_truth.shape:
        raise ValueError("Estimated and ground-truth matrices must have the same shape")

    true_binary = (ground_truth != 0).astype(np.uint8)
    estimated_binary = (estimated_adj != 0).astype(np.uint8)
    np.fill_diagonal(true_binary, 0)
    np.fill_diagonal(estimated_binary, 0)

    if not np.array_equal(true_binary, true_binary.T):
        raise ValueError("The ground-truth matrix is not symmetric")
    if not np.array_equal(estimated_binary, estimated_binary.T):
        raise ValueError("The estimated matrix is not symmetric")

    upper = np.triu_indices_from(true_binary, k=1)
    truth = true_binary[upper]
    estimate = estimated_binary[upper]

    tp = int(np.sum((truth == 1) & (estimate == 1)))
    fp = int(np.sum((truth == 0) & (estimate == 1)))
    tn = int(np.sum((truth == 0) & (estimate == 0)))
    fn = int(np.sum((truth == 1) & (estimate == 0)))

    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0

    denominator = np.sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn))
    mcc = (tp * tn - fp * fn) / denominator if denominator else 0.0

    return float(precision), float(recall), float(mcc)


def main(estimated_path: str, truth_path: str) -> tuple[float, float, float]:
    truth = read_adjacency(truth_path)
    estimated = read_adjacency(estimated_path)

    missing_rows = truth.index.difference(estimated.index)
    missing_columns = truth.columns.difference(estimated.columns)
    if len(missing_rows) or len(missing_columns):
        raise ValueError(
            "The estimated matrix does not contain every gene in the ground truth"
        )

    estimated = estimated.reindex(index=truth.index, columns=truth.columns)
    return stat_metrics(truth.to_numpy(), estimated.to_numpy())


def self_test() -> None:
    truth = np.array(
        [
            [0, 1, 0, 0],
            [1, 0, 1, 0],
            [0, 1, 0, 0],
            [0, 0, 0, 0],
        ]
    )
    estimate = np.array(
        [
            [0, 1, 0, 0],
            [1, 0, 0, 0],
            [0, 0, 0, 1],
            [0, 0, 1, 0],
        ]
    )

    expected = np.array([0.5, 0.5, 0.25])
    observed = np.array(stat_metrics(truth, estimate))
    if not np.allclose(observed, expected):
        raise AssertionError(f"Expected {tuple(expected)}, obtained {tuple(observed)}")

    perfect = np.array(stat_metrics(truth, truth))
    if not np.allclose(perfect, np.ones(3)):
        raise AssertionError(f"Perfect-network test failed: {tuple(perfect)}")

    print("Self-test passed: precision=0.5, recall=0.5, MCC=0.25")
    print("Perfect-network test passed: precision=1, recall=1, MCC=1")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Evaluate an undirected adjacency matrix against a ground truth."
    )
    parser.add_argument("--est", help="Estimated adjacency matrix (CSV or TSV)")
    parser.add_argument("--true", dest="truth", help="Ground-truth matrix (CSV or TSV)")
    parser.add_argument(
        "--self-test", action="store_true", help="Run internal tests and exit"
    )
    args = parser.parse_args()

    if args.self_test:
        self_test()
    else:
        if not args.est or not args.truth:
            parser.error("--est and --true are required unless --self-test is used")
        precision, recall, mcc = main(args.est, args.truth)
        print(f"precision={precision:.6f}")
        print(f"recall={recall:.6f}")
        print(f"mcc={mcc:.6f}")
