#!/usr/bin/env bash
set -euo pipefail

SCREENSHOT_DIR="${SCREENSHOT_DIR:-/tmp/time-tracker}"
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/.time-tracker/activity-snapshots.json}"
USER_CONTEXT_FILE="${USER_CONTEXT_FILE:-$HOME/.time-tracker/user-context.txt}"

# Create output directory and file if they don't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"
if [ ! -f "$OUTPUT_FILE" ]; then
  echo '{}' > "$OUTPUT_FILE"
fi

# Make sure screenshots directory exists
mkdir -p "$SCREENSHOT_DIR"

# Read user context if available
USER_CONTEXT=""
if [ -f "$USER_CONTEXT_FILE" ]; then
  USER_CONTEXT="User context: $(cat "$USER_CONTEXT_FILE")"
fi

# Process all screenshots (not just current hour)
for screenshot in "$SCREENSHOT_DIR"/*.png; do
  # Skip if no matches found
  [ -e "$screenshot" ] || continue
  
  # Extract timestamp from filename
  filename=$(basename "$screenshot")
  timestamp="${filename%.png}"

  PROMT=$(cat << EOF
Give a single estimate of what the user is actively doing in this screenshot.
Be concise (max 400 characters). A single block of text.

User context:

$USER_CONTEXT

Screenshot:

$screenshot
EOF
)
  
  # Get screenshot summary using ollama
  summary=$(ollama run gemma3:27b-it-qat "$PROMT")
  
  # Add to JSON file
  temp_file=$(mktemp)
  jq --arg timestamp "$timestamp" --arg summary "$summary" '. + {($timestamp): $summary}' "$OUTPUT_FILE" > "$temp_file"
  mv "$temp_file" "$OUTPUT_FILE"
  
  # Delete processed screenshot
  rm "$screenshot"
done
