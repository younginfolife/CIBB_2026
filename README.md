# rnaseq-nets

RStudio Server in a container with everything needed to go from raw RNA-seq
counts to co-expression and regulatory networks, comparing different
methodological approaches.

Built for the Rome tutorial and for the RNA-seq reverse-engineering project.
Students only need Docker: they clone this repository, double-click one script,
and get RStudio at <http://localhost:8888> with no login and with the
repository folder already mounted and set as working directory.

---

## Guida rapida (IT)

1. Installa Docker (Docker Desktop su Windows/macOS, `docker` da pacchetti su Linux).
2. Scarica questa repository (bottone verde **Code > Download ZIP**, poi estrai,
   oppure `git clone`).
3. Avvia:
   * **Windows** → doppio clic su `start.bat`
   * **macOS** → doppio clic su `start_macos.command`
   * **Linux** → da terminale `./start.sh`
4. Si apre il browser su <http://localhost:8888>. Nessun login.
5. La cartella della repository è dentro il container in `/sharedFolder` ed è
   già la working directory di RStudio: i dati in `data/` sono subito visibili
   e tutto quello che salvi resta sul tuo computer.
6. Per fermare tutto: `./start.sh --stop` (Windows: `start.bat -Stop`).

Primo avvio: il download dell'immagine è di alcuni GB, servono ~25 GB liberi.

---

## Setting up the repository (for the maintainer, once)

1. Create the repository on GitHub and push this content. The workflow names the
   images after the repository itself
   (`ghcr.io/<owner>/<repository>:latest` and `:dind`), lowercased — there is
   nothing to edit in the workflow.
2. Wait for **Actions** to finish (~1 h the first time). At the end, the job
   summary prints the exact `docker pull` lines and the `IMAGE_REPO` value.
3. Make the package public, otherwise students get a 401 on pull:
   **repository > Packages > rnaseq-nets > Package settings > Change visibility
   > Public**.
4. Copy that `IMAGE_REPO` line into **`image.conf`** and push again. This is the
   only file the launchers read to know which image to pull, and the only one to
   edit if you rename the repo or the owner.
5. Preserve the executable bit before the first push:
   ```bash
   git update-index --chmod=+x start.sh start_macos.command docker/entrypoint-dind.sh
   ```
6. Drop the tutorial data in `data/` and push.

If `image.conf` is missing or has no `IMAGE_REPO`, the scripts fall back to the
`origin` remote of the clone (`git@github.com:Owner/Repo.git` →
`ghcr.io/owner/repo`), which works for anyone who cloned with git but not for
students who downloaded the ZIP. So keep `image.conf` filled in.

Resolution order in both launchers: environment variable > `image.conf` >
git remote > built-in default.

```bash
IMAGE_REPO=ghcr.io/someone/something ./start.sh   # one-off override
```

## Requirements

