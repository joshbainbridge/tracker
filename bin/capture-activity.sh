#!/usr/bin/env bash
set -euo pipefail

# Script to capture activity data including screenshots and active window info
ACTIVITY_DIR="${ACTIVITY_DIR:-/tmp/time-tracker}"
mkdir -p "$ACTIVITY_DIR"

# Take screenshot with screencapture
FILENAME="$ACTIVITY_DIR/$(date +"%Y-%m-%d-%H-%M-%S")"
screencapture -x -C "$FILENAME-1.png" "$FILENAME-2.png" "$FILENAME-3.png" "$FILENAME-4.png"

get_active_window() {
swift - << 'EOF'
import Cocoa
import ApplicationServices

// Get frontmost application
guard let app = NSWorkspace.shared.frontmostApplication,
      let pid = app.processIdentifier as pid_t? else {
    print("ERROR: Could not get frontmost application")
    exit(1)
}

let appRef = AXUIElementCreateApplication(pid)

// Get window information
var window: AnyObject?
let windowStatus = AXUIElementCopyAttributeValue(
    appRef,
    kAXFocusedWindowAttribute as CFString,
    &window
)

if windowStatus != .success || window == nil {
    print("ERROR: Could not get focused window")
    exit(1)
}

// Get window title
var title: AnyObject?
let titleStatus = AXUIElementCopyAttributeValue(
    window as! AXUIElement,
    kAXTitleAttribute as CFString,
    &title
)

if titleStatus != .success {
    print("ERROR: Could not get window title")
    exit(1)
}

// Prepare output information
let appName = app.localizedName ?? "Unknown"
let windowTitle = title as? String ?? "Unknown"

// Output information
print("App: \(appName)")
print("Window Title: \(windowTitle)")
EOF
}

get_active_window > "$FILENAME.txt"
