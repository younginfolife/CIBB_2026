#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Double-clickable wrapper for macOS: opens a Terminal window and runs
# start.sh from the folder that contains this file. Nothing more.
# ---------------------------------------------------------------------------
DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1
"$DIR/start.sh" "$@"
status=$?
echo
echo "Press ENTER to close this window."
read -r _
exit $status
