#!/usr/bin/env bash
set -euo pipefail

# Set default files
DAILY_SUMMARY_FILE="${DAILY_SUMMARY_FILE:-$HOME/.time-tracker/daily-summaries.json}"
USER_CONTEXT_FILE="${USER_CONTEXT_FILE:-$HOME/.time-tracker/user-context.txt}"

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
  echo "  --calendar NAME Include events from specified calendar"
  echo "  --debug         Show debug information, including Ollama input"
  echo "  --help          Display this help message"
  echo ""
  echo "Examples:"
  echo "  query-summaries --start 2025-04-21 --end 2025-04-25"
  echo "  query-summaries --week 17 --year 2025"
  echo "  query-summaries --week 17 --calendar 'Work'"
}

# Parse arguments
START_DATE=""
END_DATE=""
WEEK_NUMBER=""
YEAR_NUMBER=$(date +"%Y")
DEBUG=0
CALENDAR_NAME=""

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
      YEAR_NUMBER="$2"
      shift 2
      ;;
    --calendar)
      CALENDAR_NAME="$2"
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
  FIRST_DAY=$(date -j -f "%Y-%m-%d" "$YEAR_NUMBER-01-01" +"%Y-%m-%d")
  
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
  
  echo "Week $WEEK_NUMBER of $YEAR_NUMBER: $START_DATE to $END_DATE (Monday to Friday)"
fi

# Validate that we have a date range
if [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
  echo "Error: You must specify either a date range (--start and --end) or a week number (--week)"
  show_usage
  exit 1
fi

# Read user context if available
USER_CONTEXT=""
if [ -f "$USER_CONTEXT_FILE" ]; then
  USER_CONTEXT=$(cat "$USER_CONTEXT_FILE")
fi

# Function to get calendar events for a specific date
get_calendar_events() {
  date="$1"
  calendar_name="$2"

  swift - << 'EOF' "$date" "$calendar_name"
import Foundation
import EventKit

let args = CommandLine.arguments
guard args.count == 3 else {
    print("Expected 2 arguments: targetDate and calendarName")
    exit(1)
}

let targetDateString = args[1]
let targetCalendarName = args[2]

let eventStore = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)

eventStore.requestFullAccessToEvents { granted, error in
    if !granted || error != nil {
        print("Access to Calendar denied")
        semaphore.signal()
        return
    }

    let inputFormatter = ISO8601DateFormatter()
    inputFormatter.formatOptions = [.withFullDate]
    let displayFormatter = DateFormatter()
    displayFormatter.dateFormat = "yyyy-MM-dd HH:mm"

    guard let startDate = inputFormatter.date(from: targetDateString) else {
        print("Invalid date format")
        semaphore.signal()
        return
    }
    let endDate = Calendar.current.date(
        byAdding: .day,
        value: 1,
        to: startDate
    )!

    let calendars = eventStore.calendars(for: .event)
    let targetCalendars = calendars.filter {
        $0.title == targetCalendarName
    }

    let predicate = eventStore.predicateForEvents(
        withStart: startDate,
        end: endDate,
        calendars: targetCalendars
    )
    let events = eventStore.events(matching: predicate)

    for event in events {
        let timeInterval = event.endDate.timeIntervalSince(event.startDate)
        let minutes = Int(timeInterval / 60)
        let title = event.title ?? "No Title"
        let start = displayFormatter.string(from: event.startDate)
        let end = displayFormatter.string(from: event.endDate)

        print("\(title) | \(start) → \(end) | \(minutes) min")
    }

    semaphore.signal()
}

_ = semaphore.wait(timeout: .distantFuture)
EOF
}

# Get all summaries in the date range
PERIOD_SUMMARIES=$(jq -c --arg start "$START_DATE" --arg end "$END_DATE" \
'to_entries[] | select(.key >= $start and .key <= $end)' \
"$DAILY_SUMMARY_FILE" \
| while read -r entry; do
  date=$(jq -r '.key' <<< "$entry")
  summary=$(jq -r '.value' <<< "$entry")
  echo "Date:"
  echo "$date"
  echo
  echo "Summary:"
  echo "$summary"
  echo

  if [ -n "$CALENDAR_NAME" ]; then
    events=$(get_calendar_events "$date" "$CALENDAR_NAME")
    echo "Calendar:"
    echo "$events"
    echo
  fi
done)

# Generate overall summary using ollama if we found any data
if [ -n "$PERIOD_SUMMARIES" ]; then
  # Create the prompt for Ollama
  PROMT=$(cat << EOF
Analyze the following daily summaries from $START_DATE to $END_DATE.

Provide a concise overview of the main activities and accomplishments during
this period. Also calculate approximately how many productive hours were spent
and on what main categories of work.

User context:

$USER_CONTEXT

Daily summaries:

$PERIOD_SUMMARIES
EOF
)
  
  # If debug mode is enabled, show the input data
  if [ "$DEBUG" -eq 1 ]; then
    echo "-------------"
    echo "DEBUG Prompt:"
    echo "-------------"
    echo "$PROMT"
    exit 0
  fi
  
  # Run the Ollama model
  PERIOD_SUMMARY=$(ollama run gemma3:27b-it-qat "$PROMT")
  echo "$PERIOD_SUMMARY"
else
  echo "No data available to generate a summary for this period."
fi
