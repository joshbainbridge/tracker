#!/usr/bin/env bash
set -euo pipefail

ACTIVITY_DIR="${ACTIVITY_DIR:-/tmp/time-tracker}"
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/.time-tracker/activity-snapshots.json}"
USER_CONTEXT_FILE="${USER_CONTEXT_FILE:-$HOME/.time-tracker/user-context.txt}"

# Create output directory and file if they don't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"
if [ ! -f "$OUTPUT_FILE" ]; then
  echo '{}' > "$OUTPUT_FILE"
fi

# Make sure activity directory exists
mkdir -p "$ACTIVITY_DIR"

# Read user context if available
USER_CONTEXT="No context provided."
if [ -f "$USER_CONTEXT_FILE" ]; then
  USER_CONTEXT="User context: $(cat "$USER_CONTEXT_FILE")"
fi

# Get all unique timestamps from activity snapshots
timestamps=$(find "$ACTIVITY_DIR" -type f | sed -En 's|.*/([0-9]+(-[0-9]+){5})\.txt$|\1|p' | sort -u)

# Process activity snapshots by timestamp
for timestamp in $timestamps; do
  # Find past activity (up to 5 entries)
  past=$(jq -r --arg current "$timestamp" \
  'to_entries| map(select(.key < $current)) | sort_by(.key) | .[-5:][] | "\(.key) - \(.value)"' \
  "$OUTPUT_FILE")

  # Collect all files for this activity timestamp
  screenshots=$(find "$ACTIVITY_DIR" -type f -name "$timestamp-*.png")
  textdata=$(find "$ACTIVITY_DIR" -type f -name "$timestamp.txt")

  # Get text data about active window
  window=$(cat "$textdata")

  PROMT=$(cat << EOF
Give a single estimate of what the user is actively doing across all these
screenshots. These are different displays captured at the same moment in time.
Be concise (max 400 characters). A single block of text.

User context:

$USER_CONTEXT

Past activity (newest first):

$past

Screenshots:

$screenshots

Active window:

$window
EOF
)

  # Get screenshot summary using ollama
  summary=$(ollama run gemma3:27b-it-qat "$PROMT")

  # Read existing JSON and add summary
  json=$(jq --arg timestamp "$timestamp" --arg summary "$summary" \
  '. + {($timestamp): $summary}' \
  "$OUTPUT_FILE")

  # Output to JSON file
  echo "$json" > "$OUTPUT_FILE"

  # Delete processed screenshots
  rm "$screenshots"

  # Delete processed text files
  rm "$textdata"
done
