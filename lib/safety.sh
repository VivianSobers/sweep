#!/usr/bin/env bash

sweep_resolve() {
  [ "$#" -eq 1 ] || return 1
  local path link parent base physical_parent hops
  path=$1
  [ -e "$path" ] || [ -L "$path" ] || return 1

  case "$path" in
    /*) ;;
    *) path="$PWD/$path" ;;
  esac

  hops=0
  while [ -L "$path" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || return 1
    link=$(readlink "$path") || return 1
    parent=$(dirname "$path")
    case "$link" in
      /*) path=$link ;;
      *) path="$parent/$link" ;;
    esac
    [ -e "$path" ] || [ -L "$path" ] || return 1
  done

  if [ -d "$path" ]; then
    (cd -P -- "$path" 2>/dev/null && pwd -P)
    return $?
  fi

  parent=$(dirname "$path")
  base=$(basename "$path")
  physical_parent=$(cd -P -- "$parent" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$physical_parent" "$base"
}

sweep_is_safe_path() {
  [ "$#" -eq 1 ] || return 1
  local resolved home_resolved relative
  resolved=$(sweep_resolve "$1") || return 1
  home_resolved=$(sweep_resolve "$HOME") || return 1

  case "$resolved" in
    "$home_resolved"/*) relative=${resolved#"$home_resolved"/} ;;
    *) return 1 ;;
  esac

  case "$relative" in
    */*) ;;
    *) return 1 ;;
  esac

  case "$resolved" in
    "$home_resolved/Documents"|"$home_resolved/Documents/"*|\
    "$home_resolved/Desktop"|"$home_resolved/Desktop/"*|\
    "$home_resolved/Downloads"|"$home_resolved/Downloads/"*|\
    "$home_resolved/Pictures"|"$home_resolved/Pictures/"*|\
    "$home_resolved/Movies"|"$home_resolved/Movies/"*|\
    "$home_resolved/Music"|"$home_resolved/Music/"*)
      return 1
      ;;
  esac

  return 0
}

sweep_is_running() {
  [ "$#" -eq 1 ] || return 1
  pgrep -f -- "$1" >/dev/null 2>&1
}

sweep_require_user() {
  if [ "$(id -u)" = 0 ]; then
    printf '%s\n' 'sweep: refusing to run as root' >&2
    return 1
  fi
}
