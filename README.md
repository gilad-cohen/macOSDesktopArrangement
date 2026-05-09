# MacOS Desktop Arrangement

Small native macOS proof-of-concept for restoring full-screen Space order across multiple displays.

This repo currently uses private macOS Spaces APIs for inspection and Accessibility/Mission Control UI automation for reordering. It is intended for personal/local use, not App Store distribution.

## What Works

- Reads current display/Space/app ordering through the private SkyLight framework.
- Lists Mission Control Space button names per display group.
- Reorders full-screen Spaces within a display group by dragging Mission Control thumbnails.
- Stores local machine-specific profiles.
- Selects the active profile by the Mac's stable `IOPlatformUUID`, so one shared config can contain setups for multiple computers.

## Current Limitation

This is not a polished app yet. It is a command-line PoC that proves the hard part: full-screen Space reordering can be automated on this machine.

Reliability depends on:

- Accessibility permission.
- Mission Control exposing the expected accessibility tree.
- Space button names matching the config exactly.
- Avoiding too-fast drags, which can accidentally create Split View instead of reordering.

## Requirements

- macOS with Command Line Tools installed.
- Accessibility permission for the process running the scripts.
- Recommended Mission Control settings:
  - Disable **Automatically rearrange Spaces based on most recent use**.
  - Enable **Displays have separate Spaces**.

## Repo Structure

```text
.
├── Config/
│   └── local_setups.tsv
├── Scripts/
│   ├── apply_current_profile.sh
│   ├── apply_local_setup.sh
│   ├── list_spaces.sh
│   ├── machine_id.sh
│   └── reorder_spaces.sh
├── Sources/
│   ├── drag_mouse.m
│   └── spaces_probe.m
├── Makefile
└── README.md
```

## File Responsibilities

### `Sources/spaces_probe.m`

Native Objective-C probe.

Responsibilities:

- Loads `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`.
- Calls private CGS/SkyLight symbols.
- Prints managed displays, Spaces, Space IDs, and app/window labels.
- Verifies whether Mission Control order actually changed after a drag.

Build/run:

```sh
make spaces-probe
./spaces-probe
```

### `Sources/drag_mouse.m`

Tiny native Objective-C mouse drag helper.

Responsibilities:

- Posts CoreGraphics mouse events.
- Performs fast, tunable drag gestures.
- Used by `Scripts/reorder_spaces.sh`.

Build/run:

```sh
make drag-mouse
./drag-mouse fromX fromY toX toY [durationMs]
```

Example:

```sh
./drag-mouse 860 73 714 73 320
```

### `Scripts/reorder_spaces.sh`

Reorders one Mission Control display group.

Responsibilities:

- Opens Mission Control.
- Reads Space thumbnail button names and positions from the Dock accessibility tree.
- Moves each requested Space into the requested slot.
- Uses insertion-edge drops to reduce accidental Split View creation.
- Prints final Mission Control order.

Usage:

```sh
Scripts/reorder_spaces.sh displayGroup "Space Name" ["Space Name"...]
```

Example:

```sh
Scripts/reorder_spaces.sh 1 \
  "Browser" \
  "Chat" \
  "Mail" \
  "Desktop 1" \
  "Editor" \
  "Terminal"
```

Useful timing overrides:

```sh
DRAG_DURATION_MS=400 Scripts/reorder_spaces.sh 1 "App A" "App B"
MISSION_CONTROL_OPEN_DELAY=1 Scripts/reorder_spaces.sh 1 "App A" "App B"
```

### `Scripts/list_spaces.sh`

Lists Mission Control Space button names.

Responsibilities:

- Opens Mission Control.
- Prints the button names for each display group.
- Helps you copy exact names into config.

Usage:

```sh
Scripts/list_spaces.sh 3
```

### `Scripts/machine_id.sh`

Prints the current Mac's stable machine ID.

Usage:

```sh
Scripts/machine_id.sh
```

This reads `IOPlatformUUID` via `ioreg`.

### `Scripts/apply_local_setup.sh`

Applies the profile matching the current Mac.

Responsibilities:

- Reads `Config/local_setups.tsv`.
- Detects the current machine ID.
- Selects rows matching `machine_id + setup_name`.
- Applies each display group with `reorder_spaces.sh`.

Usage:

```sh
Scripts/apply_local_setup.sh
```

Dry run:

```sh
Scripts/apply_local_setup.sh --dry-run
```

Choose a named setup:

```sh
Scripts/apply_local_setup.sh --setup work
Scripts/apply_local_setup.sh --setup home
```

### `Scripts/apply_current_profile.sh`

Compatibility wrapper.

Currently delegates to:

```sh
Scripts/apply_local_setup.sh
```

### `Config/local_setups.tsv`

Local profile store.

This file is intentionally ignored by git because it can reveal machine IDs and personal app layout. Use `Config/local_setups.example.tsv` as the public template.

Format:

```text
computer_id<TAB>setup_name<TAB>display_group<TAB>ordered_space_button_names_pipe_separated
```

Example:

```text
EXAMPLE-MACHINE-UUID	default	1	Browser|Chat|Mail|Desktop 1|Editor|Terminal
EXAMPLE-MACHINE-UUID	default	2	Desktop 2|Calendar|Notes
EXAMPLE-MACHINE-UUID	default	3	Desktop 3|Music
```

