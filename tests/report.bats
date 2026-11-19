#!/usr/bin/env bats

load helpers

setup() {
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "report: shows sizes and total" {
  make_cache Library/Developer/Xcode/DerivedData 2048
  make_cache Library/Caches/Homebrew 1024
  run "$SWEEP"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Xcode.*DerivedData.*2\.0M ]]
  [[ "$output" =~ Homebrew.*Homebrew.*1\.0M ]]
  [[ "$output" =~ Reclaimable.*3\.0M ]]
  xcode_line=$(printf '%s\n' "$output" | awk '/Xcode/ { print NR; exit }')
  homebrew_line=$(printf '%s\n' "$output" | awk '/Homebrew/ { print NR; exit }')
  [ "$xcode_line" -lt "$homebrew_line" ]
}

@test "report: deletes nothing" {
  make_cache Library/Developer/Xcode/DerivedData 16
  make_cache Library/Caches/Homebrew 8
  run "$SWEEP"
  [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]
  [ -d "$HOME/Library/Caches/Homebrew" ]
}

@test "report: nothing to clean" {
  run "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$output" = "Nothing to clean." ]
}

@test "report: unreadable shows no access" {
  make_cache Library/Caches/com.apple.Safari 10
  chmod 000 "$HOME/Library/Caches/com.apple.Safari"
  run "$SWEEP"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Safari.*no\ access ]]
  [[ "$output" =~ Reclaimable.*0K ]]
}

@test "report: running app listed as skipped" {
  make_cache "Library/Application Support/Slack/Cache" 10
  printf '%s\n' '/Slack.app/' > "$STUB_RUNNING_FILE"
  run "$SWEEP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped (running): Slack"* ]]
}

@test "report: other caches row" {
  make_cache Library/Caches/com.example.foo 64
  run "$SWEEP"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Other\ caches.*Library/Caches.*other ]]
}
