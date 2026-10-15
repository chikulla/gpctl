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
print -r -- "$2" >> "$FAKE_DIR/actions"
if [[ -f $FAKE_DIR/osascript_error ]]; then
  cat "$FAKE_DIR/osascript_error" >&2
  exit 1
fi
case $2 in
  dump | peek)
    print -r -- "$2" >> "$FAKE_DIR/reads"
    count=$(( $(cat "$FAKE_DIR/dump_count" 2>/dev/null || echo 0) + 1 ))
    echo $count > "$FAKE_DIR/dump_count"
    dump_file=$FAKE_DIR/dumps/$count
    [[ -f $dump_file ]] || dump_file=$FAKE_DIR/dumps/$(ls "$FAKE_DIR/dumps" | sort -n | tail -1)
    cat "$dump_file"
    ;;
  click)
    print -r -- "$3" >> "$FAKE_DIR/clicks"
    ;;
  refresh)
    [[ -f $FAKE_DIR/refresh_pending ]] || print -r -- "Refresh Connection menu item" >> "$FAKE_DIR/clicks"
    if [[ -f $FAKE_DIR/refresh_confirm_error ]]; then
      print -r -- "UI element not found: Refresh Connection confirmation button (1001)" >&2
      exit 1
    elif [[ -f $FAKE_DIR/no_refresh_confirmation ]]; then
      print -r -- "no-confirmation"
    else
      print -r -- "Refresh Connection button" >> "$FAKE_DIR/clicks"
      print -r -- "confirmed"
    fi
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
  stdout=$("$GPCTL" "$@" 2>"$FAKE_DIR/stderr")
  exit_code=$?
  stderr=$(cat "$FAKE_DIR/stderr")
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
    "text:接続済み"                            connected               0
    $'text:未接続\nbutton:接続'               disconnected            1
    "text:接続中..."                           connecting              1
    "text:切断中..."                           disconnecting           1
    $'text:未接続\nbutton:サインイン'       authentication-required 1
    "button:切断"                             connected               0
    "button:接続"                             disconnected            1
    $'text:接続済み\ntext:切断するには管理者に連絡' connected 0
    $'text:接続済み\ntext:認証済み'          connected               0
    $'text:Connected\ntext:Authentication succeeded' connected 0
    $'text:Refresh?\nbutton:Refresh Connection' refresh-confirmation-required 1
    $'text:接続を更新しますか?\nbutton:接続を更新' refresh-confirmation-required 1
    $'text:Connected\ntext:Not Connected' unknown 6
    $'text:Connected\nbutton:Sign In' unknown 6
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

