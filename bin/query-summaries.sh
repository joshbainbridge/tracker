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
start_date=""
end_date=""
week_number=""
year_number=$(date +"%Y")
debug=0
calendar_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)
      start_date="$2"
      shift 2
      ;;
    --end)
      end_date="$2"
      shift 2
      ;;
    --week)
      week_number="$2"
      shift 2
      ;;
    --year)
      year_number="$2"
      shift 2
      ;;
    --calendar)
      calendar_name="$2"
      shift 2
      ;;
    --debug)
      debug=1
      shift
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1"
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
if [ -n "$week_number" ]; then
  # Get first day of the year
  first_day="$year_number-01-01"
  
  # Get day of week (1-7, where 1 is Monday)
  first_day_weekday=$(date -j -f "%Y-%m-%d" "$first_day" +"%u")
  
  # Find the Monday of week 1 (the Monday on or before January 1st)
  days_to_subtract=$((first_day_weekday - 1))
  first_monday=$(date -j -v-"${days_to_subtract}"d -f "%Y-%m-%d" "$first_day" +"%Y-%m-%d")
  
  # Find the Monday of the requested week
  days_to_add=$(( (week_number - 1) * 7 ))
  start_date=$(date -j -v+"$days_to_add"d -f "%Y-%m-%d" "$first_monday" +"%Y-%m-%d")
  
  # Find the Friday of the same week
  end_date=$(date -j -v+4d -f "%Y-%m-%d" "$start_date" +"%Y-%m-%d")
  
  echo "Week $week_number of $year_number: $start_date to $end_date (Monday to Friday)"
fi

# Validate that we have a date range
if [ -z "$start_date" ] || [ -z "$end_date" ]; then
  echo "Error: You must specify either a date range (--start and --end) or a week number (--week)"
  show_usage
  exit 1
fi

# Read user context if available
user_context="No context provided."
if [ -f "$USER_CONTEXT_FILE" ]; then
  user_context=$(cat "$USER_CONTEXT_FILE")
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
period_summaries=$(jq -c --arg start "$start_date" --arg end "$end_date" \
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

  if [ -n "$calendar_name" ]; then
    events=$(get_calendar_events "$date" "$calendar_name")
    echo "Calendar:"
    echo "$events"
    echo
  fi
done)

# Generate overall summary using ollama if we found any data
if [ -n "$period_summaries" ]; then
  # Create the prompt for Ollama
  prompt=$(cat << EOF
Analyze the following daily summaries from $start_date to $end_date.

Provide a concise overview of the main activities and accomplishments during
this period. Also calculate approximately how many productive hours were spent
and on what main categories of work.

User context:

$user_context

Daily summaries:

$period_summaries
EOF
)
  
  # If debug mode is enabled, show the input data
  if [ "$debug" -eq 1 ]; then
    echo "-------------"
    echo "DEBUG Prompt:"
    echo "-------------"
    echo "$prompt"
    exit 0
  fi
  
  # Run the Ollama model
  period_summary=$(ollama run gemma3:27b-it-qat "$prompt")
  echo "$period_summary"
else
  echo "No data available to generate a summary for this period."
fi
