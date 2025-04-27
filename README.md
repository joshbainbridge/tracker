# Time Tracker

A Nix-based time tracking service that captures periodic screenshots and uses Ollama to summarize activities.

## Features

- Captures screenshots at configurable intervals.
- Uses Ollama with Gemma 3 to summarize activities from screenshots.
- Stores activity data in a JSON file.
- Automatically cleans up processed screenshots.
- Integrates with Home Manager as a service.

## Installation

Add the following to your `home.nix`:

```nix
{ config, pkgs, ... }:

{
  imports = [
    /path/to/tracker/nix/time-tracker.nix
  ];

  services.time-tracker = {
    enable = true;
    screenshotInterval = 300;  # Screenshot every 5 minutes
    processingInterval = 1800;  # Process every half hour
  };
}
```

Make sure to replace `/path/to/tracker` with the actual path to this repository.

## Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `enable` | Enable the time tracker service | `false` |
| `screenshotInterval` | Interval in seconds between screenshots | `300` |
| `processingInterval` | Interval in seconds between processing screenshots | `1800` |

## macOS Screen Recording Permissions

On macOS, you'll need to grant screen recording permissions to the Terminal or iTerm app that runs your Home Manager commands. To do this:

1. Go to System Preferences > Security & Privacy > Privacy > Screen Recording.
2. Add your terminal application to the list of allowed applications.
3. Log out and log back in for the changes to take effect.

You may also need to grant screen recording permissions to the `launchd` process.

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
