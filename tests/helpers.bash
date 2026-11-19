setup_sandbox() {
  export HOME="$BATS_TEST_TMPDIR/home"
  STUB_BIN="$BATS_TEST_TMPDIR/stubs"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  STUB_RUNNING_FILE="$BATS_TEST_TMPDIR/running"
  export STUB_BIN STUB_LOG STUB_RUNNING_FILE
  mkdir -p "$HOME" "$STUB_BIN"
  : > "$STUB_LOG"
  : > "$STUB_RUNNING_FILE"

  for stub_name in pgrep brew npm pnpm yarn pip3 conda pod xcrun docker id; do
    cat > "$STUB_BIN/$stub_name" <<'STUB'
#!/usr/bin/env bash
name=${0##*/}
printf '%s' "$name" >> "$STUB_LOG"
for arg in "$@"; do
  printf ' %s' "$arg" >> "$STUB_LOG"
done
printf '\n' >> "$STUB_LOG"

if [ "$name" = pgrep ]; then
  pattern=
  for arg in "$@"; do
    pattern=$arg
  done
  if [ -f "$STUB_RUNNING_FILE" ]; then
    while IFS= read -r running_pattern; do
      if [ "$running_pattern" = "$pattern" ]; then
        exit 0
      fi
    done < "$STUB_RUNNING_FILE"
  fi
  exit 1
fi

if [ "$name" = id ] && [ "${1:-}" = -u ]; then
  printf '%s\n' "${STUB_UID:-501}"
  exit 0
fi

exit_variable="STUB_EXIT_$name"
exit "${!exit_variable:-0}"
STUB
    chmod +x "$STUB_BIN/$stub_name"
  done

  export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
  SWEEP="$BATS_TEST_DIRNAME/../bin/sweep"
  export SWEEP
}

make_cache() {
  cache_path="$HOME/$1"
  cache_kb="$2"
  mkdir -p "$cache_path"
  dd if=/dev/zero of="$cache_path/data" bs=1024 count="$cache_kb" 2>/dev/null
}

remove_stub() {
  rm -f "$STUB_BIN/$1"
}

teardown_sandbox() {
  chmod -R u+rwx "$HOME" 2>/dev/null || true
}
