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
USER_CONTEXT="No context provided."
if [ -f "$USER_CONTEXT_FILE" ]; then
  USER_CONTEXT="User context: $(cat "$USER_CONTEXT_FILE")"
fi

# Get all unique timestamps from screenshots
timestamps=$(find "$SCREENSHOT_DIR" -type f | sed -En 's|.*/([0-9]+(-[0-9]+){5})-[1234]+\.png$|\1|p' | sort -u)

# Process screenshots by timestamp
for timestamp in $timestamps; do
  # Collect all screenshots for this timestamp
  screenshots=$(find "$SCREENSHOT_DIR" -type f -name "$timestamp-*.png")

  PROMT=$(cat << EOF
Give a single estimate of what the user is actively doing across all these
screenshots. These are different displays captured at the same moment in time.
Be concise (max 400 characters). A single block of text.

User context:

$USER_CONTEXT

Screenshots:

$screenshots
EOF
)

  # Get screenshot summary using ollama
  summary=$(ollama run gemma3:27b-it-qat "$PROMT")

  # Add to JSON file
  temp_file=$(mktemp)
  jq --arg timestamp "$timestamp" --arg summary "$summary" '. + {($timestamp): $summary}' "$OUTPUT_FILE" > "$temp_file"
  mv "$temp_file" "$OUTPUT_FILE"

  # Delete processed screenshots
  for screenshot in $screenshots; do
    rm "$screenshot"
  done
done
