#!/usr/bin/env bash
set -euo pipefail

GROUP_COUNT="${1:-3}"
MISSION_CONTROL_OPEN_DELAY="${MISSION_CONTROL_OPEN_DELAY:-0.10}"
BUTTON_READ_RETRIES="${BUTTON_READ_RETRIES:-8}"
BUTTON_READ_RETRY_DELAY="${BUTTON_READ_RETRY_DELAY:-0.25}"

open_mission_control() {
  open -a "Mission Control"
  sleep "$MISSION_CONTROL_OPEN_DELAY"
}

read_spaces() {
  osascript - "$GROUP_COUNT" <<'OSA'
on run argv
  set groupCount to item 1 of argv as integer
  tell application "System Events"
    tell process "Dock"
      set outputText to ""
      repeat with groupIndex from 1 to groupCount
        set outputText to outputText & "Display group " & groupIndex & ":" & linefeed
        set spaceButtons to buttons of list 1 of group "Spaces Bar" of group groupIndex of group "Mission Control"
        repeat with spaceButton in spaceButtons
          set outputText to outputText & "  " & (name of spaceButton) & linefeed
        end repeat
      end repeat
      return outputText
    end tell
  end tell
end run
OSA
}

open_mission_control

for ((attempt = 1; attempt <= BUTTON_READ_RETRIES; attempt++)); do
  if read_spaces; then
    osascript -e 'tell application "System Events" to key code 53' >/dev/null
    exit 0
  fi

  open_mission_control
  sleep "$BUTTON_READ_RETRY_DELAY"
done

osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
echo "Could not read Mission Control after $BUTTON_READ_RETRIES attempts." >&2
exit 1
