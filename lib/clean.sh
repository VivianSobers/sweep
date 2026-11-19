#!/usr/bin/env bash

# Paths a category removes, one per line.
sweep_clean_paths() {
  case "$1" in
    library) sweep_library_other_paths ;;
    docker) ;;
    *) sweep_category_field "$1" paths ;;
  esac
}

# KiB a category currently holds; returns 3 if part of it is unreadable.
sweep_clean_measure() {
  if [ "$1" = docker ]; then
    sweep_category_size_kb docker
    return
  fi
  sweep_size_kb_lines "$(sweep_clean_paths "$1")"
}

sweep_clean_tool_present() {
  [ -n "$1" ] && command -v "${1%% *}" >/dev/null 2>&1
}

# Runs a registry tool command. Its stdin is /dev/null so it can never
# consume input meant for sweep.
sweep_clean_run_tool() {
  local IFS=' '
  local -a tool_args
  read -r -a tool_args <<< "$1"
  "${tool_args[@]}" < /dev/null
}

# Asks before cleaning. The answer is read from fd 3, the user's stdin, which
# sweep_clean's caller sets up. EOF or anything but y/yes means no.
sweep_confirm() {
  local answer=
  printf 'Clean %s (%s)? [y/N] ' "$1" "$(sweep_human "$2")"
  IFS= read -r answer <&3 || answer=
  [ -t 3 ] || printf '\n'
  case "$answer" in
    y|Y|yes|Yes|YES) return 0 ;;
  esac
  return 1
}

sweep_clean_remove_paths() {
  local label=$1 path display failed=0
  while IFS= read -r path; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    display=$(sweep_display_path "$path")
    if ! sweep_is_safe_path "$path"; then
      printf 'refuse %s (unsafe)\n' "$display"
      continue
    fi
    if ! rm -rf -- "$path"; then
      printf 'fail  %s: could not remove %s\n' "$label" "$display"
      failed=1
    fi
  done <<EOF
$2
EOF
  return "$failed"
}

sweep_clean_dry_run_paths() {
  local path display path_kb
  while IFS= read -r path; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    display=$(sweep_display_path "$path")
    if ! sweep_is_safe_path "$path"; then
      printf 'refuse %s (unsafe)\n' "$display"
      continue
    fi
    path_kb=$(sweep_size_kb "$path") || path_kb=0
    printf 'would remove %s (%s)\n' "$display" "$(sweep_human "$path_kb")"
  done <<EOF
$1
EOF
}

# A symlinked cache measures 0 KiB but must still reach the safety gate,
# so the user sees it refused rather than silently skipped.
sweep_clean_has_live_symlink() {
  local path
  while IFS= read -r path; do
    if [ -L "$path" ] && [ -e "$path" ]; then
      return 0
    fi
  done <<EOF
$1
EOF
  return 1
}

sweep_usage_clean() {
  printf '%s\n' 'Usage: sweep clean [--dry-run] [--yes] (--all | ID...)' >&2
}

# sweep clean [--dry-run] [--yes] (--all | ID...)
# Call with the user's stdin on fd 3: sweep_clean "$@" 3<&0
sweep_clean() {
  local dry_run=0 yes=0 all=0 requested='' arg
  local id label proc mode tool_cmd paths before_kb after_kb rc freed
  local tool_present do_rm do_tool total_kb=0 failed=0

  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --yes) yes=1 ;;
      --all) all=1 ;;
      -*)
        printf 'sweep: unknown option: %s\n' "$arg" >&2
        sweep_usage_clean
        return 2
        ;;
      *)
        if ! sweep_category_field "$arg" label >/dev/null 2>&1; then
          printf 'sweep: unknown category: %s\n' "$arg" >&2
          return 2
        fi
        requested="$requested $arg "
        ;;
    esac
  done

  if { [ "$all" -eq 1 ] && [ -n "$requested" ]; } || { [ "$all" -eq 0 ] && [ -z "$requested" ]; }; then
    sweep_usage_clean
    return 2
  fi

  while IFS= read -r id; do
    if [ "$all" -eq 1 ]; then
      [ "$id" != library ] || continue
    else
      case "$requested" in
        *" $id "*) ;;
        *) continue ;;
      esac
    fi

    label=$(sweep_category_field "$id" label)
    proc=$(sweep_category_field "$id" proc)
    mode=$(sweep_category_field "$id" mode)
    tool_cmd=$(sweep_category_field "$id" tool)
    paths=$(sweep_clean_paths "$id")

    # Unreadable caches (Safari without Full Disk Access) are a skip, not a
    # failure: nothing went wrong, sweep just can't see them.
    before_kb=$(sweep_clean_measure "$id") && rc=0 || rc=$?
    if [ "$rc" -eq 3 ]; then
      printf 'skip  %s (no access)\n' "$label"
      continue
    elif [ "$rc" -ne 0 ]; then
      printf 'fail  %s: could not measure cache size\n' "$label"
      failed=1
      continue
    fi

    # With --all, categories the user doesn't have are skipped silently.
    if [ "$before_kb" -eq 0 ] && ! sweep_clean_has_live_symlink "$paths"; then
      if [ "$all" -eq 0 ]; then
        printf 'skip  %s (empty)\n' "$label"
      fi
      continue
    fi

    if [ -n "$proc" ] && sweep_is_running "$proc"; then
      printf 'skip  %s (running)\n' "$label"
      continue
    fi

    tool_present=0
    if sweep_clean_tool_present "$tool_cmd"; then
      tool_present=1
    fi

    # tool: the tool owns its cache, fall back to removing folders without it.
    # rm+tool: remove folders, then let the tool tidy what folders can't reach.
    do_rm=0
    do_tool=0
    case "$mode" in
      tool) if [ "$tool_present" -eq 1 ]; then do_tool=1; else do_rm=1; fi ;;
      rm|scan) do_rm=1 ;;
      rm+tool) do_rm=1; do_tool=$tool_present ;;
    esac

    if [ "$dry_run" -eq 1 ]; then
      if [ "$do_rm" -eq 1 ]; then
        sweep_clean_dry_run_paths "$paths"
      fi
      if [ "$do_tool" -eq 1 ]; then
        printf 'would run: %s\n' "$tool_cmd"
      fi
      total_kb=$((total_kb + before_kb))
      continue
    fi

    if [ "$yes" -eq 0 ] && ! sweep_confirm "$label" "$before_kb"; then
      printf 'skip  %s (not confirmed)\n' "$label"
      continue
    fi

    if [ "$do_rm" -eq 1 ] && ! sweep_clean_remove_paths "$label" "$paths"; then
      failed=1
    fi
    if [ "$do_tool" -eq 1 ]; then
      sweep_clean_run_tool "$tool_cmd" && rc=0 || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf 'fail  %s: %s exited %s\n' "$label" "$tool_cmd" "$rc"
        failed=1
      fi
    fi

    after_kb=$(sweep_clean_measure "$id") || true
    [ -n "$after_kb" ] || after_kb=$before_kb
    freed=0
    if [ "$before_kb" -gt "$after_kb" ]; then
      freed=$((before_kb - after_kb))
    fi
    total_kb=$((total_kb + freed))
    printf 'done  %s  freed %s\n' "$label" "$(sweep_human "$freed")"
  done <<EOF
$(sweep_category_ids)
EOF

  if [ "$dry_run" -eq 1 ]; then
    printf 'Would free %s\n' "$(sweep_human "$total_kb")"
  else
    printf 'Freed %s\n' "$(sweep_human "$total_kb")"
  fi
  return "$failed"
}
