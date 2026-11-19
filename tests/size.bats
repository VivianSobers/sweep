#!/usr/bin/env bats

load helpers

setup() {
  setup_sandbox
  source "$BATS_TEST_DIRNAME/../lib/size.sh"
}

teardown() {
  teardown_sandbox
}

@test "size: sums kib" {
  make_cache Library/Caches/one 100
  make_cache Library/Caches/two 50
  run sweep_size_kb "$HOME/Library/Caches/one" "$HOME/Library/Caches/two"
  [ "$status" -eq 0 ]
  [ "$output" -ge 150 ]
  [ "$output" -le 160 ]
}

@test "size: zero for missing" {
  run sweep_size_kb "$HOME/missing"
  [ "$status" -eq 0 ]
  [ "$output" = 0 ]
}

@test "size: unreadable returns 3" {
  make_cache Library/Caches/locked 10
  chmod 000 "$HOME/Library/Caches/locked"
  run sweep_size_kb "$HOME/Library/Caches/locked"
  [ "$status" -eq 3 ]
}

@test "human: formats" {
  [ "$(sweep_human 512)" = "512K" ]
  [ "$(sweep_human 1536)" = "1.5M" ]
  [ "$(sweep_human 14889779)" = "14.2G" ]
}

@test "size: readable file is not unreadable" {
  mkdir -p "$HOME/Library/Caches"
  dd if=/dev/zero of="$HOME/Library/Caches/blob" bs=1024 count=8 2>/dev/null
  chmod 644 "$HOME/Library/Caches/blob"
  run sweep_size_kb "$HOME/Library/Caches/blob"
  [ "$status" -eq 0 ]
  [ "$output" -ge 8 ]
}
