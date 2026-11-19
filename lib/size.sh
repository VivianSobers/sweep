#!/usr/bin/env bash

sweep_size_kb() {
  local total unreadable path path_kb
  total=0
  unreadable=0

  for path in "$@"; do
    if [ -e "$path" ]; then
      if [ ! -r "$path" ] || [ ! -x "$path" ]; then
        unreadable=1
      else
        path_kb=$(du -sk "$path" 2>/dev/null | awk 'NR == 1 { print $1 + 0 }')
        path_kb=${path_kb:-0}
        total=$((total + path_kb))
      fi
    fi
  done

  printf '%s\n' "$total"
  if [ "$unreadable" -eq 1 ]; then
    return 3
  fi
  return 0
}

sweep_human() {
  awk -v kb="$1" 'BEGIN {
    if (kb < 1024) {
      printf "%.0fK\n", kb
    } else if (kb < 1048576) {
      printf "%.1fM\n", kb / 1024
    } else {
      printf "%.1fG\n", kb / 1048576
    }
  }'
}
