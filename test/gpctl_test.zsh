#!/bin/zsh
# osascript / pgrep / open を偽物に差し替え、GlobalProtect が無い環境で gpctl の判定と制御を検査する

set -u

readonly ROOT=${0:A:h:h}
readonly GPCTL=$ROOT/gpctl
failures=0

setup() {
  export FAKE_DIR=$(mktemp -d)
  mkdir -p "$FAKE_DIR/bin" "$FAKE_DIR/dumps" "$FAKE_DIR/GlobalProtect.app"
  export GPCTL_APP_PATH=$FAKE_DIR/GlobalProtect.app
  export PATH=$FAKE_DIR/bin:$ORIGINAL_PATH

  # dump は呼ばれるたびに dumps/1, 2, ... を順に返し、尽きたら最後のものを返し続ける
  cat > "$FAKE_DIR/bin/osascript" <<'FAKE'
#!/bin/zsh
cat >/dev/null
if [[ -f $FAKE_DIR/osascript_error ]]; then
  cat "$FAKE_DIR/osascript_error" >&2
  exit 1
fi
case $2 in
  dump)
    count=$(( $(cat "$FAKE_DIR/dump_count" 2>/dev/null || echo 0) + 1 ))
    echo $count > "$FAKE_DIR/dump_count"
    dump_file=$FAKE_DIR/dumps/$count
    [[ -f $dump_file ]] || dump_file=$FAKE_DIR/dumps/$(ls "$FAKE_DIR/dumps" | sort -n | tail -1)
    cat "$dump_file"
    ;;
  click)
    print -r -- "$3" >> "$FAKE_DIR/clicks"
    ;;
esac
FAKE
  print '#!/bin/zsh\nexit 0' > "$FAKE_DIR/bin/pgrep"
  print '#!/bin/zsh\nexit 0' > "$FAKE_DIR/bin/open"
  chmod +x "$FAKE_DIR/bin/"*
}

teardown() {
  rm -rf "$FAKE_DIR"
}

set_dumps() {
  local i=1
  for dump in "$@"; do
    print -r -- "$dump" > "$FAKE_DIR/dumps/$i"
    (( i++ ))
  done
}

clicks() {
  cat "$FAKE_DIR/clicks" 2>/dev/null
}

run_gpctl() {
  stdout=$("$GPCTL" "$@" 2>/dev/null)
  exit_code=$?
}

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then
    print -r -- "ok   - $name"
  else
    print -r -- "FAIL - $name: expected [$expected], got [$actual]"
    (( failures++ ))
  fi
}

readonly ORIGINAL_PATH=$PATH

test_status_classification() {
  local cases=(
    "text:Connected"                          connected               0
    $'text:Not Connected\nbutton:Connect'     disconnected            1
    "text:Connecting..."                      connecting              1
    "text:Disconnecting..."                   disconnecting           1
    $'text:Not Connected\nbutton:Sign In'     authentication-required 1
    "button:Disconnect"                       connected               0
    "button:Connect"                          disconnected            1
    "text:GlobalProtect"                      unknown                 6
  )
  local dump expected_state expected_code
  for dump expected_state expected_code in "${cases[@]}"; do
    setup
    set_dumps "$dump"
    run_gpctl status
    assert_eq "status: ${dump//$'\n'/ | } -> state" "$expected_state" "$stdout"
    assert_eq "status: ${dump//$'\n'/ | } -> exit code" "$expected_code" "$exit_code"
    teardown
  done
}

test_connect_clicks_and_waits_until_connected() {
  setup
  set_dumps "text:Not Connected" "text:Connecting..." "text:Connected"
  run_gpctl connect
  assert_eq "connect: exit code" 0 "$exit_code"
  assert_eq "connect: clicks Connect" "Connect" "$(clicks)"
  assert_eq "connect: prints result" "Connected." "$stdout"
  teardown
}

test_connect_when_already_connected_does_not_click() {
  setup
  set_dumps "text:Connected"
  run_gpctl connect
  assert_eq "connect (already): exit code" 0 "$exit_code"
  assert_eq "connect (already): no click" "" "$(clicks)"
  teardown
}

test_connect_times_out() {
  setup
  set_dumps "text:Not Connected"
  run_gpctl connect --timeout 1
  assert_eq "connect timeout: exit code" 5 "$exit_code"
  teardown
}

test_connect_no_wait_does_not_poll() {
  setup
  set_dumps "text:Not Connected"
  run_gpctl connect --no-wait
  assert_eq "connect --no-wait: exit code" 0 "$exit_code"
  assert_eq "connect --no-wait: clicks Connect" "Connect" "$(clicks)"
  assert_eq "connect --no-wait: reads state once" 1 "$(cat "$FAKE_DIR/dump_count")"
  teardown
}

test_toggle_disconnects_when_connected() {
  setup
  set_dumps "text:Connected" "text:Connected" "text:Not Connected"
  run_gpctl toggle
  assert_eq "toggle (connected): exit code" 0 "$exit_code"
  assert_eq "toggle (connected): clicks Disconnect" "Disconnect" "$(clicks)"
  teardown
}

test_toggle_connects_when_disconnected() {
  setup
  set_dumps "text:Not Connected" "text:Not Connected" "text:Connected"
  run_gpctl toggle
  assert_eq "toggle (disconnected): exit code" 0 "$exit_code"
  assert_eq "toggle (disconnected): clicks Connect" "Connect" "$(clicks)"
  teardown
}

test_invalid_arguments() {
  setup
  run_gpctl
  assert_eq "no command: exit code" 2 "$exit_code"
  run_gpctl unknown
  assert_eq "unknown command: exit code" 2 "$exit_code"
  run_gpctl connect --timeout abc
  assert_eq "non-numeric timeout: exit code" 2 "$exit_code"
  run_gpctl connect --timeout
  assert_eq "missing timeout value: exit code" 2 "$exit_code"
  run_gpctl connect --unknown
  assert_eq "unknown option: exit code" 2 "$exit_code"
  teardown
}

test_app_not_found() {
  setup
  export GPCTL_APP_PATH=$FAKE_DIR/missing.app
  run_gpctl status
  assert_eq "app not found: exit code" 3 "$exit_code"
  teardown
}

test_permission_error() {
  setup
  print "execution error: System Events got an error: osascript is not allowed assistive access. (-1719)" > "$FAKE_DIR/osascript_error"
  run_gpctl status
  assert_eq "permission error: exit code" 4 "$exit_code"
  teardown
}

test_embedded_applescript_compiles() {
  local compiled=$(mktemp -d)/gpctl.scpt
  sed -n "/<<'APPLESCRIPT'/,/^APPLESCRIPT\$/p" "$GPCTL" | sed '1d;$d' | osacompile -o "$compiled" 2>/dev/null
  assert_eq "embedded AppleScript compiles" 0 $?
  rm -rf "${compiled:h}"
}

test_status_classification
test_connect_clicks_and_waits_until_connected
test_connect_when_already_connected_does_not_click
test_connect_times_out
test_connect_no_wait_does_not_poll
test_toggle_disconnects_when_connected
test_toggle_connects_when_disconnected
test_invalid_arguments
test_app_not_found
test_permission_error
test_embedded_applescript_compiles

if (( failures > 0 )); then
  print "$failures test(s) failed"
  exit 1
fi
print "all tests passed"
