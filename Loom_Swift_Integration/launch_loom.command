#!/bin/bash
# launch_loom.command
# Double-click in Finder to build and launch the integrated Loom app.
# First run compiles — this may take a minute.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting Loom from $SCRIPT_DIR"
echo "(First run compiles — this may take a minute)"
echo ""

swift run Loom
