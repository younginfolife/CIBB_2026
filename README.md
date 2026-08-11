# CIBB 2026 — RNA-seq and network reverse engineering

RStudio Server in a container, with everything needed to go from RNA-seq counts
to co-expression and regulatory networks, comparing different methodological
approaches.

Repository: <https://github.com/younginfolife/CIBB_2026>
Images: `ghcr.io/younginfolife/cibb_2026:latest` and `:dind`

---

## For students

You only need Docker. Nothing else: R, RStudio and all packages are already
inside the image.

1. Install Docker
   * Windows and macOS: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   * Linux: `docker` from your distribution packages
2. Download this repository: green **Code > Download ZIP** button, then extract.
   Or `git clone https://github.com/younginfolife/CIBB_2026.git`
3. Start it:
   * **Windows** → double-click `start.bat`
   * **macOS** → double-click `start_macos.command`
   * **Linux** → in a terminal, `./start.sh`
4. The browser opens on <http://localhost:8888>. **No login**, no username and no
   password.
5. First thing to run in the RStudio console:
   ```r
   source("/sharedFolder/scripts/00_check_installation.R")
   ```
   It prints the list of packages with their versions and runs a quick network
   inference test. If it reaches the end, the environment is fine.
6. To stop everything: `./start.sh --stop` (Windows: `start.bat -Stop`).

The first start downloads several GB and needs **~25 GB of free disk space**.
Later starts are immediate.

If you downloaded the ZIP on macOS or Linux and get "Permission denied":

```bash
chmod +x start.sh start_macos.command docker/entrypoint-dind.sh
```

### The shared folder

The folder containing the launcher script (that is, the repository root) is
mounted in the container as `/sharedFolder`, and it is already the RStudio
working directory.

```
your computer                         container
CIBB_2026/              <------->     /sharedFolder/
├── data/                             ├── data/
├── scripts/                          ├── scripts/
└── ...                               └── ...
```

So inside RStudio you read the data with relative paths:

```r
counts <- read.delim("data/TestData/Data/insilico_size100_1_multifactorial.tsv",
                     check.names = FALSE)
```

Everything you save there stays on your computer after the container is shut
down. Everything you save elsewhere (for example in `/home/rstudio`) is lost.

### Apple Silicon (M1/M2/M3/M4) and other ARM machines

The published images are built for **amd64**. On an ARM Mac they run under
emulation: RStudio behaves normally, heavy computations are slower. The launcher
detects this, prints a warning and passes `--platform linux/amd64` so the
behaviour is predictable. Nothing to do.

For a native ARM image, build it once locally (long: on arm64 there are no
precompiled CRAN binaries, every package is compiled from source):

```bash
./start.sh --build
```

The `--dind` variant under emulation is unreliable (an emulated `dockerd` inside
an emulated container): on ARM either build it natively or skip it.

### Launcher options

| Linux / macOS | Windows | What it does |
|---|---|---|
| `./start.sh` | `.\start.ps1` | start the container |
| `./start.sh --port 9999` | `.\start.ps1 -Port 9999` | use another port |
| `./start.sh --dind` | `.\start.ps1 -Dind` | docker-in-docker variant |
| `./start.sh --build` | `.\start.ps1 -Build` | build the image locally instead of pulling it |
| `./start.sh --stop` | `.\start.ps1 -Stop` | stop and remove the container |
| `./start.sh --logs` | `.\start.ps1 -Logs` | follow the container logs |
| `./start.sh --shell` | `.\start.ps1 -Shell` | open a bash shell inside the container |

Before starting, the scripts check that: Docker is installed and the daemon
answers; the folder exists and is readable and writable; the path does not
contain characters that break bind mounts (spaces are handled, everything is
quoted; accents, network paths and shell metacharacters produce a warning);
there is enough free disk space; the port is free.

## What is installed

**Preprocessing, normalisation, batch correction**

`DESeq2` · `edgeR` · `limma` · `sva` · `RUVSeq` · `EDASeq` · `matrixStats` ·
`data.table` · `tidyverse`

**Reverse engineering / network inference**

`WGCNA` · `GENIE3` · `minet` (ARACNe, CLR, MRNET) · `GeneNet` · `huge` ·
`glasso` · `space` · `c3net` · `BDgraph` · `qgraph` · `igraph`

`space` and `c3net` are no longer in the active CRAN index and are installed
from the CRAN Archive (see `docker/install_packages.R`).

| | |
|---|---|
| R | 4.6.1, the current release (2026-06-24), from `rocker/rstudio:4.6.1` |
| Bioconductor | the release matching R 4.6.x, picked by BiocManager |
| Docker (dind variant) | from the official `docker:29-dind` image |

R is **not** the apt/Ubuntu one: the rocker images install exactly the version of
the tag. The full package version manifest is inside the image:

```r
read.csv("/opt/package_manifest.csv")
```

## Repository structure

```
.
├── Dockerfile                     # RStudio Server (R 4.6.1) + R packages
├── Dockerfile.dind                # + Docker Engine from the official docker:dind image
├── docker/
│   ├── install_packages.R         # CRAN + Bioconductor + CRAN Archive, with final check
│   ├── rsession.conf              # RStudio starts in /sharedFolder
│   ├── Rprofile.site              # same for terminal sessions
│   └── entrypoint-dind.sh         # starts the inner dockerd, then RStudio
├── .github/workflows/
│   └── docker-build.yml           # builds and publishes both images to ghcr.io
├── image.conf                     # which image the launchers pull
├── .gitattributes                 # line endings: LF for scripts, CRLF for .bat/.ps1
├── start.sh                       # launcher Linux + macOS
├── start_macos.command            # double-click launcher for macOS
├── start.ps1                      # launcher Windows
├── start.bat                      # double-click launcher for Windows
├── scripts/
│   └── 00_check_installation.R    # environment check + minimal example
└── data/
    ├── TestData/                  # tutorial data + gold standards
    └── ValidationData/            # validation data + gold standards
```

