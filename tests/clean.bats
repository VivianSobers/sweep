#!/usr/bin/env bats

load helpers

setup() {
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "clean: dry-run deletes nothing" {
  make_cache Library/Developer/Xcode/DerivedData 100
  run "$SWEEP" clean --all --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove ~/Library/Developer/Xcode/DerivedData"* ]]
  [ -f "$HOME/Library/Developer/Xcode/DerivedData/data" ]
  ! grep -q '^xcrun ' "$STUB_LOG"
}

@test "clean: yes removes xcode only" {
  make_cache Library/Developer/Xcode/DerivedData 100
  make_cache Documents/keep 1
  run "$SWEEP" clean xcode --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Developer/Xcode/DerivedData" ]
  [ -f "$HOME/Documents/keep/data" ]
  grep -q '^xcrun simctl delete unavailable$' "$STUB_LOG"
}

@test "clean: paths with spaces" {
  make_cache "Library/Application Support/Slack/Code Cache" 50
  run "$SWEEP" clean slack --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Application Support/Slack/Code Cache" ]
}

@test "clean: confirm no keeps files" {
  make_cache Library/Developer/Xcode/DerivedData 10
  run bash -c 'printf "n\\n" | "$@"' sh "$SWEEP" clean xcode
  [ -f "$HOME/Library/Developer/Xcode/DerivedData/data" ]
}

@test "clean: eof keeps files" {
  make_cache Library/Developer/Xcode/DerivedData 10
  run "$SWEEP" clean xcode < /dev/null
  [ -f "$HOME/Library/Developer/Xcode/DerivedData/data" ]
}

@test "clean: confirm yes removes" {
  make_cache Library/Developer/Xcode/DerivedData 10
  run bash -c 'printf "y\\n" | "$@"' sh "$SWEEP" clean xcode
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Developer/Xcode/DerivedData" ]
}

@test "clean: running app skipped" {
  make_cache "Library/Application Support/Slack/Cache" 10
  printf '%s\n' '/Slack.app/' > "$STUB_RUNNING_FILE"
  run "$SWEEP" clean slack --yes
  [ "$status" -eq 0 ]
  [ -f "$HOME/Library/Application Support/Slack/Cache/data" ]
  [[ "$output" == *"skip  Slack (running)"* ]]
}

@test "clean: tool used when present" {
  make_cache Library/Caches/Homebrew 10
  run "$SWEEP" clean homebrew --yes
  [ "$status" -eq 0 ]
  grep -q '^brew cleanup --prune=all$' "$STUB_LOG"
  [ -d "$HOME/Library/Caches/Homebrew" ]
}

@test "clean: tool missing falls back" {
  remove_stub npm
  make_cache .npm/_cacache 10
  run "$SWEEP" clean npm --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.npm/_cacache" ]
}

@test "clean: tool failure continues" {
  STUB_EXIT_brew=1
  export STUB_EXIT_brew
  make_cache Library/Caches/Homebrew 10
  make_cache Library/Developer/Xcode/DerivedData 10
  run "$SWEEP" clean homebrew xcode --yes
  [ "$status" -eq 1 ]
  [[ "$output" == *"fail  Homebrew"* ]]
  [ ! -e "$HOME/Library/Developer/Xcode/DerivedData" ]
}

@test "clean: unknown category" {
  make_cache Library/Developer/Xcode/DerivedData 10
  run "$SWEEP" clean xcode frob --yes
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown category: frob"* ]]
  [ -f "$HOME/Library/Developer/Xcode/DerivedData/data" ]
}

@test "clean: symlink escape refused" {
  mkdir -p "$BATS_TEST_TMPDIR/outside" "$HOME/Library/Developer/Xcode"
  printf 'keep\n' > "$BATS_TEST_TMPDIR/outside/file"
  ln -s "$BATS_TEST_TMPDIR/outside" "$HOME/Library/Developer/Xcode/DerivedData"
  run "$SWEEP" clean xcode --yes
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/outside/file" ]
  [[ "$output" == *"refuse"* ]]
}

@test "clean: all excludes library" {
  make_cache Library/Caches/com.example.foo 8
  run "$SWEEP" clean --all --yes
  [ "$status" -eq 0 ]
  [ -f "$HOME/Library/Caches/com.example.foo/data" ]
  run "$SWEEP" clean library --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Caches/com.example.foo" ]
}
