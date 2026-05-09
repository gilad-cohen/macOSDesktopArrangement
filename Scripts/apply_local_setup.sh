#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-$ROOT/Config/local_setups.tsv}"
MACHINE_ID="${MACHINE_ID:-$("$ROOT/Scripts/machine_id.sh")}"
SETUP_NAME="${SETUP_NAME:-default}"
DRY_RUN=0
FAST_CHECK=1
MISSION_CONTROL_OPEN_DELAY="${MISSION_CONTROL_OPEN_DELAY:-0.10}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --setup)
      SETUP_NAME="${2:?missing setup name}"
      shift 2
      ;;
    --config)
      CONFIG="${2:?missing config path}"
      shift 2
      ;;
    --machine-id)
      MACHINE_ID="${2:?missing machine id}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-fast-check)
      FAST_CHECK=0
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ ! -f "$CONFIG" ]]; then
  echo "missing config: $CONFIG" >&2
  exit 66
fi

matched=0
declare -a MATCHED_GROUPS=()
declare -a MATCHED_ORDERS=()
echo "Machine: $MACHINE_ID"
echo "Setup: $SETUP_NAME"

while IFS=$'\t' read -r config_machine config_setup display_group ordered_names; do
  [[ -z "${config_machine:-}" || "$config_machine" == \#* ]] && continue
  [[ "$config_machine" == "$MACHINE_ID" ]] || continue
  [[ "$config_setup" == "$SETUP_NAME" ]] || continue
  matched=1
  MATCHED_GROUPS+=("$display_group")
  MATCHED_ORDERS+=("$ordered_names")

  IFS='|' read -r -a names <<< "$ordered_names"
  echo "Display group $display_group:"
  printf '  %s\n' "${names[@]}"
done < "$CONFIG"

if [[ "$matched" -eq 0 ]]; then
  cat >&2 <<EOF
No local setup matched this machine.

Config: $CONFIG
Machine: $MACHINE_ID
Setup: $SETUP_NAME

Add rows like:
$MACHINE_ID	$SETUP_NAME	1	App 1|App 2|Desktop 1
EOF
  exit 65
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

make -C "$ROOT" drag-mouse >/dev/null
open -a "Mission Control"
sleep "$MISSION_CONTROL_OPEN_DELAY"

cleanup() {
  osascript -e 'tell application "System Events" to key code 53' >/dev/null 2>&1 || true
}
trap cleanup EXIT

read_group_names() {
  local display_group="$1"
  local attempt output
  for ((attempt = 1; attempt <= ${BUTTON_READ_RETRIES:-8}; attempt++)); do
    if output="$(osascript - "$display_group" 2>/dev/null <<'OSA'
on run argv
  set displayGroup to item 1 of argv as integer
  tell application "System Events"
    tell process "Dock"
      set outputRows to {}
      set spaceButtons to buttons of list 1 of group "Spaces Bar" of group displayGroup of group "Mission Control"
      repeat with spaceButton in spaceButtons
        set end of outputRows to name of spaceButton
      end repeat
      set AppleScript's text item delimiters to "|"
      return outputRows as text
    end tell
  end tell
end run
OSA
    )"; then
      printf '%s\n' "$output"
      return 0
    fi

    open -a "Mission Control"
    sleep "${BUTTON_READ_RETRY_DELAY:-0.25}"
  done

  return 1
}

read_all_group_names() {
  local groups_arg="$1"
  local attempt output
  for ((attempt = 1; attempt <= ${BUTTON_READ_RETRIES:-8}; attempt++)); do
    if output="$(osascript - "$groups_arg" 2>/dev/null <<'OSA'
on run argv
  set groupText to item 1 of argv
  set oldDelimiters to AppleScript's text item delimiters
  set AppleScript's text item delimiters to ","
  set groupItems to text items of groupText
  set AppleScript's text item delimiters to oldDelimiters

  tell application "System Events"
    tell process "Dock"
      set outputRows to {}
      repeat with groupItem in groupItems
        set displayGroup to groupItem as integer
        set spaceNames to {}
        set spaceButtons to buttons of list 1 of group "Spaces Bar" of group displayGroup of group "Mission Control"
        repeat with spaceButton in spaceButtons
          set end of spaceNames to name of spaceButton
        end repeat
        set AppleScript's text item delimiters to "|"
        set end of outputRows to ((displayGroup as text) & tab & (spaceNames as text))
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

    open -a "Mission Control"
    sleep "${BUTTON_READ_RETRY_DELAY:-0.25}"
  done

  return 1
}

if [[ "$FAST_CHECK" -eq 1 ]]; then
  already_correct=1
  group_arg="$(IFS=,; printf '%s' "${MATCHED_GROUPS[*]}")"
  all_current="$(read_all_group_names "$group_arg")"
  for index in "${!MATCHED_GROUPS[@]}"; do
    current_order="$(awk -F '\t' -v group="${MATCHED_GROUPS[$index]}" '$1 == group { print $2; exit }' <<< "$all_current")"
    expected_order="${MATCHED_ORDERS[$index]}"
    if [[ "$current_order" != "$expected_order" ]]; then
      already_correct=0
      break
    fi
  done

  if [[ "$already_correct" -eq 1 ]]; then
    echo "Already correct; no reorder needed."
    exit 0
  fi
fi

for index in "${!MATCHED_GROUPS[@]}"; do
  IFS='|' read -r -a names <<< "${MATCHED_ORDERS[$index]}"
  REORDER_SPACES_SESSION=1 REORDER_SPACES_SKIP_BUILD=1 \
    "$ROOT/Scripts/reorder_spaces.sh" "${MATCHED_GROUPS[$index]}" "${names[@]}"
done
