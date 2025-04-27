#!/usr/bin/env bash
set -euo pipefail

# Set default files
DAILY_SUMMARY_FILE="${DAILY_SUMMARY_FILE:-$HOME/.time-tracker/daily-summaries.json}"

# Display usage information
function show_usage {
  echo "Usage: query-summaries [OPTIONS]"
  echo "Query daily summaries for a date range or week number"
  echo ""
  echo "Options:"
  echo "  --start DATE    Start date (YYYY-MM-DD)"
  echo "  --end DATE      End date (YYYY-MM-DD)"
  echo "  --week WEEK     Week number (1-53)"
  echo "  --year YEAR     Year (YYYY), defaults to current year"
  echo "  --debug         Show debug information, including Ollama input"
  echo "  --help          Display this help message"
  echo ""
  echo "Examples:"
  echo "  query-summaries --start 2025-04-21 --end 2025-04-25"
  echo "  query-summaries --week 17 --year 2025"
}

# Parse arguments
START_DATE=""
END_DATE=""
WEEK_NUMBER=""
YEAR=$(date +"%Y")
DEBUG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)
      START_DATE="$2"
      shift 2
      ;;
    --end)
      END_DATE="$2"
      shift 2
      ;;
    --week)
      WEEK_NUMBER="$2"
      shift 2
      ;;
    --year)
      YEAR="$2"
      shift 2
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# Check if daily summary file exists
if [ ! -f "$DAILY_SUMMARY_FILE" ]; then
  echo "Error: Daily summaries file not found at $DAILY_SUMMARY_FILE"
  exit 1
fi

# Calculate dates from week number if provided
if [ -n "$WEEK_NUMBER" ]; then
  # Calculate the date of the first day of the year
  FIRST_DAY=$(date -j -f "%Y-%m-%d" "$YEAR-01-01" +"%Y-%m-%d")
  
  # Calculate the day of week of the first day (1-7, where 1 is Monday)
  FIRST_DAY_WEEKDAY=$(date -j -f "%Y-%m-%d" "$FIRST_DAY" +"%u")
  
  # Calculate days to add to get to the first Monday of the year
  if [ "$FIRST_DAY_WEEKDAY" -eq 1 ]; then
    DAYS_TO_ADD=0
  else
    DAYS_TO_ADD=$((8 - FIRST_DAY_WEEKDAY))
  fi
  
  # Calculate the first Monday of the year
  FIRST_MONDAY=$(date -j -v+"$DAYS_TO_ADD"d -f "%Y-%m-%d" "$FIRST_DAY" +"%Y-%m-%d")
  
  # Calculate days to add to get to the Monday of the requested week
  DAYS_TO_ADD=$(( (WEEK_NUMBER - 1) * 7 ))
  
  # Calculate the Monday of the requested week
  START_DATE=$(date -j -v+"$DAYS_TO_ADD"d -f "%Y-%m-%d" "$FIRST_MONDAY" +"%Y-%m-%d")
  
  # Calculate the Friday of the requested week (4 days after Monday)
  END_DATE=$(date -j -v+4d -f "%Y-%m-%d" "$START_DATE" +"%Y-%m-%d")
  
  echo "Week $WEEK_NUMBER of $YEAR: $START_DATE to $END_DATE (Monday to Friday)"
fi

# Validate that we have a date range
if [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
  echo "Error: You must specify either a date range (--start and --end) or a week number (--week)"
  show_usage
  exit 1
fi

# Function to check if a date is within range
is_date_in_range() {
  local check_date="$1"
  local start_date="$2"
  local end_date="$3"
  
  # Convert dates to seconds since epoch for comparison
  local check_seconds
  check_seconds=$(date -j -f "%Y-%m-%d" "$check_date" +"%s")
  local start_seconds
  start_seconds=$(date -j -f "%Y-%m-%d" "$start_date" +"%s")
  local end_seconds
  end_seconds=$(date -j -f "%Y-%m-%d" "$end_date" +"%s")
  
  # Check if date is within range (inclusive)
  if [ "$check_seconds" -ge "$start_seconds" ] && [ "$check_seconds" -le "$end_seconds" ]; then
    return 0
  else
    return 1
  fi
}

# Extract all dates from the summaries file
DATES=$(jq -r 'keys[]' "$DAILY_SUMMARY_FILE")

# Get all summaries in the date range
PERIOD_SUMMARIES="{}"
for date in $DATES; do
  if is_date_in_range "$date" "$START_DATE" "$END_DATE"; then
    summary=$(jq -r --arg date "$date" '.[$date]' "$DAILY_SUMMARY_FILE")
    PERIOD_SUMMARIES=$(echo "$PERIOD_SUMMARIES" | jq --arg date "$date" --arg summary "$summary" '. + {($date): $summary}')
  fi
done

# Generate overall summary
echo "Overall Summary for $START_DATE to $END_DATE"
echo "========================================================"

# Generate overall summary using ollama if we found any data
if [ "$(echo "$PERIOD_SUMMARIES" | jq 'length')" -gt 0 ]; then
  # Create the prompt for Ollama
  OLLAMA_PROMPT="Analyze the following daily summaries from $START_DATE to $END_DATE. Provide a concise overview of the main activities and accomplishments during this period. Also calculate approximately how many productive hours were spent and on what main categories of work. Daily summaries: $(echo "$PERIOD_SUMMARIES" | jq -c)"
  
  # If debug mode is enabled, show the input data
  if [ "$DEBUG" -eq 1 ]; then
    echo "DEBUG: Ollama Prompt:"
    echo "-------------------"
    echo "$OLLAMA_PROMPT"
    echo "-------------------"
    echo "DEBUG: Daily Summaries Input:"
    echo "-------------------"
    echo "$PERIOD_SUMMARIES" | jq
    echo "-------------------"
  fi
  
  # Run the Ollama model
  PERIOD_SUMMARY=$(ollama run gemma3:27b-it-qat "$OLLAMA_PROMPT")
  echo "$PERIOD_SUMMARY"
else
  echo "No data available to generate a summary for this period."
fi