| | |
|---|---|
| Docker | Docker Desktop ≥ 4.x (Windows/macOS) or Docker Engine ≥ 20.10 (Linux) |
| Disk | ~25 GB free (~8 GB the image, the rest for Docker's own storage) |
| RAM | 8 GB minimum, 16 GB recommended (WGCNA and `huge`/`glasso` on real data) |
| Ports | 8888 on localhost (changeable) |

On Windows, Docker Desktop must be using the WSL2 backend (the default).

## Quick start

```bash
git clone https://github.com/<owner>/<repository>.git
cd <repository>
./start.sh            # Linux / macOS
```

Windows (PowerShell or double click on `start.bat`):

```powershell
.\start.ps1
```

Then open <http://localhost:8888>. There is no username and no password
(`DISABLE_AUTH=true`).

If the scripts are not executable (typical when the repo is downloaded as ZIP):

```bash
chmod +x start.sh start_macos.command docker/entrypoint-dind.sh
```

When you first push the repository, make sure the executable bit is recorded in
git, otherwise every student has to run the `chmod` above:

```bash
git update-index --chmod=+x start.sh start_macos.command docker/entrypoint-dind.sh
```

First thing to run inside RStudio, to verify the environment:

```r
source("/sharedFolder/scripts/00_check_installation.R")
```

## Launcher options

| Linux / macOS | Windows | What it does |
|---|---|---|
| `./start.sh` | `.\start.ps1` | start the container |
| `./start.sh --port 9999` | `.\start.ps1 -Port 9999` | use another host port |
| `./start.sh --dind` | `.\start.ps1 -Dind` | docker-in-docker variant |
| `./start.sh --build` | `.\start.ps1 -Build` | build the image locally instead of pulling |
| `./start.sh --stop` | `.\start.ps1 -Stop` | stop and remove the container |
| `./start.sh --logs` | `.\start.ps1 -Logs` | follow the container logs |
| `./start.sh --shell` | `.\start.ps1 -Shell` | bash shell inside the container |

Before starting, the scripts check that: Docker is installed and the daemon is
answering; the folder exists, is readable and writable; the path does not
contain characters that break bind mounts (spaces are handled — everything is
quoted — but non-ASCII characters, UNC paths and shell metacharacters produce a
warning); there is enough free disk space; and the host port is free.

## The shared folder

The folder **containing the launcher script** (i.e. the repository root) is
mounted in the container as `/sharedFolder`, and RStudio starts there
(`session-default-working-dir` in `docker/rsession.conf`, plus a `setwd()` in
`Rprofile.site` for terminal sessions).

```
your machine                          container
rnaseq-nets/            <------->     /sharedFolder/
├── data/                             ├── data/
├── scripts/                          ├── scripts/
└── ...                               └── ...
```

Everything written there survives the container. Everything written elsewhere
(e.g. `/home/rstudio`) is lost when the container is removed.

On Linux the container user is remapped to your uid/gid (`USERID`/`GROUPID`), so
new files belong to you. On macOS and Windows, Docker Desktop already handles
ownership and the remapping is skipped on purpose (gid 20 on macOS collides with
an existing group inside the image).

## Docker-in-Docker variant

`Dockerfile.dind` is a multi-stage build whose first stage **is the official
`docker:29-dind` image**: engine binaries, cli-plugins (buildx, compose), the
`dind` cgroup helper and the official `dockerd-entrypoint.sh` are copied from
there, so nothing Docker-related comes from apt. No host socket is mounted
(`/var/run/docker.sock` is never shared): the container runs its own `dockerd`.
Useful if during the tutorial you want to run other containers
(e.g. CREDO/rCASC-style workflows) from inside RStudio.

`FROM docker:dind` directly is not possible here: that image is Alpine/musl and
RStudio Server has no musl build, so R + RStudio could not run in it. Copying
the engine out of it gives the same Docker version and the same startup logic on
a glibc base.

```bash
./start.sh --dind
```

It requires `--privileged` (added automatically by the launchers) and a named
volume for `/var/lib/docker` so that inner images are not lost at every restart.
The entrypoint tries three strategies in order: official entrypoint with
upstream defaults (overlay2 when the kernel allows it), official entrypoint with
`--storage-driver=vfs`, plain `dockerd` with `vfs`. If none works, RStudio starts
anyway and the reason is printed in `docker logs rnaseq-nets-dind`.

Inside the container, from the RStudio terminal:

```bash
docker info
docker run --rm hello-world
```

## Versions

| | |
|---|---|
| R | 4.6.1 (current release, 2026-06-24) from `rocker/rstudio:4.6.1` |
| Bioconductor | the release matching R 4.6.x, chosen by BiocManager |
| Docker (dind variant) | from the official `docker:29-dind` image |

R is **not** the apt/Ubuntu one: the rocker images install the exact R version of
the tag. To change it, no need to edit the Dockerfile:

```bash
R_VERSION=4.5.3 ./start.sh --build
docker build --build-arg R_VERSION=4.5.3 --build-arg BIOC_VERSION=3.22 -t rnaseq-nets:latest .
```

The same applies to the engine used by the dind variant
(`DIND_IMAGE=docker:28-dind`). In CI both are set in the `env:` block of
`.github/workflows/docker-build.yml`.

## Installed packages

**Preprocessing / normalisation / batch correction**

`DESeq2` · `edgeR` · `limma` · `sva` · `RUVSeq` · `EDASeq` · `matrixStats` ·
`data.table` · `tidyverse`

**Reverse engineering / network inference**

`WGCNA` · `GENIE3` · `minet` (ARACNe, CLR, MRNET) · `GeneNet` · `huge` ·
`glasso` · `space` · `c3net` · `BDgraph` · `qgraph` · `igraph`

`space` and `c3net` are no longer in the active CRAN index and are installed
from the CRAN Archive (see `docker/install_packages.R`).

The full version manifest of the image is at `/opt/package_manifest.csv`:

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
│   └── entrypoint-dind.sh         # runs the official dockerd-entrypoint.sh, then RStudio
├── .github/workflows/
│   └── docker-build.yml           # builds and pushes both images to ghcr.io
├── image.conf                     # which image the launchers pull (edit this one)
├── start.sh                       # launcher Linux + macOS
├── start_macos.command            # double-clickable wrapper for macOS
├── start.ps1                      # launcher Windows
├── start.bat                      # double-clickable wrapper for Windows
├── scripts/
│   └── 00_check_installation.R    # environment check + minimal network example
└── data/                          # datasets of the tutorial (see data/README.md)
```

## Images

Prebuilt images are published on the GitHub Container Registry:

```
ghcr.io/<owner>/<repository>:latest
ghcr.io/<owner>/<repository>:dind
```

The exact names are printed in the workflow summary and stored in `image.conf`.
Forks work the same way: the workflow publishes under the fork's own
owner/repository, and the launchers pick it up from `image.conf` or from the git
remote.

The workflow needs no secrets (`GITHUB_TOKEN` is enough). The first run may take
~1 hour. Remember to set the package visibility to *public* so that students can
pull without logging in.

## Building locally

```bash
docker build --build-arg R_VERSION=4.6.1 -t rnaseq-nets:latest .

docker build -f Dockerfile.dind \
  --build-arg BASE_IMAGE=rnaseq-nets:latest \
  --build-arg DIND_IMAGE=docker:29-dind \
  -t rnaseq-nets:dind .

./start.sh --build --image rnaseq-nets:latest
```

## Troubleshooting

**"docker: command not found" / the daemon is not answering** — start Docker
Desktop and wait until the engine reports it is running; on Linux
`sudo systemctl start docker` and make sure your user is in the `docker` group.

**401 / denied when pulling** — the GHCR package is still private: set it to
public, or `docker login ghcr.io` with a personal access token (`read:packages`).

**Port 8888 already in use** — `./start.sh --port 9999`.

**The page does not load right after the script ends** — RStudio takes a few
seconds; reload. If it keeps failing, `./start.sh --logs`.

**"invalid mount config" / the folder is not visible in RStudio** — on macOS add
the path in *Docker Desktop > Settings > Resources > File sharing*; on Windows
check that the disk is shared and that the path is not a network (UNC) path.
Paths with spaces are fine; paths with accents, `$`, `&` or `;` are best avoided.

**Permission denied when saving in `/sharedFolder` (Linux)** — the folder must be
writable by your user; check with `ls -ld .`.

**`docker info` fails in the dind variant** — the container must be
`--privileged` (the launcher adds it) and the kernel must allow it; the
entrypoint log explains what failed.

**Out of disk space during the build** — `docker system prune -af` and check
`docker system df`.

## Reset

```bash
./start.sh --stop
docker rmi "$(grep '^IMAGE_REPO=' image.conf | cut -d= -f2):latest"
docker volume rm rnaseq-nets-dind-docker-lib   # only for the dind variant
```

## License

MIT for the code in this repository. The R packages and the base image
(`rocker/rstudio`) keep their own licenses.