## Docker-in-Docker variant

`Dockerfile.dind` is a multi-stage build whose first stage **is the official
`docker:29-dind` image**: engine binaries, cli-plugins (buildx, compose), the
`dind` cgroup helper and the official `dockerd-entrypoint.sh` are copied from
there, so nothing Docker-related comes from apt. The host socket is never
mounted: the container runs its own `dockerd`. Useful if during the tutorial you
want to run other containers from inside RStudio.

```bash
./start.sh --dind
```

It requires `--privileged` (added by the launchers) and uses a dedicated volume
for `/var/lib/docker`, so inner images are not lost at every restart. The
entrypoint tries three strategies in order: official entrypoint with upstream
defaults (overlay2 when the kernel allows it), official entrypoint with
`--storage-driver=vfs`, plain `dockerd` with `vfs`. If none works, RStudio starts
anyway and the reason is printed by `docker logs cibb-2026-dind`.

From the RStudio terminal inside the container:

```bash
docker info
docker run --rm hello-world
```

`FROM docker:dind` directly is not possible: that image is Alpine/musl and
RStudio Server has no musl build, so R and RStudio could not run in it.

## Requirements

| | |
|---|---|
| Docker | Docker Desktop ≥ 4.x (Windows/macOS) or Docker Engine ≥ 20.10 (Linux) |
| Disk | ~25 GB free (~8 GB the image, the rest for Docker's own storage) |
| RAM | 8 GB minimum, 16 GB recommended (WGCNA and `huge`/`glasso` on real data) |
| Port | 8888 on localhost, changeable |

On Windows, Docker Desktop must use the WSL2 backend, which is the default.

## Troubleshooting

**"docker: command not found" or the daemon does not answer** — start Docker
Desktop and wait until it reports the engine is running; on Linux
`sudo systemctl start docker` and check that you are in the `docker` group.

**401 / denied while pulling the image** — the GHCR package is still private: it
must be made public (see below), or `docker login ghcr.io` with a personal access
token with `read:packages`.

**Port 8888 already in use** — `./start.sh --port 9999`.

**The page does not load right after the script ends** — RStudio takes a few
seconds, reload. If it keeps failing, `./start.sh --logs`.

**"invalid mount config" or the folder is not visible in RStudio** — on macOS add
the path in *Docker Desktop > Settings > Resources > File sharing*; on Windows
check that the disk is shared and that the path is not a network (UNC) path.
Paths with spaces are fine; paths with accents, `$`, `&` or `;` are best avoided.

**Permission denied when saving in `/sharedFolder` (Linux)** — the folder must be
writable by your user, check with `ls -ld .`.

**`bad interpreter: /usr/bin/env bash^M`** — the scripts were saved with Windows
line endings. The `.gitattributes` file prevents this; if it happens anyway:
`dos2unix start.sh docker/entrypoint-dind.sh`.

**Out of disk space during the build** — `docker system prune -af`, and check
with `docker system df`.

## Full reset

```bash
./start.sh --stop
docker rmi ghcr.io/younginfolife/cibb_2026:latest
docker volume rm cibb-2026-dind-docker-lib   # dind variant only
```

---

## For the repository maintainer

The images are built and published by the GitHub Action in
`.github/workflows/docker-build.yml`, which names them after the repository
itself (`ghcr.io/<owner>/<repository>`, lowercased). No need to edit the
workflow, no secrets required: `GITHUB_TOKEN` is enough.

One-time tasks:

1. Make the package public, otherwise students get a 401:
   **repository > Packages > cibb_2026 > Package settings > Change visibility >
   Public**.
2. Check that `image.conf` contains `IMAGE_REPO=ghcr.io/younginfolife/cibb_2026`.
   It is the only file the launchers read to know which image to pull, and the
   only one to change if the repository is renamed or moved.
3. Make sure the scripts carry the executable bit in the repository (`100755`,
   not `100644`):
   ```bash
   git update-index --chmod=+x start.sh start_macos.command docker/entrypoint-dind.sh
   ```

Resolution order in both launchers: environment variable > `image.conf` > git
remote of the clone > built-in default.

```bash
IMAGE_REPO=ghcr.io/other/other ./start.sh   # one-off override
```

The first build on Actions takes about an hour. The job summary prints the exact
`docker pull` lines.

To change the R version without touching the Dockerfile:

```bash
R_VERSION=4.5.3 ./start.sh --build
docker build --build-arg R_VERSION=4.5.3 --build-arg BIOC_VERSION=3.22 -t cibb2026:latest .
```

Building both images locally:

```bash
docker build --build-arg R_VERSION=4.6.1 -t cibb2026:latest .

docker build -f Dockerfile.dind \
  --build-arg BASE_IMAGE=cibb2026:latest \
  --build-arg DIND_IMAGE=docker:29-dind \
  -t cibb2026:dind .
```

## License

MIT for the code in this repository. The R packages and the base image
(`rocker/rstudio`) keep their own licenses.
