#!/usr/bin/env bats

load helpers

setup() {
  setup_sandbox
  source "$BATS_TEST_DIRNAME/../lib/safety.sh"
}

teardown() {
  teardown_sandbox
}

@test "safe: accepts path inside Library/Caches" {
  make_cache Library/Caches/Foo 1
  run sweep_is_safe_path "$HOME/Library/Caches/Foo"
  [ "$status" -eq 0 ]
}

@test "safe: rejects HOME itself" {
  run sweep_is_safe_path "$HOME"
  [ "$status" -eq 1 ]
}

@test "safe: rejects root" {
  run sweep_is_safe_path /
  [ "$status" -eq 1 ]
}

@test "safe: rejects tmp path" {
  run sweep_is_safe_path "$BATS_TEST_TMPDIR/outside"
  [ "$status" -eq 1 ]
}

@test "safe: rejects one level below HOME" {
  run sweep_is_safe_path "$HOME/Library"
  [ "$status" -eq 1 ]
}

@test "safe: rejects Documents" {
  mkdir -p "$HOME/Documents/x"
  run sweep_is_safe_path "$HOME/Documents/x"
  [ "$status" -eq 1 ]
}

@test "safe: rejects nonexistent path" {
  run sweep_is_safe_path "$HOME/Library/Caches/missing"
  [ "$status" -eq 1 ]
}

@test "safe: rejects symlink escaping HOME" {
  mkdir -p "$BATS_TEST_TMPDIR/outside" "$HOME/Library/Developer/Xcode"
  ln -s "$BATS_TEST_TMPDIR/outside" "$HOME/Library/Developer/Xcode/DerivedData"
  run sweep_is_safe_path "$HOME/Library/Developer/Xcode/DerivedData"
  [ "$status" -eq 1 ]
}

@test "safe: rejects .. traversal" {
  run sweep_is_safe_path "$HOME/Library/Caches/../../.."
  [ "$status" -eq 1 ]
}

@test "require_user: exits 1 as root" {
  STUB_UID=0
  export STUB_UID
  run sweep_require_user
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to run as root"* ]]
}
