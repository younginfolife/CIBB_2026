# data

This folder is visible inside the container as `/sharedFolder/data` and is
already the RStudio working directory, so relative paths work:

```r
counts <- read.delim("data/TestData/Data/insilico_size100_1_multifactorial.tsv",
                     check.names = FALSE)
```

Contents:

* `TestData/` — tutorial data and the corresponding gold standards
* `ValidationData/` — validation data and the corresponding gold standards

Notes for adding data: files above 100 MB cannot be pushed to GitHub, use Git LFS
or an external link (Zenodo, Drive). Avoid spaces and accents in file and folder
names. Do not commit intermediate results here, only input data.
