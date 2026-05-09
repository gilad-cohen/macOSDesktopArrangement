#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRAG="$ROOT/drag-mouse"
DISPLAY_GROUP="${1:-}"

if [[ -z "$DISPLAY_GROUP" || "$#" -lt 2 ]]; then
  cat >&2 <<'USAGE'
usage: Scripts/reorder_spaces.sh displayGroup "Space Name" ["Space Name"...]

Example:
  Scripts/reorder_spaces.sh 1 "Browser" "Chat" "Mail" "Desktop 1" "Editor" "Terminal"

Notes:
  - displayGroup is the Mission Control display group: 1, 2, 3...
  - names must match the Mission Control Spaces Bar button names exactly.
USAGE
  exit 64
fi

shift
DESIRED=("$@")
DRAG_DURATION_MS="${DRAG_DURATION_MS:-320}"
MISSION_CONTROL_OPEN_DELAY="${MISSION_CONTROL_OPEN_DELAY:-0.10}"
AFTER_DRAG_DELAY="${AFTER_DRAG_DELAY:-0.35}"
BUTTON_READ_RETRIES="${BUTTON_READ_RETRIES:-8}"
BUTTON_READ_RETRY_DELAY="${BUTTON_READ_RETRY_DELAY:-0.25}"
REORDER_SPACES_SESSION="${REORDER_SPACES_SESSION:-0}"
REORDER_SPACES_SKIP_BUILD="${REORDER_SPACES_SKIP_BUILD:-0}"

if [[ "$REORDER_SPACES_SKIP_BUILD" -eq 0 ]]; then
  make -C "$ROOT" drag-mouse >/dev/null
fi

open_mission_control() {
  open -a "Mission Control"
  sleep "$MISSION_CONTROL_OPEN_DELAY"
}

close_mission_control() {
  osascript -e 'tell application "System Events" to key code 53' >/dev/null
}

buttons() {
  local attempt
  for ((attempt = 1; attempt <= BUTTON_READ_RETRIES; attempt++)); do
    local output
    if output="$(osascript - "$DISPLAY_GROUP" 2>/dev/null <<'OSA'
on run argv
  set displayGroup to item 1 of argv as integer
  tell application "System Events"
    tell process "Dock"
      set outputRows to {}
      set spaceButtons to buttons of list 1 of group "Spaces Bar" of group displayGroup of group "Mission Control"
      repeat with spaceButton in spaceButtons
        set buttonPosition to position of spaceButton
        set buttonSize to size of spaceButton
        set leftX to item 1 of buttonPosition
        set widthValue to item 1 of buttonSize
        set centerX to leftX + (widthValue / 2)
        set centerY to (item 2 of buttonPosition) + ((item 2 of buttonSize) / 2)
        set rightX to leftX + widthValue
        set end of outputRows to ((name of spaceButton) & tab & ((centerX as integer) as text) & tab & ((centerY as integer) as text) & tab & ((leftX as integer) as text) & tab & ((rightX as integer) as text))
      end repeat
      set AppleScript's text item delimiters to linefeed
      return outputRows as text
    end tell
  end tell
end run
OSA
    )"; then
      printf '%s\n' "$output"
      return 0
    fi

    open_mission_control
    sleep "$BUTTON_READ_RETRY_DELAY"
  done

  echo "Could not read Mission Control display group $DISPLAY_GROUP after $BUTTON_READ_RETRIES attempts." >&2
  return 1
}

name_at_index() {
  local index="$1"
  sed -n "$((index + 1))p" "$STATE" | cut -f1
}

line_for_name() {
  local name="$1"
  awk -F '\t' -v target="$name" '$1 == target { print NR "\t" $0; exit }' "$STATE"
}

read_field() {
  local field="$1"
  cut -f"$field"
}

STATE="$(mktemp -t reorder-spaces.XXXXXX)"

cleanup() {
  rm -f "$STATE"
  if [[ "$REORDER_SPACES_SESSION" -eq 0 ]]; then
    close_mission_control
  fi
}

if [[ "$REORDER_SPACES_SESSION" -eq 0 ]]; then
  open_mission_control
fi
trap cleanup EXIT

printf 'Target order for display group %s:\n' "$DISPLAY_GROUP"
printf '  %s\n' "${DESIRED[@]}"

buttons > "$STATE"

for target_index in "${!DESIRED[@]}"; do
  target_name="${DESIRED[$target_index]}"
  current_name="$(name_at_index "$target_index")"

  if [[ "$current_name" == "$target_name" ]]; then
    continue
  fi

  source_line="$(line_for_name "$target_name")"
  if [[ -z "$source_line" ]]; then
    echo "Missing Space button: $target_name" >&2
    echo "Current buttons:" >&2
    cut -f1 "$STATE" >&2
    exit 65
  fi

  target_line="$(sed -n "$((target_index + 1))p" "$STATE")"
  source_index="$(printf '%s\n' "$source_line" | read_field 1)"
  from_x="$(printf '%s\n' "$source_line" | read_field 3)"
  from_y="$(printf '%s\n' "$source_line" | read_field 4)"
  to_y="$(printf '%s\n' "$target_line" | read_field 3)"

  if (( source_index > target_index + 1 )); then
    target_left="$(printf '%s\n' "$target_line" | read_field 4)"
    to_x="$((target_left + 6))"
  else
    target_right="$(printf '%s\n' "$target_line" | read_field 5)"
    to_x="$((target_right - 6))"
  fi

  printf 'Move "%s" from slot %s to slot %s\n' "$target_name" "$source_index" "$((target_index + 1))"
  "$DRAG" "$from_x" "$from_y" "$to_x" "$to_y" "$DRAG_DURATION_MS"
  sleep "$AFTER_DRAG_DELAY"
  buttons > "$STATE"
done

echo "Final Mission Control order:"
cut -f1 "$STATE" | sed 's/^/  /'
