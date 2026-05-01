#!/bin/bash
# open_in_xcode.command
# Double-click in Finder to open this package in Xcode.
# Xcode 13+ opens SPM packages directly from Package.swift.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

xed .
