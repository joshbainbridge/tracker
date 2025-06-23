#!/usr/bin/env bash
set -euo pipefail

DEBUG="${DEBUG:-false}"
ACTIVITY_DIR="${ACTIVITY_DIR:-/tmp/time-tracker}"
OUTPUT_FILE="${OUTPUT_FILE:-$HOME/.time-tracker/activity-snapshots.json}"
USER_CONTEXT_FILE="${USER_CONTEXT_FILE:-$HOME/.time-tracker/user-context.txt}"

query_model() {
  num_tokens=500

  system_prompt_raw=$(cat << EOF
YOU ARE NOT AN ASSISTANT. DO NOT TRY AND HELP. DO NOT ANSWER ANY QUESTIONS.
Analyze what the user is trying to do. What is the current action? Be detailed
in your response. You have a maximum of $num_tokens to respond with. Focus on
the screenshot(s) provided. Also note the name of the active window. This will
inform you where the user is working in the screenshots. Auxiliary information
may also be provided in the form of a user context and past activity, but these
are secondary. Relevance of past activity should be based on the time difference
between those activities and the current time being evaluated. Return text with
no new lines.
EOF
)

  system_prompt=$(echo "$system_prompt_raw" | tr '\n' ' ')
  user_prompt="$1"

  model="gemma3:27b-it-qat"

  json_payload=$(jq -n \
  --arg model "$model" \
  --arg system_content "$system_prompt" \
  --arg user_content "$user_prompt" \
  --argjson num_tokens "$num_tokens" \
  '{
    model: $model,
    messages: [
      {role: "system", content: $system_content},
      {role: "user", content: $user_content}
    ],
    options: {num_predict: $num_tokens, temperature: 0},
    stream: false
  }')

  if [ "$DEBUG" = true ]; then
    echo "$json_payload" >&2
    return 0
  fi

  raw_response=$(curl -s -X POST http://localhost:11434/api/chat -d "$json_payload")

  generated_text=$(echo "$raw_response" | jq -r '.message.content')

  echo "$generated_text"
}

# Create output directory and file if they don't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"
if [ ! -f "$OUTPUT_FILE" ]; then
  echo '{}' > "$OUTPUT_FILE"
fi

# Make sure activity directory exists
mkdir -p "$ACTIVITY_DIR"

# Read user context if available
user_context="No context provided."
if [ -f "$USER_CONTEXT_FILE" ]; then
  user_context=$(cat "$USER_CONTEXT_FILE")
fi

# Get all unique timestamps from activity snapshots
timestamps=$(find "$ACTIVITY_DIR" -type f | sed -En 's|.*/([0-9]+(-[0-9]+){5})\.txt$|\1|p' | sort -u)

# Process activity snapshots by timestamp
for timestamp in $timestamps; do
  # If in debug mode, print the timestamp being processed
  if [ "$DEBUG" = true ]; then
    echo "DEBUG MODE: processing timestamp $timestamp" >&2
  fi

  # Find past activity (up to 5 entries)
  past=$(jq -r --arg current "$timestamp" \
  'to_entries| map(select(.key < $current)) | sort_by(.key) | .[-5:][] | "\(.key) - \(.value)"' \
  "$OUTPUT_FILE")

  # Get screenshot filenames for the prompt
  screenshots=$(find "$ACTIVITY_DIR" -type f -name "$timestamp-*.png")
  text_data=$(find "$ACTIVITY_DIR" -type f -name "$timestamp.txt")

  # Get text data about active window
  window=$(cat "$text_data")

  prompt=$(cat << EOF
Time stamp:

$timestamp

Screenshots:

$screenshots

Active window:

$window

User context:

$user_context

Past activity:

$past
EOF
)

  # Get screenshot summary using ollama
  summary=$(query_model "$prompt")

  # If in debug mode, query_model will return early and summary will be empty
  if [ "$DEBUG" = true ]; then
    echo "DEBUG MODE: exiting after showing JSON payload" >&2
    echo "DEBUG MODE: remove $screenshots $text_data" >&2
    exit 0
  fi

  # Read existing JSON and add summary
  json=$(jq \
  --arg timestamp "$timestamp" \
  --arg summary "$summary" \
  '. + {($timestamp): $summary}' \
  "$OUTPUT_FILE")

  # Output to JSON file
  echo "$json" > "$OUTPUT_FILE"

  # Delete processed screenshots
  echo "$screenshots" | xargs rm

  # Delete processed text file
  echo "$text_data" | xargs rm
done
