#!/usr/bin/env bash

# Copies the rw/ro mode from a source mountpoint and remounts target mountpoint
# with the same mode, if mode is rw with overlay, it will be considered as ro

# $1: source mountpoint to get fs mode from
# $2: target mountpoint to set fs mode to
# $3: (optional) if $3==rwonly and $SOURCE_MODE!=rw then skip remounting

if [ "$#" -lt 2 ]; then
  echo "Illegal number of parameters"
  exit 1
fi

# print rw/ro/rw*/ro* for a given mountpoint otherwise print nothing
function get_fs_mode() {
  # realpath will remove trailing slashes
  local MOUNTPOINT=$(realpath "${1}")
  local RE="^$(echo "$MOUNTPOINT" | sed 's/\//\\\//g')\$"
  # keep in mind that this command is intended to work with mawk, using gawk can
  # print some unintended errors
  awk -v re=$RE \
  '$2~re {mode=substr($4,1,2); if($1 == "overlay"){mode=mode"*"}; print mode}' \
  /proc/mounts
}

SOURCE_MODE=$(get_fs_mode "${1}")
if [ -z "$SOURCE_MODE" ]; then
  echo "${1} is not a valid mountpoint"
  exit 1
fi

NEXT_MODE=$SOURCE_MODE
if [ "$SOURCE_MODE" = "rw*" ] || [ "$SOURCE_MODE" = "ro*" ]; then
  NEXT_MODE=ro
fi

TARGET_MODE=$(get_fs_mode "${2}")
if [ "$NEXT_MODE" = "$TARGET_MODE" ]; then
  echo "Already ${NEXT_MODE}"
  exit 0
fi

if [ "${3}" = "rwonly" ] && [ "$SOURCE_MODE" != "rw" ]; then
  echo "Skipping..."
  exit 0
fi

mount -o "${NEXT_MODE},remount" "$2"
