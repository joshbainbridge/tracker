#!/usr/bin/env bash
set -euo pipefail

SCREENSHOT_DIR="${SCREENSHOT_DIR:-/tmp/time-tracker}"
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/.time-tracker/activity-snapshots.json}"

# Create output directory and file if they don't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"
if [ ! -f "$OUTPUT_FILE" ]; then
  echo '{}' > "$OUTPUT_FILE"
fi

# Make sure screenshots directory exists
mkdir -p "$SCREENSHOT_DIR"

# Process all screenshots (not just current hour)
for screenshot in "$SCREENSHOT_DIR"/*.png; do
  # Skip if no matches found
  [ -e "$screenshot" ] || continue
  
  # Extract timestamp from filename
  filename=$(basename "$screenshot")
  timestamp="${filename%.png}"
  
  # Get screenshot summary using ollama
  summary=$(ollama run gemma3:27b-it-qat "Give a single estimate of what the user is actively doing in this screenshot. RETURN ONLY ONE BLOCK OF TEXT. NO MORE THAN 400 CHARACTERS. $screenshot")
  
  # Add to JSON file
  temp_file=$(mktemp)
  jq --arg timestamp "$timestamp" --arg summary "$summary" '. + {($timestamp): $summary}' "$OUTPUT_FILE" > "$temp_file"
  mv "$temp_file" "$OUTPUT_FILE"
  
  # Delete processed screenshot
  rm "$screenshot"
done
