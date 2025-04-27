# Time Tracker

A Nix-based time tracking service for macOS that monitors activity and uses local AI inference to generate summaries.

**Note:** This service is designed specifically for macOS using launchd agents.

## Features

- Monitors user activity at configurable intervals.
- Uses local inference with a multimodal LLM to generate activity summaries.
- Creates hourly and daily activity reports.
- Provides a query tool for aggregating and analyzing activities across multiple days or weeks.
- Stores organized data in JSON format.
- Integrates with Nix Home Manager as a service.

## Installation

This service requires Nix and Home Manager.

Add the following to your `home.nix`:

```nix
{
  imports = [
    /path/to/tracker/nix/time-tracker.nix
  ];

  services.time-tracker = {
    enable = true;
    screenshotInterval = 5;
    processingInterval = 30;
    workHoursOnly = true;
    weekdaysOnly = true;
    workStartHour = 9;
    workEndHour = 18;
  };
}
```

Make sure to replace `/path/to/tracker` with the actual path to this repository.

## Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `enable` | Enable the time tracker service | `false` |
| `screenshotInterval` | Interval in minutes between activity captures | `5` |
| `processingInterval` | Interval in minutes between processing activities | `30` |
| `workHoursOnly` | Whether to run only during configured work hours | `true` |
| `weekdaysOnly` | Whether to run only on weekdays (Monday-Friday) | `true` |
| `workStartHour` | Start hour of work day (24-hour format, 0-23) | `9` |
| `workEndHour` | End hour of work day (24-hour format, 0-23) | `18` |

## Output

The service generates three JSON files in the `$HOME/.time-tracker/` directory:

1. **Activity Snapshots** (`activity-snapshots.json`):
   ```json
   {
     "2025-04-26-17-20-06": "Working on a coding project in Visual Studio Code, editing JavaScript files",
     "2025-04-26-17-25-10": "Checking email in Gmail, reviewing work correspondence"
   }
   ```

2. **Hourly Summaries** (`hourly-summaries.json`):
   ```json
   {
     "2025-04-26-17": "Spent the hour working on JavaScript development in VS Code with occasional email checking"
   }
   ```

3. **Daily Summaries** (`daily-summaries.json`):
   ```json
   {
     "2025-04-26": "Primarily focused on JavaScript development (4 hours), communication via email/Slack (2 hours), and project planning (1 hour). Total productive time: approximately 7 hours."
   }
   ```

## Query Tool

The package includes a `query-summaries` tool for analyzing your time spent across multiple days:

```bash
# Query by date range
query-summaries --start 2025-04-21 --end 2025-04-25

# Query by week number
query-summaries --week 17 --year 2025

# Debug mode to see input data
query-summaries --week 17 --debug
```

This tool aggregates daily summaries and generates an overview of your activities across a specified date range or work week.
