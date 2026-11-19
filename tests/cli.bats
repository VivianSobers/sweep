#!/usr/bin/env bats

load helpers

setup() {
  setup_sandbox
}

teardown() {
  teardown_sandbox
}

@test "cli: version" {
  run "$SWEEP" --version
  [ "$status" -eq 0 ]
  [ "$output" = "sweep 0.1.0" ]
}

@test "cli: help" {
  run "$SWEEP" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: sweep"* ]]
}

@test "cli: unknown command" {
  run "$SWEEP" frob
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "cli: list" {
  run "$SWEEP" list
  [ "$status" -eq 0 ]
  [[ "$output" == *$'xcode\tXcode\t'* ]]
  [[ "$output" == *$'slack\tSlack\t'*"Application Support/Slack/Code Cache"* ]]
}

@test "cli: refuses root" {
  STUB_UID=0
  export STUB_UID
  run "$SWEEP" --version
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to run as root"* ]]
}

@test "cli: works via symlink" {
  ln -s "$SWEEP" "$BATS_TEST_TMPDIR/sw"
  run "$BATS_TEST_TMPDIR/sw"
  [ "$status" -eq 0 ]
}
