#!/bin/bash
# launch_loom_app.command
# Double-click in Finder to launch LoomApp.
# Opens in Terminal, builds if needed (first run), then starts the app.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting LoomApp from $SCRIPT_DIR"
echo "(First run compiles — this may take a minute)"
echo ""

swift run LoomApp
