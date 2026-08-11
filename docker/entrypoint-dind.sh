#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Starts the inner Docker daemon and then hands over to the rocker init system
# that launches RStudio Server.
#
# The daemon is the one copied from the official docker:dind image, and it is
# started through the official `dockerd-entrypoint.sh` so that cgroups,
# iptables and the storage driver are set up exactly as upstream does it.
# No host socket is mounted: this is real docker-in-docker and needs
# --privileged.
# ---------------------------------------------------------------------------
set -e

DOCKERD_LOG=/var/log/dockerd.log
DOCKERD_TIMEOUT="${DOCKERD_TIMEOUT:-90}"
: > "${DOCKERD_LOG}" || true

wait_for_dockerd() {
    local pid="$1" waited=0
    while [ "${waited}" -lt "${DOCKERD_TIMEOUT}" ]; do
        if docker info >/dev/null 2>&1; then
            echo "[dind] dockerd is up ($(docker version --format '{{.Server.Version}}' 2>/dev/null))"
            return 0
        fi
        if ! kill -0 "${pid}" 2>/dev/null; then
            echo "[dind] dockerd exited"
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "[dind] timeout after ${DOCKERD_TIMEOUT}s"
    kill "${pid}" 2>/dev/null || true
    return 1
}

try_start() {
    # $@ : extra flags for dockerd
    echo "[dind] starting: dockerd-entrypoint.sh dockerd $*"
    /usr/local/bin/dockerd-entrypoint.sh dockerd \
        --host=unix:///var/run/docker.sock \
        --group=docker \
        "$@" >>"${DOCKERD_LOG}" 2>&1 &
    wait_for_dockerd "$!"
}

try_start_raw() {
    # fallback: skip the official entrypoint and call dockerd directly
    echo "[dind] starting dockerd directly $*"
    dockerd --host=unix:///var/run/docker.sock --group=docker "$@" \
        >>"${DOCKERD_LOG}" 2>&1 &
    wait_for_dockerd "$!"
}

if [ -S /var/run/docker.sock ] && docker info >/dev/null 2>&1; then
    echo "[dind] a working docker socket is already present, not starting dockerd"
else
    rm -f /var/run/docker.pid /var/run/docker.sock 2>/dev/null || true

    # 1. upstream defaults (overlay2 when the kernel allows it)
    # 2. upstream + vfs (always works, slower, more disk)
    # 3. plain dockerd + vfs
    if ! try_start; then
        rm -f /var/run/docker.pid /var/run/docker.sock 2>/dev/null || true
        echo "[dind] retrying with --storage-driver=vfs"
        if ! try_start --storage-driver=vfs; then
            rm -f /var/run/docker.pid /var/run/docker.sock 2>/dev/null || true
            echo "[dind] retrying without the official entrypoint"
            if ! try_start_raw --storage-driver=vfs; then
                echo "[dind] WARNING: the inner Docker daemon could not be started."
                echo "[dind] Was the container run with --privileged ?"
                echo "[dind] Last lines of ${DOCKERD_LOG}:"
                tail -n 40 "${DOCKERD_LOG}" 2>/dev/null || true
                echo "[dind] Continuing anyway: RStudio will work, docker will not."
            fi
        fi
    fi
fi

# keep the rstudio user in the docker group even if the gid changed at runtime
if getent group docker >/dev/null 2>&1; then
    usermod -aG docker rstudio 2>/dev/null || true
fi
chmod 660 /var/run/docker.sock 2>/dev/null || true
chgrp docker /var/run/docker.sock 2>/dev/null || true

echo "[dind] handing over to: $*"
exec "$@"
