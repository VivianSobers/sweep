#!/usr/bin/env bash

sweep_registry() {
  cat <<'REGISTRY'
xcode|Xcode|rm+tool|/Xcode.app/Contents/MacOS/Xcode|xcrun simctl delete unavailable|~/Library/Developer/Xcode/DerivedData;~/Library/Developer/Xcode/iOS DeviceSupport;~/Library/Developer/CoreSimulator/Caches
homebrew|Homebrew|tool||brew cleanup --prune=all|~/Library/Caches/Homebrew
npm|npm|tool||npm cache clean --force|~/.npm/_cacache
pnpm|pnpm|tool||pnpm store prune|~/Library/pnpm/store
yarn|Yarn|tool||yarn cache clean|~/Library/Caches/Yarn
pip|pip|tool||pip3 cache purge|~/Library/Caches/pip
conda|conda|tool||conda clean --all --yes|~/miniconda3/pkgs;~/anaconda3/pkgs;~/miniforge3/pkgs
docker|Docker build cache|tool||docker builder prune --force|
gradle|Gradle|rm|GradleDaemon||~/.gradle/caches
android|Android Studio|rm|/Android Studio.app/||~/Library/Caches/Google/AndroidStudio*;~/.android/cache
cocoapods|CocoaPods|tool||pod cache clean --all|~/Library/Caches/CocoaPods
chrome|Chrome|rm|/Google Chrome.app/Contents/MacOS/Google Chrome||~/Library/Caches/Google/Chrome
safari|Safari|rm|/Safari.app/Contents/MacOS/Safari||~/Library/Caches/com.apple.Safari
firefox|Firefox|rm|/Firefox.app/||~/Library/Caches/Firefox
arc|Arc|rm|/Arc.app/||~/Library/Caches/company.thebrowser.Browser
slack|Slack|rm|/Slack.app/||~/Library/Application Support/Slack/Cache;~/Library/Application Support/Slack/Code Cache;~/Library/Application Support/Slack/Service Worker/CacheStorage
discord|Discord|rm|/Discord.app/||~/Library/Application Support/discord/Cache;~/Library/Application Support/discord/Code Cache
spotify|Spotify|rm|/Spotify.app/||~/Library/Caches/com.spotify.client
vscode|VS Code|rm|/Visual Studio Code.app/||~/Library/Application Support/Code/Cache;~/Library/Application Support/Code/CachedData;~/Library/Application Support/Code/CachedExtensionVSIXs
teams|Teams|rm|/Microsoft Teams.app/||~/Library/Containers/com.microsoft.teams2/Data/Library/Caches
zoom|Zoom|rm|/zoom.us.app/||~/Library/Caches/us.zoom.xos
library|Other caches|scan|||~/Library/Caches
REGISTRY
}

sweep_category_ids() {
  sweep_registry | awk -F '|' '{ print $1 }'
}

sweep_expand_path() {
  local raw full_path expanded has_glob tilde
  raw=$1
  tilde=$(printf '\176')
  case "$raw" in
    "$tilde/"*) full_path="$HOME/${raw:2}" ;;
    "$tilde") full_path=$HOME ;;
    *) full_path=$raw ;;
  esac

  has_glob=0
  case "$full_path" in
    *'*'*|*'?'*|*'['*) has_glob=1 ;;
  esac

  local IFS='
'
  for expanded in $full_path; do
    if [ "$has_glob" -eq 1 ]; then
      if [ -e "$expanded" ] || [ -L "$expanded" ]; then
        printf '%s\n' "$expanded"
      fi
    else
      printf '%s\n' "$expanded"
    fi
  done
}

sweep_category_field() {
  [ "$#" -eq 2 ] || return 1
  local id field value paths path remaining
  id=$1
  field=$2
  case "$field" in
    label|mode|proc|tool|paths) ;;
    *) return 1 ;;
  esac

  case "$field" in
    label) value=$(sweep_registry | awk -F '|' -v id="$id" '$1 == id { print $2; found=1; exit } END { if (!found) exit 1 }') || return 1; printf '%s\n' "$value" ;;
    mode) value=$(sweep_registry | awk -F '|' -v id="$id" '$1 == id { print $3; found=1; exit } END { if (!found) exit 1 }') || return 1; printf '%s\n' "$value" ;;
    proc) value=$(sweep_registry | awk -F '|' -v id="$id" '$1 == id { print $4; found=1; exit } END { if (!found) exit 1 }') || return 1; printf '%s\n' "$value" ;;
    tool) value=$(sweep_registry | awk -F '|' -v id="$id" '$1 == id { print $5; found=1; exit } END { if (!found) exit 1 }') || return 1; printf '%s\n' "$value" ;;
    paths)
      paths=$(sweep_registry | awk -F '|' -v id="$id" '$1 == id { print $6; found=1; exit } END { if (!found) exit 1 }') || return 1
      while [ -n "$paths" ]; do
        case "$paths" in
          *';'*) path=${paths%%;*}; remaining=${paths#*;} ;;
          *) path=$paths; remaining= ;;
        esac
        if [ -n "$path" ]; then
          sweep_expand_path "$path"
        fi
        paths=$remaining
      done
      ;;
  esac
}

sweep_docker_size_kb() {
  local docker_output
  docker_output=$(docker system df --format '{{.Type}}|{{.Size}}' 2>/dev/null) || docker_output=
  printf '%s\n' "$docker_output" | awk -F '|' '$1 == "Build Cache" {
    size=$2
    unit=size
    gsub(/[0-9.]/, "", unit)
    number=size
    sub(/[A-Za-z]+$/, "", number)
    if (number !~ /^[0-9]+([.][0-9]+)?$/) next
    if (unit == "B") kb=number / 1024
    else if (unit == "kB" || unit == "KB" || unit == "KiB") kb=number
    else if (unit == "MB") kb=number * 1000000 / 1024
    else if (unit == "MiB") kb=number * 1024
    else if (unit == "GB") kb=number * 1000000000 / 1024
    else if (unit == "GiB") kb=number * 1048576
    else if (unit == "TB") kb=number * 1000000000000 / 1024
    else if (unit == "TiB") kb=number * 1073741824
    else kb=0
    print int(kb)
    found=1
    exit
  } END { if (!found) print 0 }'
}

sweep_category_size_kb() {
  [ "$#" -eq 1 ] || return 1
  local id paths
  id=$1
  if [ "$id" = docker ]; then
    if command -v docker >/dev/null 2>&1; then
      sweep_docker_size_kb
    else
      printf '0\n'
    fi
    return 0
  fi

  paths=$(sweep_category_field "$id" paths) || return 1
  if [ -z "$paths" ]; then
    printf '0\n'
    return 0
  fi
  local -a path_array
  local path path_index
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
