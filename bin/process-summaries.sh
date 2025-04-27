#!/usr/bin/env bash
set -euo pipefail

# Set default files
ACTIVITY_FILE="${ACTIVITY_FILE:-$HOME/.time-tracker/activity-snapshots.json}"
HOURLY_SUMMARY_FILE="${HOURLY_SUMMARY_FILE:-$HOME/.time-tracker/hourly-summaries.json}"
DAILY_SUMMARY_FILE="${DAILY_SUMMARY_FILE:-$HOME/.time-tracker/daily-summaries.json}"

# Create output files if they don't exist
for file in "$HOURLY_SUMMARY_FILE" "$DAILY_SUMMARY_FILE"; do
  mkdir -p "$(dirname "$file")"
  if [ ! -f "$file" ]; then
    echo '{}' > "$file"
  fi
done

# Process data for yesterday
YESTERDAY=$(date -v-1d +"%Y-%m-%d")
echo "Processing summaries for $YESTERDAY"

# Check if yesterday is already in the daily summaries
if jq -e --arg date "$YESTERDAY" '.[$date]' "$DAILY_SUMMARY_FILE" > /dev/null 2>&1; then
  echo "Daily summary for $YESTERDAY already exists, skipping"
  exit 0
fi

# Process hourly summaries
for HOUR in {00..23}; do
  HOUR_KEY="$YESTERDAY-$HOUR"

  # Check if hourly summary already exists
  if jq -e --arg key "$HOUR_KEY" '.[$key]' "$HOURLY_SUMMARY_FILE" > /dev/null 2>&1; then
    echo "Hourly summary for $HOUR_KEY already exists, skipping"
    continue
  fi

  # Filter activity data for this hour of yesterday
  HOUR_START="$YESTERDAY-$HOUR"
  HOUR_DATA=$(jq --arg start "$HOUR_START" 'with_entries(select(.key | startswith($start))) | to_entries | map({timestamp: .key, activity: .value})' "$ACTIVITY_FILE")

  # Skip if no data for this hour
  if [ "$(echo "$HOUR_DATA" | jq 'length')" -eq 0 ]; then
    echo "No data for $HOUR_KEY, skipping"
    continue
  fi

  # Generate summary using ollama
  HOUR_SUMMARY=$(ollama run gemma3:27b-it-qat "Summarize the following activities for the hour $YESTERDAY $HOUR:00. What was the person primarily working on during this hour? Be concise (max 500 characters). Activities: $(echo "$HOUR_DATA" | jq -c)")

  # Add hourly summary to the hourly summaries file
  temp_file=$(mktemp)
  jq --arg key "$HOUR_KEY" --arg summary "$HOUR_SUMMARY" '. + {($key): $summary}' "$HOURLY_SUMMARY_FILE" > "$temp_file"
  mv "$temp_file" "$HOURLY_SUMMARY_FILE"

  echo "Generated hourly summary for $HOUR_KEY"
done

# Get all hourly summaries for yesterday
HOURS_DATA=$(jq --arg date "$YESTERDAY" 'with_entries(select(.key | startswith($date)))' "$HOURLY_SUMMARY_FILE")

# Skip if no hourly summaries exist
if [ "$(echo "$HOURS_DATA" | jq 'length')" -eq 0 ]; then
  echo "No hourly summaries for $YESTERDAY, skipping daily summary"
  exit 0
fi

# Generate daily summary using ollama
DAY_SUMMARY=$(ollama run gemma3:27b-it-qat "Summarize the following hourly activities for the day $YESTERDAY. What was the person primarily working on during this day? How many productive hours? Be concise (max 1000 characters). Hourly summaries: $(echo "$HOURS_DATA" | jq -c)")

# Add daily summary to the daily summaries file
temp_file=$(mktemp)
jq --arg date "$YESTERDAY" --arg summary "$DAY_SUMMARY" '. + {($date): $summary}' "$DAILY_SUMMARY_FILE" > "$temp_file"
mv "$temp_file" "$DAILY_SUMMARY_FILE"

echo "Generated daily summary for $YESTERDAY"
