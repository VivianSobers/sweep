#!/usr/bin/env bash

sweep_clean_paths() {
  local id
  id=$1
  if [ "$id" = library ]; then
    sweep_library_other_paths
  elif [ "$id" = docker ]; then
    return 0
  else
    sweep_category_field "$id" paths
  fi
}

sweep_clean_measure() {
  local id paths path path_index
  local -a path_array
  id=$1
  if [ "$id" = docker ]; then
    sweep_category_size_kb "$id"
    return $?
  fi

  paths=$(sweep_clean_paths "$id") || return 1
  if [ -z "$paths" ]; then
    printf '0\n'
    return 0
  fi

  path_index=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    path_array[path_index]=$path
    path_index=$((path_index + 1))
  done <<EOF
$paths
EOF
  sweep_size_kb "${path_array[@]}"
}

sweep_clean_tool_present() {
  local tool_cmd tool_name
  tool_cmd=$1
  [ -n "$tool_cmd" ] || return 1
  tool_name=${tool_cmd%% *}
  command -v "$tool_name" >/dev/null 2>&1
}

sweep_clean_run_tool() {
  local tool_cmd
  local -a tool_args
  local IFS=' '
  tool_cmd=$1
  read -r -a tool_args <<< "$tool_cmd"
  [ -n "${tool_args[0]:-}" ] || return 0
  "${tool_args[@]}"
}

