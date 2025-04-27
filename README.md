# Time Tracker

A Nix-based time tracking service for macOS that captures periodic screenshots and uses Ollama to summarize activities.

**Note:** This service is designed specifically for macOS using launchd agents.

## Features

- Captures screenshots at configurable intervals.
- Uses Ollama with Gemma 3 to summarize activities from screenshots.
- Stores activity data in a JSON file.
- Automatically cleans up processed screenshots.
- Integrates with Home Manager as a service.

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
| `screenshotInterval` | Interval in minutes between screenshots | `5` |
| `processingInterval` | Interval in minutes between processing screenshots | `30` |
| `workHoursOnly` | Whether to run only during configured work hours | `true` |
| `weekdaysOnly` | Whether to run only on weekdays (Monday-Friday) | `true` |
| `workStartHour` | Start hour of work day (24-hour format, 0-23) | `9` |
| `workEndHour` | End hour of work day (24-hour format, 0-23) | `18` |

## Output

The service creates a JSON file at `$HOME/.time-tracker/activity-snapshots.json` with entries like:

```json
[
  {
    "timestamp": "2025-04-26-17-20-06",
    "activity": "Working on a coding project in Visual Studio Code, editing JavaScript files"
  }
]
```
