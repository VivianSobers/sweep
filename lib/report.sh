#!/usr/bin/env bash

# Every path some named category owns, one per line.
sweep_registered_paths() {
  local id
  while IFS= read -r id; do
    case "$id" in
      library|docker) continue ;;
    esac
    sweep_category_field "$id" paths
  done <<EOF
$(sweep_category_ids)
EOF
}

# Direct children of ~/Library/Caches that no named category owns.
sweep_library_other_paths() {
  local cache_root="$HOME/Library/Caches" known child nl='
'
  [ -d "$cache_root" ] || return 0
  known="$nl$(sweep_registered_paths)$nl"

  for child in "$cache_root"/*; do
    [ -e "$child" ] || [ -L "$child" ] || continue
    case "$known" in
      *"$nl$child$nl"*) continue ;;
    esac
    # Google/ holds Chrome and Android Studio, which have their own rows.
    [ "$child" != "$cache_root/Google" ] || continue
    printf '%s\n' "$child"
  done
}

sweep_display_path() {
  local display=$1
  # shellcheck disable=SC2088 # a literal ~ is the point: it is for display
  case "$display" in
    "$HOME"/*) display="~/${display#"$HOME"/}" ;;
  esac
  if [ "${#display}" -gt 44 ]; then
    display="${display:0:43}…"
  fi
  printf '%s\n' "$display"
}

# Appends one row to the caller's report state (rows, total, skipped) for
# the category in $label/$running. rc is sweep_size_kb's status: 3 means
# part of it is unreadable. Rows sort by kb; -1 sorts them last.
sweep_report_add_row() {
  local location=$1 kb=$2 rc=$3 size sort_kb
  if [ "$rc" -eq 3 ]; then
    size='no access'
    sort_kb=-1
  else
    size=$(sweep_human "$kb")
    sort_kb=$kb
  fi
  if [ "$running" -eq 1 ]; then
    sort_kb=-1
    case ", $skipped," in
      *", $label,"*) ;;
      *) skipped="${skipped:+$skipped, }$label" ;;
    esac
  elif [ "$rc" -eq 0 ]; then
    total=$((total + kb))
  fi
  rows="$rows$sort_kb|$label|$location|$size
"
}

sweep_report() {
  local rows='' skipped='' total=0
  local id label proc running paths path kb rc line

  while IFS= read -r id; do
    label=$(sweep_category_field "$id" label)
    proc=$(sweep_category_field "$id" proc)
    running=0
    if [ -n "$proc" ] && sweep_is_running "$proc"; then
      running=1
    fi

    case "$id" in
      docker)
        kb=$(sweep_category_size_kb docker)
        if [ "$kb" -gt 0 ]; then
          sweep_report_add_row 'Docker build cache' "$kb" 0
        fi
        ;;
      library)
        paths=$(sweep_library_other_paths)
        if [ -n "$paths" ]; then
          kb=$(sweep_size_kb_lines "$paths") && rc=0 || rc=$?
          # shellcheck disable=SC2088 # display text, not a path
          sweep_report_add_row "~/Library/Caches (other)" "$kb" "$rc"
        fi
        ;;
      *)
        paths=$(sweep_category_field "$id" paths)
        while IFS= read -r path; do
          [ -e "$path" ] || [ -L "$path" ] || continue
          kb=$(sweep_size_kb "$path") && rc=0 || rc=$?
          sweep_report_add_row "$(sweep_display_path "$path")" "$kb" "$rc"
        done <<EOF
$paths
EOF
        ;;
    esac
  done <<EOF
$(sweep_category_ids)
EOF

  if [ -z "$rows" ]; then
    printf '%s\n' 'Nothing to clean.'
    return 0
  fi

  line='──────────────────────────────────────────────────────────────────────'
  printf '  %-20s %-44s %s\n' CATEGORY LOCATION SIZE
  printf '  %s\n' "$line"
  printf '%s' "$rows" | sort -t '|' -k1,1nr | while IFS='|' read -r _ label path kb; do
    printf '  %-20s %-44s %s\n' "$label" "$path" "$kb"
  done
  printf '  %s\n' "$line"
  printf '  %-65s %s\n' 'Reclaimable' "$(sweep_human "$total")"
  if [ -n "$skipped" ]; then
    printf '  Skipped (running): %s\n' "$skipped"
  fi
}
