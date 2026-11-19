#!/usr/bin/env bash

sweep_library_other_paths() {
  local cache_root child id known category_paths registered
  cache_root="$HOME/Library/Caches"
  [ -d "$cache_root" ] || return 0

  for child in "$cache_root"/*; do
    [ -e "$child" ] || [ -L "$child" ] || continue
    case "$child" in
      "$cache_root/Google"|"$cache_root/Google/"*) continue ;;
    esac

    known=0
    while IFS= read -r id; do
      [ "$id" = library ] && continue
      [ "$id" = docker ] && continue
      category_paths=$(sweep_category_field "$id" paths) || continue
      while IFS= read -r registered; do
        if [ "$registered" = "$child" ]; then
          known=1
          break
        fi
      done <<EOF
$category_paths
EOF
      [ "$known" -eq 1 ] && break
    done <<EOF
$(sweep_category_ids)
EOF

    if [ "$known" -eq 0 ]; then
      printf '%s\n' "$child"
    fi
  done
}

sweep_display_path() {
  local path display tilde
  path=$1
  tilde=$(printf '\176')
  case "$path" in
    "$HOME"/*) display="${tilde}/${path#"$HOME"/}" ;;
    "$HOME") display=$tilde ;;
    *) display=$path ;;
  esac
  if [ "${#display}" -gt 44 ]; then
    display="${display:0:43}…"
  fi
  printf '%s\n' "$display"
}

sweep_report() {
  local rows skipped total newline id label proc paths path size_kb size_status size_display numeric running display tilde path_index
  local -a path_array
  rows=
  skipped=
  total=0
  tilde=$(printf '\176')
  newline='
'

  while IFS= read -r id; do
    label=$(sweep_category_field "$id" label) || continue
    proc=$(sweep_category_field "$id" proc) || proc=
    running=0
    if [ -n "$proc" ] && sweep_is_running "$proc"; then
      running=1
      if [ -z "$skipped" ]; then
        skipped=$label
      else
        skipped="$skipped, $label"
      fi
    fi

    if [ "$id" = library ]; then
      paths=$(sweep_library_other_paths)
      [ -n "$paths" ] || continue
      path_index=0
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        path_array[path_index]=$path
        path_index=$((path_index + 1))
      done <<EOF
$paths
EOF
      if size_kb=$(sweep_size_kb "${path_array[@]}"); then
        size_display=$(sweep_human "$size_kb")
        numeric=$size_kb
        if [ "$running" -eq 0 ]; then
          total=$((total + size_kb))
        fi
      else
        size_status=$?
        if [ "$size_status" -eq 3 ]; then
          size_display='no access'
          numeric=-1
        else
          continue
        fi
      fi
      if [ "$running" -eq 1 ]; then
        numeric=-1
      fi
      display="${tilde}/Library/Caches (other)"
      rows="${rows}${numeric}|${label}|${display}|${size_display}|${running}${newline}"
      continue
    fi

    paths=$(sweep_category_field "$id" paths) || continue
    if [ "$id" = docker ]; then
      size_kb=$(sweep_category_size_kb "$id") || size_kb=0
      [ "$size_kb" -gt 0 ] || continue
      size_display=$(sweep_human "$size_kb")
      numeric=$size_kb
      if [ "$running" -eq 0 ]; then
        total=$((total + size_kb))
      else
        numeric=-1
      fi
      rows="${rows}${numeric}|${label}|Docker build cache|${size_display}|${running}${newline}"
      continue
    fi

    [ -n "$paths" ] || continue
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      [ -e "$path" ] || [ -L "$path" ] || continue
      if size_kb=$(sweep_size_kb "$path"); then
        size_display=$(sweep_human "$size_kb")
        numeric=$size_kb
        if [ "$running" -eq 0 ]; then
          total=$((total + size_kb))
        else
          numeric=-1
        fi
      else
        size_status=$?
        if [ "$size_status" -eq 3 ]; then
          size_display='no access'
          numeric=-1
        else
          continue
        fi
      fi
      display=$(sweep_display_path "$path")
      rows="${rows}${numeric}|${label}|${display}|${size_display}|${running}${newline}"
    done <<EOF
$paths
EOF
  done <<EOF
$(sweep_category_ids)
EOF

  if [ -z "$rows" ]; then
    printf '%s\n' 'Nothing to clean.'
    return 0
  fi

  printf '  %-20s %-44s %s\n' CATEGORY LOCATION SIZE
  printf '  %s\n' '──────────────────────────────────────────────────────────────────────'
  printf '%s' "$rows" | sort -t '|' -k1,1nr | while IFS='|' read -r _row_kb row_label row_location row_size _row_running; do
    printf '  %-20s %-44s %s\n' "$row_label" "$row_location" "$row_size"
  done
  printf '  %s\n' '──────────────────────────────────────────────────────────────────────'
  printf '  %-65s %s\n' 'Reclaimable' "$(sweep_human "$total")"
  if [ -n "$skipped" ]; then
    printf '  Skipped (running): %s\n' "$skipped"
  fi
}
