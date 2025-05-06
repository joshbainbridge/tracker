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
user_context="No context provided."
if [ -f "$USER_CONTEXT_FILE" ]; then
  user_context="User context: $(cat "$USER_CONTEXT_FILE")"
fi

# Process data for yesterday
yesterday=$(date -v-1d +"%Y-%m-%d")
echo "Processing summaries for $yesterday"

# Check if yesterday is already in the daily summaries
if jq -e --arg date "$yesterday" '.[$date]' "$DAILY_SUMMARY_FILE" > /dev/null 2>&1; then
  echo "Daily summary for $yesterday already exists, skipping"
  exit 0
fi

# Process hourly summaries
for h in {0..23}; do
  # Ensure hour is zero-padded
  hour=$(printf "%02d" "$h")
  hour_key="$yesterday-$hour"

  # Check if hourly summary already exists
  if jq -e --arg key "$hour_key" '.[$key]' "$HOURLY_SUMMARY_FILE" > /dev/null 2>&1; then
    echo "Hourly summary for $hour_key already exists, skipping"
    continue
  fi

  # Find recent hours (up to 5)
  past=$(jq -r --arg current "$hour_key" \
  'to_entries | map(select(.key < $current)) | sort_by(.key) | .[-5:][] | "\(.key) - \(.value)"' \
  "$HOURLY_SUMMARY_FILE")

  # Filter activity data for this hour of yesterday
  hour_data=$(jq -r --arg start "$hour_key" \
  'to_entries | map(select(.key | startswith($start))) | .[] | "\(.key) - \(.value)"' \
  "$ACTIVITY_FILE")

  # Skip if no data for this hour
  if [ -z "$hour_data" ]; then
    echo "No data for $hour_key, skipping"
    continue
  fi

  prompt=$(cat << EOF
Summarize the following activities for the hour $yesterday $hour:00. What
was the person primarily working on during this hour? Be concise (max 500
characters).

User context:

$user_context

Past hours (newest first):

$past

Activity:

$hour_data
EOF
)

  # Generate summary using ollama
  hour_summary=$(ollama run gemma3:27b-it-qat "$prompt")

  # Add hourly summary to the hourly summaries file
  json=$(jq --arg key "$hour_key" --arg summary "$hour_summary" \
  '. + {($key): $summary}' \
  "$HOURLY_SUMMARY_FILE")

  # Output to JSON file
  echo "$json" > "$HOURLY_SUMMARY_FILE"

  echo "Generated hourly summary for $hour_key"
done

# Find recent days (up to 5)
past=$(jq -r --arg current "$yesterday" \
'to_entries | map(select(.key < $current)) | sort_by(.key) | .[-5:][] | "\(.key) - \(.value)"' \
"$DAILY_SUMMARY_FILE")

# Get all hourly summaries for yesterday
hour_data=$(jq -r --arg date "$yesterday" \
'to_entries | map(select(.key | startswith($date))) | .[] | "\(.key) - \(.value)"' \
"$HOURLY_SUMMARY_FILE")

# Skip if no hourly summaries exist
if [ -z "$hour_data" ]; then
  echo "No hourly summaries for $yesterday, skipping daily summary"
  exit 0
fi

prompt=$(cat << EOF
Summarize the following hourly activities for the day $yesterday. What was
the person primarily working on during this day? How many productive hours? Be
concise (max 1000 characters).

User context:

$user_context

Past days (newest first):

$past

Hourly summaries:

$hour_data
EOF
)

# Generate daily summary using ollama
day_summary=$(ollama run gemma3:27b-it-qat "$prompt")

# Add daily summary to the daily summaries file
json=$(jq --arg date "$yesterday" --arg summary "$day_summary" \
'. + {($date): $summary}' \
"$DAILY_SUMMARY_FILE")

# Output to JSON file
echo "$json" > "$DAILY_SUMMARY_FILE"

echo "Generated daily summary for $yesterday"