test_connect_reads_once_and_clicks_once() {
  setup
  set_dumps $'text:Not Connected\nbutton:Connect' "text:Connected"
  run_gpctl connect
  assert_eq "connect: exit code" 0 "$exit_code"
  assert_eq "connect: clicks Connect" "Connect" "$(clicks)"
  assert_eq "connect: reports operation started" "Connection started. Check 'gpctl status' to confirm it." "$stdout"
  assert_eq "connect: one read and one click" $'dump\nclick' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_connect_uses_japanese_button_label() {
  setup
  set_dumps $'text:未接続\nbutton:接続' "text:接続済み"
  run_gpctl connect
  assert_eq "connect (Japanese UI): exit code" 0 "$exit_code"
  assert_eq "connect (Japanese UI): clicks 接続" "接続" "$(clicks)"
  assert_eq "connect (Japanese UI): reports operation started" "Connection started. Check 'gpctl status' to confirm it." "$stdout"
  assert_eq "connect (Japanese UI): one read and one click" $'dump\nclick' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_disconnect_reads_once_and_clicks_once() {
  setup
  set_dumps $'text:Connected\nbutton:Disconnect' "text:Not Connected"
  run_gpctl disconnect
  assert_eq "disconnect: exit code" 0 "$exit_code"
  assert_eq "disconnect: clicks Disconnect" "Disconnect" "$(clicks)"
  assert_eq "disconnect: reports operation started" "Disconnection started. Check 'gpctl status' to confirm it." "$stdout"
  assert_eq "disconnect: one read and one click" $'dump\nclick' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_disconnect_uses_japanese_button_label() {
  setup
  set_dumps $'text:接続済み\nbutton:切断' "text:未接続"
  run_gpctl disconnect
  assert_eq "disconnect (Japanese UI): exit code" 0 "$exit_code"
  assert_eq "disconnect (Japanese UI): clicks 切断" "切断" "$(clicks)"
  assert_eq "disconnect (Japanese UI): reports operation started" "Disconnection started. Check 'gpctl status' to confirm it." "$stdout"
  assert_eq "disconnect (Japanese UI): one read and one click" $'dump\nclick' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_connect_when_already_connected_does_not_click() {
  setup
  set_dumps "text:Connected"
  run_gpctl connect
  assert_eq "connect (already): exit code" 0 "$exit_code"
  assert_eq "connect (already): no click" "" "$(clicks)"
  assert_eq "connect (already): one read" "dump" "$(cat "$FAKE_DIR/reads")"
  teardown
}

test_connect_does_not_click_while_connecting() {
  setup
  set_dumps $'text:Connecting...\nbutton:Connect' "text:Connected"
  run_gpctl connect
  assert_eq "connect (connecting with Connect button): exit code" 1 "$exit_code"
  assert_eq "connect (connecting with Connect button): no click" "" "$(clicks)"
  assert_eq "connect (connecting with Connect button): one read" "dump" "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_disconnect_does_not_click_while_disconnecting() {
  setup
  set_dumps "text:Disconnecting..."
  run_gpctl disconnect
  assert_eq "disconnect (disconnecting): exit code" 1 "$exit_code"
  assert_eq "disconnect (disconnecting): no click" "" "$(clicks)"
  assert_eq "disconnect (disconnecting): one read" "dump" "$(cat "$FAKE_DIR/reads")"
  teardown
}

test_refresh_with_confirmation() {
  setup
  set_dumps $'text:Connected\nbutton:Disconnect'
  run_gpctl refresh
  assert_eq "refresh (confirmation shown): exit code" 0 "$exit_code"
  assert_eq "refresh (confirmation shown): selects menu item and confirms" $'Refresh Connection menu item\nRefresh Connection button' "$(clicks)"
  assert_eq "refresh (confirmation shown): prints result" "Connection refresh started." "$stdout"
  assert_eq "refresh (confirmation shown): one state read" "dump" "$(cat "$FAKE_DIR/reads")"
  assert_eq "refresh (confirmation shown): one read and one refresh action" $'dump\nrefresh' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_refresh_while_connecting() {
  setup
  set_dumps $'text:Connecting...\nbutton:Connect'
  run_gpctl refresh
  assert_eq "refresh (connecting): exit code" 0 "$exit_code"
  assert_eq "refresh (connecting): selects menu item and confirms" $'Refresh Connection menu item\nRefresh Connection button' "$(clicks)"
  assert_eq "refresh (connecting): one read and one refresh action" $'dump\nrefresh' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_refresh_with_confirmation_pending() {
  setup
  set_dumps $'text:Refresh?\nbutton:Refresh Connection'
  touch "$FAKE_DIR/refresh_pending"
  run_gpctl refresh
  assert_eq "refresh (confirmation pending): exit code" 0 "$exit_code"
  assert_eq "refresh (confirmation pending): clicks confirmation only" "Refresh Connection button" "$(clicks)"
  assert_eq "refresh (confirmation pending): prints result" "Connection refresh started." "$stdout"
  assert_eq "refresh (confirmation pending): one read and one refresh action" $'dump\nrefresh' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_refresh_when_disconnected_does_not_click() {
  setup
  set_dumps $'text:Not Connected\nbutton:Connect'
  run_gpctl refresh
  assert_eq "refresh (disconnected): exit code" 1 "$exit_code"
  assert_eq "refresh (disconnected): no click" "" "$(clicks)"
  assert_eq "refresh (disconnected): no success message" "" "$stdout"
  assert_eq "refresh (disconnected): advises connect" "gpctl: GlobalProtect is disconnected. Use 'gpctl connect'." "$stderr"
  assert_eq "refresh (disconnected): one read, no refresh action" "dump" "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_refresh_in_other_states_does_not_click() {
  local cases=(
    $'text:Not Connected\nbutton:Sign In' 1
    "text:Disconnecting..." 1
    "text:GlobalProtect" 6
  )
  local dump expected_code
  for dump expected_code in "${cases[@]}"; do
    setup
    set_dumps "$dump"
    run_gpctl refresh
    assert_eq "refresh (${dump//$'\n'/ | }): exit code" "$expected_code" "$exit_code"
    assert_eq "refresh (${dump//$'\n'/ | }): no click" "" "$(clicks)"
    assert_eq "refresh (${dump//$'\n'/ | }): one read, no refresh action" "dump" "$(cat "$FAKE_DIR/actions")"
    teardown
  done
}

test_refresh_requires_confirmation() {
  setup
  set_dumps "text:Connected"
  touch "$FAKE_DIR/no_refresh_confirmation"
  run_gpctl refresh
  assert_eq "refresh (no confirmation): exit code" 6 "$exit_code"
  assert_eq "refresh (no confirmation): selects menu item only" "Refresh Connection menu item" "$(clicks)"
  assert_eq "refresh (no confirmation): no success message" "" "$stdout"
  assert_eq "refresh (no confirmation): one state read" "dump" "$(cat "$FAKE_DIR/reads")"
  assert_eq "refresh (no confirmation): one read and one refresh action" $'dump\nrefresh' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_refresh_fails_if_confirmation_click_errors() {
  setup
  set_dumps "text:Connected"
  touch "$FAKE_DIR/refresh_confirm_error"
  run_gpctl refresh
  assert_eq "refresh confirmation error: exit code" 6 "$exit_code"
  assert_eq "refresh confirmation error: no success message" "" "$stdout"
  assert_eq "refresh confirmation error: one read and one refresh action" $'dump\nrefresh' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_toggle_disconnects_when_connected() {
  setup
  set_dumps $'text:Connected\nbutton:Disconnect' "text:Not Connected"
  run_gpctl toggle
  assert_eq "toggle (connected): exit code" 0 "$exit_code"
  assert_eq "toggle (connected): clicks Disconnect" "Disconnect" "$(clicks)"
  assert_eq "toggle (connected): reports operation started" "Disconnection started. Check 'gpctl status' to confirm it." "$stdout"
  assert_eq "toggle (connected): one read and one click" $'dump\nclick' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_toggle_connects_when_disconnected() {
  setup
  set_dumps $'text:Not Connected\nbutton:Connect' "text:Connected"
  run_gpctl toggle
  assert_eq "toggle (disconnected): exit code" 0 "$exit_code"
  assert_eq "toggle (disconnected): clicks Connect" "Connect" "$(clicks)"
  assert_eq "toggle (disconnected): reports operation started" "Connection started. Check 'gpctl status' to confirm it." "$stdout"
  assert_eq "toggle (disconnected): one read and one click" $'dump\nclick' "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_toggle_does_not_click_while_connecting() {
  setup
  set_dumps $'text:接続中...\nbutton:接続' "text:接続済み"
  run_gpctl toggle
  assert_eq "toggle (connecting with Connect button): exit code" 1 "$exit_code"
  assert_eq "toggle (connecting with Connect button): no click" "" "$(clicks)"
  assert_eq "toggle (connecting with Connect button): one read" "dump" "$(cat "$FAKE_DIR/actions")"
  teardown
}

test_invalid_arguments() {
  setup
  run_gpctl
  assert_eq "no command: exit code" 2 "$exit_code"
  run_gpctl unknown
  assert_eq "unknown command: exit code" 2 "$exit_code"
  run_gpctl connect --timeout 1
  assert_eq "removed --timeout option: exit code" 2 "$exit_code"
  run_gpctl connect --timeout
  assert_eq "removed --timeout without value: exit code" 2 "$exit_code"
  run_gpctl connect --no-wait
  assert_eq "removed --no-wait option: exit code" 2 "$exit_code"
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

test_closed_window_is_not_a_permission_error() {
  setup
  print 'execution error: System Events got an error: Can’t get window 1 of application process "GlobalProtect". Invalid index. (-1719)' > "$FAKE_DIR/osascript_error"
  run_gpctl status
  assert_eq "closed window: exit code" 6 "$exit_code"
  teardown
}

test_embedded_applescript_compiles() {
  local compiled=$(mktemp -d)/gpctl.scpt
  sed -n "/<<'APPLESCRIPT'/,/^APPLESCRIPT\$/p" "$GPCTL" | sed '1d;$d' | osacompile -o "$compiled" 2>/dev/null
  assert_eq "embedded AppleScript compiles" 0 $?
  rm -rf "${compiled:h}"
}

test_status_classification
test_connect_reads_once_and_clicks_once
test_connect_uses_japanese_button_label
test_disconnect_reads_once_and_clicks_once
test_disconnect_uses_japanese_button_label
test_connect_when_already_connected_does_not_click
test_connect_does_not_click_while_connecting
test_disconnect_does_not_click_while_disconnecting
test_refresh_with_confirmation
test_refresh_while_connecting
test_refresh_with_confirmation_pending
test_refresh_when_disconnected_does_not_click
test_refresh_in_other_states_does_not_click
test_refresh_requires_confirmation
test_refresh_fails_if_confirmation_click_errors
test_toggle_disconnects_when_connected
test_toggle_connects_when_disconnected
test_toggle_does_not_click_while_connecting
test_invalid_arguments
test_app_not_found
test_permission_error
test_closed_window_is_not_a_permission_error
test_embedded_applescript_compiles

if (( failures > 0 )); then
  print "$failures test(s) failed"
  exit 1
fi
print "all tests passed"
