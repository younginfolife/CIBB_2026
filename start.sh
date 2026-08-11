#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# rnaseq-nets : launcher for Linux and macOS
#
#   ./start.sh                 start RStudio Server on http://localhost:8888
#   ./start.sh --dind          start the docker-in-docker variant (privileged)
#   ./start.sh --port 9999     use another host port
#   ./start.sh --build         build the image locally instead of pulling it
#   ./start.sh --stop          stop and remove the container
#   ./start.sh --logs          follow the container logs
#   ./start.sh --shell         open a bash shell inside the running container
#
# The folder containing this script is shared with the container in
# /sharedFolder, and RStudio starts there.
# ---------------------------------------------------------------------------
set -euo pipefail

# --- where am I ? (handles spaces and symlinks in the path) -----------------
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    case "$SOURCE" in
        /*) ;;
        *) SOURCE="$DIR/$SOURCE" ;;
    esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SHARED_DIR="$SCRIPT_DIR"

# --- configuration ---------------------------------------------------------
# Order of precedence: environment variables > image.conf > git remote > default
CONF_IMAGE_REPO=""
CONF_TAG_STD=""
CONF_TAG_DIND=""
CONF_R_VERSION=""
CONF_DIND_IMAGE=""

if [ -f "$SCRIPT_DIR/image.conf" ]; then
    while IFS='=' read -r key value; do
        key="${key%%#*}"; key="$(printf '%s' "$key" | tr -d '[:space:]')"
        value="$(printf '%s' "$value" | tr -d '[:space:]')"
        [ -n "$key" ] || continue
        case "$key" in
            IMAGE_REPO) CONF_IMAGE_REPO="$value" ;;
            TAG_STD)    CONF_TAG_STD="$value" ;;
            TAG_DIND)   CONF_TAG_DIND="$value" ;;
            R_VERSION)  CONF_R_VERSION="$value" ;;
            DIND_IMAGE) CONF_DIND_IMAGE="$value" ;;
        esac
    done < "$SCRIPT_DIR/image.conf"
fi

# if image.conf is missing, derive owner/repo from the git remote of the clone
if [ -z "$CONF_IMAGE_REPO" ] && command -v git >/dev/null 2>&1; then
    REMOTE="$(git -C "$SCRIPT_DIR" config --get remote.origin.url 2>/dev/null || true)"
    if [ -n "$REMOTE" ]; then
        SLUG="$(printf '%s' "$REMOTE" \
                | sed -e 's#^git@github.com:#https://github.com/#' \
                      -e 's#^https\{0,1\}://[^/]*/##' -e 's#\.git$##')"
        case "$SLUG" in
            */*) CONF_IMAGE_REPO="ghcr.io/$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]')" ;;
        esac
    fi
fi

IMAGE_REPO="${IMAGE_REPO:-${CONF_IMAGE_REPO:-ghcr.io/reproduciblebioinformatics/rnaseq-nets}}"
TAG_STD="${TAG_STD:-${CONF_TAG_STD:-latest}}"
TAG_DIND="${TAG_DIND:-${CONF_TAG_DIND:-dind}}"
CONTAINER_NAME="${CONTAINER_NAME:-rnaseq-nets}"
PORT="${PORT:-8888}"
MIN_FREE_GB="${MIN_FREE_GB:-25}"
R_VERSION="${R_VERSION:-${CONF_R_VERSION:-4.6.1}}"
DIND_IMAGE="${DIND_IMAGE:-${CONF_DIND_IMAGE:-docker:29-dind}}"

MODE="standard"
DO_BUILD=0
ACTION="start"
IMAGE_OVERRIDE=""

# --- colours (disabled if not a tty) ---------------------------------------
if [ -t 1 ]; then
    C_R="$(printf '\033[31m')"; C_G="$(printf '\033[32m')"
    C_Y="$(printf '\033[33m')"; C_B="$(printf '\033[1m')"
    C_0="$(printf '\033[0m')"
else
    C_R=""; C_G=""; C_Y=""; C_B=""; C_0=""
fi
info()  { printf '%s[info]%s %s\n'  "$C_G" "$C_0" "$*"; }
warn()  { printf '%s[warn]%s %s\n'  "$C_Y" "$C_0" "$*" >&2; }
err()   { printf '%s[error]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()   { err "$*"; exit 1; }

usage() {
    awk 'NR > 1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
    exit 0
}

# --- arguments -------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --dind|-d)   MODE="dind" ;;
        --port|-p)   shift; [ $# -gt 0 ] || die "--port requires a value"; PORT="$1" ;;
        --build|-b)  DO_BUILD=1 ;;
        --image|-i)  shift; [ $# -gt 0 ] || die "--image requires a value"; IMAGE_OVERRIDE="$1" ;;
        --stop|stop) ACTION="stop" ;;
        --logs|logs) ACTION="logs" ;;
        --shell|shell) ACTION="shell" ;;
        --help|-h)   usage ;;
        *)           die "unknown option: $1  (try --help)" ;;
    esac
    shift
done

if [ "$MODE" = "dind" ]; then
    IMAGE="${IMAGE_REPO}:${TAG_DIND}"
    CONTAINER_NAME="${CONTAINER_NAME}-dind"
else
    IMAGE="${IMAGE_REPO}:${TAG_STD}"
fi
[ -n "$IMAGE_OVERRIDE" ] && IMAGE="$IMAGE_OVERRIDE"

# --- docker available ? ----------------------------------------------------
command -v docker >/dev/null 2>&1 || die "docker is not installed or not in PATH.
  Linux : https://docs.docker.com/engine/install/
  macOS : https://www.docker.com/products/docker-desktop/"

if ! docker info >/dev/null 2>&1; then
    die "the Docker daemon is not responding.
  macOS : start Docker Desktop and wait until the whale icon stops animating.
  Linux : sudo systemctl start docker   (and check that your user is in the 'docker' group)"
fi

# --- secondary actions -----------------------------------------------------
case "$ACTION" in
    stop)
        if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
            info "stopping $CONTAINER_NAME ..."
            docker rm -f "$CONTAINER_NAME" >/dev/null
            info "done."
        else
            info "no container named $CONTAINER_NAME."
        fi
        exit 0 ;;
    logs)
        exec docker logs -f "$CONTAINER_NAME" ;;
    shell)
        exec docker exec -it "$CONTAINER_NAME" bash ;;
esac

# --- checks on the shared folder ------------------------------------------
info "image         : $IMAGE"
info "shared folder : $SHARED_DIR"

[ -d "$SHARED_DIR" ] || die "the folder to share does not exist: $SHARED_DIR"
[ -r "$SHARED_DIR" ] || die "the folder to share is not readable: $SHARED_DIR"
if [ ! -w "$SHARED_DIR" ]; then
    warn "the folder is NOT writable by your user: RStudio will not be able to save files there."
fi

case "$SHARED_DIR" in
    *" "*) warn "the path contains spaces. It is handled by this script (everything is quoted),
       but avoid renaming folders while the container is running." ;;
esac

# non-ASCII characters in the path (accents, etc.) can confuse some Docker setups
if printf '%s' "$SHARED_DIR" | LC_ALL=C grep -q '[^ -~]'; then
    warn "the path contains non-ASCII characters (accents/special chars).
       If the mount fails, move the folder to a simple path, e.g. \$HOME/rnaseq-nets."
fi

case "$SHARED_DIR" in
    *[\'\"\`\$\;\&\|\<\>\*\?]*)
        warn "the path contains shell metacharacters (quotes, \$, ;, &, *, ...).
       Docker may refuse the bind mount: consider moving the folder." ;;
esac

# Docker Desktop on macOS only shares some paths by default
if [ "$(uname -s)" = "Darwin" ]; then
    case "$SHARED_DIR" in
        "$HOME"/*|/Users/*|/Volumes/*|/tmp/*|/private/*) ;;
        *) warn "on macOS, Docker Desktop shares by default only /Users, /Volumes, /tmp and /private.
       If the mount fails, add this path in Docker Desktop > Settings > Resources > File sharing." ;;
    esac
fi

# --- free disk space -------------------------------------------------------
FREE_GB="$(df -Pk "$SHARED_DIR" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024/1024}')"
if [ -n "${FREE_GB:-}" ]; then
    info "free space on that filesystem : ${FREE_GB} GB"
    if [ "$FREE_GB" -lt "$MIN_FREE_GB" ]; then
        warn "less than ${MIN_FREE_GB} GB free. The image is large (~5-8 GB, more for the dind variant)
       and Docker also needs room for its own storage (on macOS: ~/Library/Containers/com.docker.docker)."
    fi
else
    warn "could not determine the free space on $SHARED_DIR."
fi

# --- host port free ? ------------------------------------------------------
port_in_use() {
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    elif command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$" && return 0
    elif command -v netstat >/dev/null 2>&1; then
        netstat -an 2>/dev/null | grep -i listen | grep -qE "[:.]$1[[:space:]]" && return 0
    fi
    return 1
}

if port_in_use "$PORT"; then
    if docker ps --format '{{.Names}} {{.Ports}}' | grep -q "^${CONTAINER_NAME} .*:${PORT}->"; then
        info "the container $CONTAINER_NAME is already running on port $PORT."
        info "open http://localhost:${PORT}   (stop it with: $0 --stop)"
        exit 0
    fi
    die "host port $PORT is already in use by another process.
  Use another port:  $0 --port 9999"
fi

# --- remove a stale container with the same name ---------------------------
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    info "removing the previous container $CONTAINER_NAME ..."
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# --- build or pull the image ----------------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
    info "building the image locally (30-60 minutes the first time) ..."
    docker build \
        --build-arg R_VERSION="${R_VERSION}" \
        -t "${IMAGE_REPO}:${TAG_STD}" "$SCRIPT_DIR"
    if [ "$MODE" = "dind" ]; then
        docker build \
            -f "$SCRIPT_DIR/Dockerfile.dind" \
            --build-arg BASE_IMAGE="${IMAGE_REPO}:${TAG_STD}" \
            --build-arg DIND_IMAGE="${DIND_IMAGE}" \
            -t "${IMAGE_REPO}:${TAG_DIND}" \
            "$SCRIPT_DIR"
    fi
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    info "pulling $IMAGE (several GB, be patient) ..."
    if [ "$MODE" = "dind" ]; then
        BUILD_HINT="$0 --build --dind"
    else
        BUILD_HINT="$0 --build"
    fi
    docker pull "$IMAGE" || die "pull failed.
  Check the image name, or build it locally with:  ${BUILD_HINT}"
else
    info "image already present locally : $IMAGE"
fi

# --- run -------------------------------------------------------------------
RUN_ARGS=(
    -d
    --name "$CONTAINER_NAME"
    --hostname rnaseq-nets
    -p "127.0.0.1:${PORT}:8787"
    -e DISABLE_AUTH=true
    -e ROOT=true
    -e "TUTORIAL_SHARED_DIR=/sharedFolder"
    -v "${SHARED_DIR}:/sharedFolder"
    --shm-size=2g
)

# On Linux the container user must have the same uid/gid as the host user,
# otherwise files written in /sharedFolder end up owned by someone else.
# On macOS Docker Desktop already maps ownership, and gid 20 clashes with an
# existing group inside the image, so it is skipped there.
if [ "$(uname -s)" = "Linux" ]; then
    RUN_ARGS+=( -e USERID="$(id -u)" -e GROUPID="$(id -g)" )
fi

if [ "$MODE" = "dind" ]; then
    warn "the dind variant needs --privileged (its own Docker daemon runs inside the container)."
    RUN_ARGS+=( --privileged -v "${CONTAINER_NAME}-docker-lib:/var/lib/docker" )
fi

info "starting the container ..."
docker run "${RUN_ARGS[@]}" "$IMAGE" >/dev/null

# --- wait for RStudio to answer -------------------------------------------
info "waiting for RStudio Server ..."
i=0
while [ "$i" -lt 90 ]; do
    if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
        err "the container stopped unexpectedly. Logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -n 40
        exit 1
    fi
    if curl -fsS -o /dev/null "http://localhost:${PORT}" 2>/dev/null; then
        break
    fi
    sleep 2
    i=$((i + 2))
done

printf '\n%s========================================================%s\n' "$C_B" "$C_0"
printf '  RStudio Server : %shttp://localhost:%s%s\n' "$C_B" "$PORT" "$C_0"
printf '  login          : not required (DISABLE_AUTH)\n'
printf '  shared folder  : %s  ->  /sharedFolder\n' "$SHARED_DIR"
printf '  container      : %s\n' "$CONTAINER_NAME"
printf '%s========================================================%s\n\n' "$C_B" "$C_0"
printf '  logs  : %s --logs\n' "$0"
printf '  shell : %s --shell\n' "$0"
printf '  stop  : %s --stop\n\n' "$0"

# --- try to open the browser ----------------------------------------------
if [ "${NO_BROWSER:-0}" != "1" ]; then
    if command -v open >/dev/null 2>&1; then
        open "http://localhost:${PORT}" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "http://localhost:${PORT}" >/dev/null 2>&1 || true
    fi
fi