sweep_clean_requested() {
  local requested_id target
  target=$1
  shift
  for requested_id in "$@"; do
    if [ "$requested_id" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

sweep_clean_remove_paths() {
  local label path display failed
  label=$1
  failed=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
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
    [ -n "$path" ] || continue
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

sweep_clean() {
  local dry_run yes all_categories requested_count arg usage_error id label proc mode tool_cmd paths before_kb after_kb size_status tool_present answer action_failed tool_status freed total_kb
  local -a requested
  exec 3<&0
  dry_run=0
  yes=0
  all_categories=0
  requested_count=0
  usage_error=0

  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --yes) yes=1 ;;
      --all)
        if [ "$all_categories" -eq 1 ]; then
          usage_error=1
        fi
        all_categories=1
        ;;
      *)
        requested[requested_count]=$arg
        requested_count=$((requested_count + 1))
        ;;
    esac
  done

  if [ "$usage_error" -eq 1 ] || { [ "$all_categories" -eq 1 ] && [ "$requested_count" -gt 0 ]; } || { [ "$all_categories" -eq 0 ] && [ "$requested_count" -eq 0 ]; }; then
    printf '%s\n' 'Usage: sweep clean [--dry-run] [--yes] (--all | ID...)' >&2
    exec 3<&-
    return 2
  fi

  if [ "$all_categories" -eq 0 ]; then
    local request_index requested_id
    request_index=0
    while [ "$request_index" -lt "$requested_count" ]; do
      requested_id=${requested[$request_index]}
      if ! sweep_category_field "$requested_id" label >/dev/null 2>&1; then
        printf 'sweep: unknown category: %s\n' "$requested_id" >&2
        exec 3<&-
        return 2
      fi
      request_index=$((request_index + 1))
    done
  fi

  total_kb=0
  failed=0
  while IFS= read -r id; do
    if [ "$all_categories" -eq 1 ]; then
      [ "$id" = library ] && continue
    elif ! sweep_clean_requested "$id" "${requested[@]}"; then
      continue
    fi

    label=$(sweep_category_field "$id" label) || continue
    proc=$(sweep_category_field "$id" proc) || proc=
    mode=$(sweep_category_field "$id" mode) || continue
    tool_cmd=$(sweep_category_field "$id" tool) || tool_cmd=
    paths=$(sweep_clean_paths "$id") || paths=

    if [ -n "$proc" ] && sweep_is_running "$proc"; then
      printf 'skip  %s (running)\n' "$label"
      continue
    fi

    if before_kb=$(sweep_clean_measure "$id"); then
      :
    else
      size_status=$?
      if [ "$size_status" -eq 3 ]; then
        printf 'skip  %s (no access)\n' "$label"
      else
        printf 'fail  %s: could not measure cache size\n' "$label"
      fi
      failed=1
      continue
    fi

    tool_present=0
    if sweep_clean_tool_present "$tool_cmd"; then
      tool_present=1
    fi
    if [ "$before_kb" -eq 0 ] && { [ "$mode" != tool ] || [ "$tool_present" -eq 0 ]; }; then
      if ! sweep_clean_has_live_symlink "$paths"; then
        printf 'skip  %s (empty)\n' "$label"
        continue
      fi
    fi

    if [ "$dry_run" -eq 1 ]; then
      case "$mode" in
        tool)
          if [ "$tool_present" -eq 1 ]; then
            printf 'would run: %s\n' "$tool_cmd"
          else
            sweep_clean_dry_run_paths "$paths"
          fi
          ;;
        rm|scan)
          sweep_clean_dry_run_paths "$paths"
          ;;
        rm+tool)
          sweep_clean_dry_run_paths "$paths"
          if [ "$tool_present" -eq 1 ]; then
            printf 'would run: %s\n' "$tool_cmd"
          fi
          ;;
      esac
      total_kb=$((total_kb + before_kb))
      continue
    fi

    action_failed=0
    case "$mode" in
      tool)
        if [ "$tool_present" -eq 1 ]; then
          if [ "$yes" -eq 0 ]; then
            printf 'Clean %s (%s)? [y/N] ' "$label" "$(sweep_human "$before_kb")"
            if IFS= read -r answer <&3; then
              :
            else
              answer=
            fi
            printf '\n'
            case "$answer" in
              y|Y|yes) ;;
              *) printf 'skip  %s (not confirmed)\n' "$label"; continue ;;
            esac
          fi
          if sweep_clean_run_tool "$tool_cmd"; then
            :
          else
            tool_status=$?
            printf 'fail  %s: %s exited %s\n' "$label" "$tool_cmd" "$tool_status"
            failed=1
          fi
        else
          if [ "$yes" -eq 0 ]; then
            printf 'Clean %s (%s)? [y/N] ' "$label" "$(sweep_human "$before_kb")"
            if IFS= read -r answer; then
              :
            else
              answer=
            fi
            printf '\n'
            case "$answer" in
              y|Y|yes) ;;
              *) printf 'skip  %s (not confirmed)\n' "$label"; continue ;;
            esac
          fi
          if ! sweep_clean_remove_paths "$label" "$paths"; then
            action_failed=1
          fi
        fi
        ;;
      rm|scan)
        if [ "$yes" -eq 0 ]; then
          printf 'Clean %s (%s)? [y/N] ' "$label" "$(sweep_human "$before_kb")"
          if IFS= read -r answer <&3; then
            :
          else
            answer=
          fi
          printf '\n'
          case "$answer" in
            y|Y|yes) ;;
            *) printf 'skip  %s (not confirmed)\n' "$label"; continue ;;
          esac
        fi
        if ! sweep_clean_remove_paths "$label" "$paths"; then
          action_failed=1
        fi
        ;;
      rm+tool)
        if [ "$yes" -eq 0 ]; then
          printf 'Clean %s (%s)? [y/N] ' "$label" "$(sweep_human "$before_kb")"
          if IFS= read -r answer <&3; then
            :
          else
            answer=
          fi
          printf '\n'
          case "$answer" in
            y|Y|yes) ;;
            *) printf 'skip  %s (not confirmed)\n' "$label"; continue ;;
          esac
        fi
        if ! sweep_clean_remove_paths "$label" "$paths"; then
          action_failed=1
        fi
        if [ "$tool_present" -eq 1 ]; then
          if sweep_clean_run_tool "$tool_cmd"; then
            :
          else
            tool_status=$?
            printf 'fail  %s: %s exited %s\n' "$label" "$tool_cmd" "$tool_status"
            failed=1
          fi
        fi
        ;;
    esac

    if [ "$action_failed" -eq 1 ]; then
      failed=1
    fi
    if after_kb=$(sweep_clean_measure "$id"); then
      :
    else
      size_status=$?
      after_kb=0
      if [ "$size_status" -ne 3 ]; then
        failed=1
      fi
    fi
    if [ "$before_kb" -gt "$after_kb" ]; then
      freed=$((before_kb - after_kb))
    else
      freed=0
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
  exec 3<&-
  return "$failed"
}
