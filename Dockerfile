# ---------------------------------------------------------------------------
# RNA-seq preprocessing + network reverse engineering  --  RStudio Server image
#
# Base: rocker/rstudio, where R is compiled/installed by the rocker scripts,
# NOT taken from the Ubuntu apt archive. R 4.6.1 is the current release
# (2026-06-24).
#
#   build:  docker build -t rnaseq-nets:latest .
#   run  :  docker run --rm -p 8888:8787 -e DISABLE_AUTH=true \
#              -v "$PWD:/sharedFolder" rnaseq-nets:latest
#   open :  http://localhost:8888
# ---------------------------------------------------------------------------
ARG R_VERSION=4.6.1
FROM rocker/rstudio:${R_VERSION}

# Bioconductor release to use. Leave empty to let BiocManager pick the one
# matching the R version (3.23 for R 4.6.x), or pin it explicitly, e.g.
#   docker build --build-arg BIOC_VERSION=3.23 .
ARG BIOC_VERSION=""

LABEL org.opencontainers.image.title="rnaseq-nets" \
      org.opencontainers.image.description="RStudio Server with RNA-seq preprocessing and gene network reverse-engineering R packages" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Rome \
    LANG=C.UTF-8 \
    BIOC_VERSION=${BIOC_VERSION}

# --- system libraries needed to compile the R packages ---------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gfortran \
        cmake \
        pkg-config \
        git \
        curl \
        wget \
        nano \
        less \
        unzip \
        pandoc \
        libxml2-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libgit2-dev \
        libglpk-dev \
        libgmp-dev \
        libmpfr-dev \
        libpng-dev \
        libjpeg-dev \
        libtiff5-dev \
        libfreetype6-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libblas-dev \
        liblapack-dev \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libhdf5-dev \
        libudunits2-dev \
        libgdal-dev \
    && rm -rf /var/lib/apt/lists/*

# --- R packages ------------------------------------------------------------
COPY docker/install_packages.R /tmp/install_packages.R
RUN Rscript /tmp/install_packages.R && rm -rf /tmp/* /var/tmp/*

# --- RStudio behaviour ----------------------------------------------------
# session-default-working-dir makes RStudio start directly inside the folder
# shared from the host.
COPY docker/rsession.conf /etc/rstudio/rsession.conf
COPY docker/Rprofile.site /usr/local/lib/R/etc/Rprofile.site

RUN mkdir -p /sharedFolder && chmod 777 /sharedFolder

# no login: the launcher scripts pass -e DISABLE_AUTH=true, this is the default
ENV DISABLE_AUTH=true \
    ROOT=true

WORKDIR /sharedFolder
EXPOSE 8787

# the rocker entrypoint (/init) fixes the uid/gid of user `rstudio` when
# USERID / GROUPID are provided and then starts RStudio Server
CMD ["/init"]
