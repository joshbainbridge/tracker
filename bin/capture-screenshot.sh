#!/usr/bin/env bash
set -euo pipefail

# Simple script to capture screenshots
SCREENSHOT_DIR="${SCREENSHOT_DIR:-/tmp/time-tracker}"
mkdir -p "$SCREENSHOT_DIR"

# Take screenshot with screencapture
FILENAME="$SCREENSHOT_DIR/$(date +"%Y-%m-%d-%H-%M-%S").png"
screencapture -x -C "$FILENAME"
