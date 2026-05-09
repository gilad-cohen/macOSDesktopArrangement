#!/usr/bin/env bash
set -euo pipefail

ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/ { print $4; exit }'
