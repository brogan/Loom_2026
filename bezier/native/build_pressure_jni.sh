#!/bin/bash
# Build the pressure JNI native library for macOS arm64.
# Run this once from the bezier/native directory:
#   cd /Users/broganbunt/Loom_2026/bezier/native && bash build_pressure_jni.sh
#
# The resulting dylib is placed in bezier/libs/ where StylusPressureSource can find it.

set -e

JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null)
if [ -z "$JAVA_HOME" ]; then
    echo "Error: could not locate JAVA_HOME via /usr/libexec/java_home"
    exit 1
fi

OUT_DIR="$(dirname "$0")/../libs"
mkdir -p "$OUT_DIR"

clang -shared -fPIC \
    -I"${JAVA_HOME}/include" \
    -I"${JAVA_HOME}/include/darwin" \
    -framework Foundation \
    -framework AppKit \
    -arch arm64 \
    -o "${OUT_DIR}/libPressureJNI.dylib" \
    "$(dirname "$0")/PressureJNI.m"

echo "Built: ${OUT_DIR}/libPressureJNI.dylib"