## How To Run

1. Grant Accessibility permission to the app/terminal running the scripts.

2. Confirm Accessibility is enabled:

   ```sh
   osascript -e 'tell application "System Events" to get UI elements enabled'
   ```

   Expected:

   ```text
   true
   ```

3. Build native helpers:

   ```sh
   make all
   ```

4. List current Space names:

   ```sh
   Scripts/list_spaces.sh 3
   ```

5. Dry-run the local setup:

   ```sh
   Scripts/apply_local_setup.sh --dry-run
   ```

6. Apply the local setup:

   ```sh
   Scripts/apply_local_setup.sh
   ```

7. Verify with the private probe:

   ```sh
   ./spaces-probe
   ```

## Add A New Computer

On the new Mac:

```sh
Scripts/machine_id.sh
Scripts/list_spaces.sh 3
```

Then add rows to `Config/local_setups.tsv`:

```text
NEW-MACHINE-UUID	default	1	App A|App B|Desktop 1
NEW-MACHINE-UUID	default	2	Desktop 2|App C
NEW-MACHINE-UUID	default	3	Desktop 3|App D
```

Now this command will automatically use only that Mac's rows:

```sh
Scripts/apply_local_setup.sh
```

## Add Work/Home Profiles

Use the same `computer_id` with different `setup_name` values:

```text
YOUR-MACHINE-UUID	work	1	Browser|Mail|Chat|Desktop 1|Editor
YOUR-MACHINE-UUID	home	1	Browser|Messages|Desktop 1|Editor
```

Run:

```sh
Scripts/apply_local_setup.sh --setup work
Scripts/apply_local_setup.sh --setup home
```

## Add Or Change Display Groups

Display groups are Mission Control's current display group numbers, not permanent physical display IDs.

To inspect them:

```sh
Scripts/list_spaces.sh 3
```

Copy the exact Space names into `Config/local_setups.tsv`.

## Timing Tuning

The profile apply path opens Mission Control once for all display groups and does a compact single-read fast check before any drag work.

With Mission Control animation disabled:

```sh
defaults write com.apple.dock expose-animation-duration -float 0
killall Dock
```

The current three-display no-op apply was measured at about `1.17s-1.59s`.

If drags are too slow:

```sh
DRAG_DURATION_MS=280 Scripts/apply_local_setup.sh
```

If drags accidentally create Split View, slow them down:

```sh
DRAG_DURATION_MS=450 Scripts/apply_local_setup.sh
```

If Mission Control is not ready quickly enough:

```sh
MISSION_CONTROL_OPEN_DELAY=1 Scripts/apply_local_setup.sh
```

Fast-but-still-conservative defaults:

```sh
MISSION_CONTROL_OPEN_DELAY=0.10
DRAG_DURATION_MS=320
AFTER_DRAG_DELAY=0.35
```

Avoid pushing `DRAG_DURATION_MS` too low. A previous `70ms` center-drop test caused macOS to create Split View instead of reordering. The current script drops near insertion edges and keeps drag duration conservative to avoid that class of bug.

## Performance Expectations

For apps that are already open and already full-screen:

- No-op apply across the current three display groups: about `2.45s`.
- No-op apply with Mission Control animation disabled: about `1.17s-1.59s`.
- Each actual Space move adds Mission Control animation/drag/readback time.
- The script only rereads a display group after an actual drag, so already-correct groups are cheap.

For apps that must be launched, moved to displays, and switched to full screen:

- A strict `5s` end-to-end target is probably unrealistic for many apps because app launch and macOS full-screen animations dominate runtime.
- The practical target is: parallelize app launches first, then perform display/full-screen placement, then do one batched Mission Control reorder pass.
- The current repo implements the final reorder pass. Launch/full-screen orchestration is the next layer.

## Troubleshooting

### `System Events got an error: Can't get group "Mission Control"`

Mission Control was not ready yet.

Try:

```sh
MISSION_CONTROL_OPEN_DELAY=1 Scripts/apply_local_setup.sh
```

### A Space became `App A & App B`

The drag was interpreted as Split View.

Fix:

1. Open the combined Space.
2. Exit full screen for one app.
3. Re-enter full screen.
4. Re-run with a slower drag:

   ```sh
   DRAG_DURATION_MS=450 Scripts/apply_local_setup.sh
   ```

### A Space name is missing

Run:

```sh
Scripts/list_spaces.sh 3
```

Then update `Config/local_setups.tsv` with the exact current name.

## Direction Toward A Real App

The next native app version should:

- Use Swift/AppKit as a menu-bar app.
- Use the same machine/profile config model.
- Detect connected physical displays through CoreGraphics.
- Map work/home profiles by display fingerprints.
- Keep this Mission Control reorder engine as the low-level implementation.
- Add a capture command that saves current order into config.

## Risk

This approach is intentionally private and local.

Main risks:

- SkyLight/CGS private symbols can change in future macOS versions.
- Mission Control accessibility structure can change.
- Drag behavior is timing-sensitive.
- Mac App Store distribution is not realistic for this approach.

For personal use, the approach is viable because it is inspectable, tunable, and easy to repair if macOS behavior changes.
