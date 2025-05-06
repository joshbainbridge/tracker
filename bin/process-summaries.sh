#!/usr/bin/env bash
set -euo pipefail

# Set default files
ACTIVITY_FILE="${ACTIVITY_FILE:-$HOME/.time-tracker/activity-snapshots.json}"
HOURLY_SUMMARY_FILE="${HOURLY_SUMMARY_FILE:-$HOME/.time-tracker/hourly-summaries.json}"
DAILY_SUMMARY_FILE="${DAILY_SUMMARY_FILE:-$HOME/.time-tracker/daily-summaries.json}"
USER_CONTEXT_FILE="${USER_CONTEXT_FILE:-$HOME/.time-tracker/user-context.txt}"

# Create output files if they don't exist
for file in "$HOURLY_SUMMARY_FILE" "$DAILY_SUMMARY_FILE"; do
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    echo '{}' > "$file"
  fi
done

# Read user context if available
USER_CONTEXT=""
if [ -f "$USER_CONTEXT_FILE" ]; then
  USER_CONTEXT="User context: $(cat "$USER_CONTEXT_FILE")"
fi

# Process data for yesterday
YESTERDAY=$(date -v-1d +"%Y-%m-%d")
echo "Processing summaries for $YESTERDAY"

# Check if yesterday is already in the daily summaries
if jq -e --arg date "$YESTERDAY" '.[$date]' "$DAILY_SUMMARY_FILE" > /dev/null 2>&1; then
  echo "Daily summary for $YESTERDAY already exists, skipping"
  exit 0
fi

# Process hourly summaries
for h in {0..23}; do
  # Ensure hour is zero-padded
  HOUR=$(printf "%02d" "$h")
  HOUR_KEY="$YESTERDAY-$HOUR"

  # Check if hourly summary already exists
  if jq -e --arg key "$HOUR_KEY" '.[$key]' "$HOURLY_SUMMARY_FILE" > /dev/null 2>&1; then
    echo "Hourly summary for $HOUR_KEY already exists, skipping"
    continue
  fi

  # Find recent hours (up to 5)
  PAST=$(jq -r --arg current "$HOUR_KEY" \
  'to_entries | map(select(.key < $current)) | sort_by(.key) | .[-5:][] | "\(.key) - \(.value)"' \
  "$HOURLY_SUMMARY_FILE")

  # Filter activity data for this hour of yesterday
  HOUR_DATA=$(jq -r --arg start "$HOUR_KEY" \
  'to_entries | map(select(.key | startswith($start))) | .[] | "\(.key) - \(.value)"' \
  "$ACTIVITY_FILE")

  # Skip if no data for this hour
  if [ -z "$HOUR_DATA" ]; then
    echo "No data for $HOUR_KEY, skipping"
    continue
  fi

  PROMT=$(cat << EOF
Summarize the following activities for the hour $YESTERDAY $HOUR:00. What
was the person primarily working on during this hour? Be concise (max 500
characters).

User context:

$USER_CONTEXT

Past hours (newest first):

$PAST

Activity:

$HOUR_DATA
EOF
)

  # Generate summary using ollama
  HOUR_SUMMARY=$(ollama run gemma3:27b-it-qat "$PROMT")

  # Add hourly summary to the hourly summaries file
  json=$(jq --arg key "$HOUR_KEY" --arg summary "$HOUR_SUMMARY" \
  '. + {($key): $summary}' \
  "$HOURLY_SUMMARY_FILE")

  # Output to JSON file
  echo "$json" > "$HOURLY_SUMMARY_FILE"

  echo "Generated hourly summary for $HOUR_KEY"
done

# Find recent days (up to 5)
PAST=$(jq -r --arg current "$YESTERDAY" \
'to_entries | map(select(.key < $current)) | sort_by(.key) | .[-5:][] | "\(.key) - \(.value)"' \
"$DAILY_SUMMARY_FILE")

# Get all hourly summaries for yesterday
HOURS_DATA=$(jq -r --arg date "$YESTERDAY" \
'to_entries | map(select(.key | startswith($date))) | .[] | "\(.key) - \(.value)"' \
"$HOURLY_SUMMARY_FILE")

# Skip if no hourly summaries exist
if [ -z "$HOURS_DATA" ]; then
  echo "No hourly summaries for $YESTERDAY, skipping daily summary"
  exit 0
fi

PROMT=$(cat << EOF
Summarize the following hourly activities for the day $YESTERDAY. What was
the person primarily working on during this day? How many productive hours? Be
concise (max 1000 characters).

User context:

$USER_CONTEXT

Past days (newest first):

$PAST

Hourly summaries:

$HOURS_DATA
EOF
)

# Generate daily summary using ollama
DAY_SUMMARY=$(ollama run gemma3:27b-it-qat "$PROMT")

# Add daily summary to the daily summaries file
json=$(jq --arg date "$YESTERDAY" --arg summary "$DAY_SUMMARY" \
'. + {($date): $summary}' \
"$DAILY_SUMMARY_FILE")

# Output to JSON file
echo "$json" > "$DAILY_SUMMARY_FILE"

echo "Generated daily summary for $YESTERDAY"
