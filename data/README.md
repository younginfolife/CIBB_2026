# data

Datasets of the tutorial go here. This folder is visible inside the container
as `/sharedFolder/data`, so from RStudio:

```r
counts <- read.delim("data/counts.txt", row.names = 1, check.names = FALSE)
```

Notes:

* files larger than 100 MB cannot be pushed to GitHub: use Git LFS, a Zenodo /
  Drive link, or ask students to download them separately;
* keep the file names free of spaces and accents;
* do not commit intermediate results here, only the input data.
